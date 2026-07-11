/// Single source of truth for cards (architecture skill: Repository pattern).
/// Consumes [ApiClient] + [LocalStore], transforms raw JSON into domain [Card]s,
/// caches for offline reading, and queues shares made while offline.
library;

import 'dart:convert';
import 'package:flutter/foundation.dart';

import '../../domain/models/artifact.dart';
import '../../domain/models/card.dart';
import '../../domain/models/collection.dart';
import '../../domain/models/concept.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/feed.dart';
import '../../domain/models/graph.dart';
import '../../domain/models/pipeline_event.dart';
import '../services/api_client.dart';
import '../services/local_ai/local_ai_service.dart';
import '../services/local_store.dart';

class CardRepository extends ChangeNotifier {
  CardRepository({required ApiClient api, required LocalStore store})
      : _api = api,
        _store = store;

  final ApiClient _api;
  final LocalStore _store;

  ApiClient get api => _api;

  void updateBaseUrl(String url) {
    _api.setBaseUrl(url);
    notifyListeners();
  }

  Future<String?> discoverServer() async {
    final discovered = await _api.discoverAndUpdateBaseUrl();
    notifyListeners();
    return discovered;
  }

  /// Submit a shared URL. On network failure the URL is queued locally and the
  /// caller is told it is pending (offline share queue, docs/06).
  Future<CreateCardResult> share(String url) async {
    try {
      final result = await _api.createCard(url);
      await flushPendingShares();
      notifyListeners();
      return result;
    } catch (e) {
      if (e is! ApiException) {
        await _store.enqueueShare(url);
      }
      notifyListeners();
      rethrow;
    }
  }

  /// Upgrade a quota-degraded paragraph card by structuring its stored bundle
  /// on-device and uploading the result (V2 on-device AI).
  ///
  /// Returns true when the card was upgraded. Every failure path returns false
  /// silently — the paragraph card is never made worse.
  Future<bool> upgradeOnDevice(String cardId, LocalAiService ai) async {
    if (!ai.canStructure) return false;
    try {
      final stored = await _api.getBundle(cardId);
      if (stored == null || (stored['bundle'] ?? '').isEmpty) return false;
      final generated = await ai.structureBundle(
        stored['bundle']!,
        transcript: stored['transcript'] ?? '',
        caption: stored['caption'] ?? '',
      );
      if (generated == null) return false;
      final card = await _api.uploadStructure(cardId, generated);
      await _store.cacheCard(card.cardId, _rawOf(card));
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('on-device upgrade failed for $cardId: $e');
      return false;
    }
  }

  /// Best-effort retry of shares captured while offline.
  Future<void> flushPendingShares() async {
    bool flushed = false;
    for (final url in _store.pendingShares()) {
      try {
        await _api.createCard(url);
        await _store.removeShare(url);
        flushed = true;
      } catch (_) {
        break; // still offline; keep the rest queued
      }
    }
    if (flushed) notifyListeners();
  }

  /// Library listing. Falls back to the local cache when the network is down so
  /// previously-seen cards remain browsable offline.
  Future<List<Card>> list({CardState? state}) async {
    try {
      final cards = await _api.listCards(state: state, limit: 100);
      for (final c in cards) {
        await _store.cacheCard(c.cardId, _rawOf(c));
      }
      return cards;
    } catch (_) {
      final cached = _store.readAllCards().map(Card.fromJson).toList()
        ..sort((a, b) => (b.meta.createdAt ?? DateTime(0))
            .compareTo(a.meta.createdAt ?? DateTime(0)));
      if (cached.isEmpty) rethrow;
      return state == null
          ? cached
          : cached.where((c) => c.state == state).toList();
    }
  }

  /// Every card, paginated to bypass the per-request cap (export/backup).
  /// Falls back to the full offline cache if the network is down.
  Future<List<Card>> listAll() async {
    const page = 200; // matches backend `le=200`
    try {
      final all = <Card>[];
      for (var offset = 0;; offset += page) {
        final batch = await _api.listCards(limit: page, offset: offset);
        for (final c in batch) {
          await _store.cacheCard(c.cardId, _rawOf(c));
        }
        all.addAll(batch);
        if (batch.length < page) break;
      }
      return all;
    } catch (_) {
      final cached = _store.readAllCards().map(Card.fromJson).toList()
        ..sort((a, b) => (b.meta.createdAt ?? DateTime(0))
            .compareTo(a.meta.createdAt ?? DateTime(0)));
      if (cached.isEmpty) rethrow;
      return cached;
    }
  }

  /// Fetch one card; serves the cache on network failure (offline reading).
  Future<Card> getCard(String cardId) async {
    try {
      final card = await _api.getCard(cardId);
      await _store.cacheCard(cardId, _rawOf(card));
      return card;
    } catch (_) {
      final cached = _store.readCard(cardId);
      if (cached != null) return Card.fromJson(cached);
      rethrow;
    }
  }

  Card? cachedCard(String cardId) {
    final json = _store.readCard(cardId);
    return json == null ? null : Card.fromJson(json);
  }

  Stream<PipelineEvent> stream(String cardId) {
    return _api.streamCard(cardId).map((event) {
      if (event.isTerminal) {
        notifyListeners();
      }
      return event;
    });
  }

  /// Optimistically persist toggled checklist/step state. The full block list is
  /// PATCHed (server stores blocks JSON verbatim).
  Future<Card> patchBlocks(String cardId, List<Map<String, dynamic>> blocks) async {
    final card = await _api.patchCardBlocks(cardId, blocks);
    await _store.cacheCard(cardId, _rawOf(card));
    notifyListeners();
    return card;
  }

  /// Persist the card's action list (docs/13) — follow toggle + per-item done.
  Future<Card> patchActionItems(
      String cardId, Map<String, dynamic> actionItems) async {
    final card = await _api.patchCardActionItems(cardId, actionItems);
    await _store.cacheCard(cardId, _rawOf(card));
    notifyListeners();
    return card;
  }

  /// Clear all locally cached cards. Returns how many were removed.
  Future<int> clearCardCache() => _store.clearCardCache();

  Future<void> delete(String cardId) async {
    await _store.removeCard(cardId);
    try {
      await _api.deleteCard(cardId);
    } catch (_) {
      // Best-effort; card is already gone from local cache.
    }
    notifyListeners();
  }

  Future<List<Card>> search(String query) => _api.search(query);

  /// Grounded chat over one card (docs/13). Network-only; the conversation is
  /// held in the view model and replayed each turn. Persisted server-side per
  /// owner (docs/14).
  Future<String> chat(String cardId, List<Map<String, String>> messages) =>
      _api.chat(cardId, messages);

  /// Restore the saved chat for a card (docs/14), owner-scoped.
  Future<List<Map<String, String>>> chatHistory(String cardId) =>
      _api.chatHistory(cardId);

  /// Explore one thread of the rabbit hole (docs/14). Network-only; the
  /// exploration trail is held in the view model and replayed each turn.
  /// Persisted server-side per owner, keyed by [root].
  Future<RabbitHoleStep> exploreRabbitHole(
          String cardId, String topic, List<String> trail, String root) =>
      _api.exploreRabbitHole(cardId, topic, trail, root);

  /// Restore the saved rabbit-hole trail for a card + [root] topic (docs/14).
  Future<List<RabbitHoleStep>> rabbitHoleHistory(String cardId, String root) =>
      _api.rabbitHoleHistory(cardId, root);

  /// The aggregated artifact catalog (docs/12). Network-only for now — these
  /// are remote-thumbnail entries with no offline-render requirement.
  Future<List<CatalogEntry>> catalog({ArtifactType? type}) =>
      _api.listCatalog(type: type);

  Future<void> deleteCatalogEntry(String artifactId) async {
    await _api.deleteCatalogEntry(artifactId);
    notifyListeners();
  }

  /// Save a referenced artifact into the catalog tab (long-press to save).
  Future<CatalogEntry> saveCatalogEntry(String artifactId) async {
    final res = await _api.saveCatalogEntry(artifactId);
    notifyListeners();
    return res;
  }

  /// Generate the on-demand LLM detail for a catalog item (Fetch info button).
  Future<CatalogEntry> fetchCatalogInfo(String artifactId) async {
    final res = await _api.fetchCatalogInfo(artifactId);
    notifyListeners();
    return res;
  }

  /// Artifacts a single card references (docs/12) — reader "References" strip.
  Future<List<CatalogEntry>> cardArtifacts(String cardId) =>
      _api.cardArtifacts(cardId);

  // ---- Collections --------------------------------------------------------- //

  Future<List<CollectionEntry>> listCollections() => _api.listCollections();

  Future<CollectionEntry> renameCollection(String id, String name) async {
    final res = await _api.renameCollection(id, name);
    notifyListeners();
    return res;
  }

  Future<CollectionEntry> createCollection(String name) async {
    final res = await _api.createCollection(name);
    notifyListeners();
    return res;
  }

  Future<void> moveCardToCollection(String cardId, String? collectionId) async {
    await _api.moveCardToCollection(cardId, collectionId);
    notifyListeners();
  }

  Future<List<Card>> listByCollection(String collectionId, {int limit = 100}) =>
      _api.listCards(collectionId: collectionId, limit: limit);

  // -------------------------------------------------------------------------- //

  /// The knowledge graph: cards as nodes, similarity as edges. Network-only.
  Future<GraphData> graph({double threshold = 0.55, int topK = 4}) =>
      _api.graph(threshold: threshold, topK: topK);

  /// Cross-card grounded Q&A (docs/09). Network-only; history held client-side.
  /// Persisted server-side per owner (docs/14).
  Future<LibraryChatResult> libraryChat(List<Map<String, String>> messages) =>
      _api.libraryChat(messages);

  /// Restore the saved library chat (docs/14), owner-scoped.
  Future<List<Map<String, String>>> libraryChatHistory() =>
      _api.libraryChatHistory();

  // ---- Knowledge Feed + Connections --------------------------------------- //

  /// The reel-style knowledge feed assembled from the owner's cards.
  Future<List<FeedItem>> feed({int limit = 40}) => _api.feed(limit: limit);

  /// Surprising connections between the owner's cards (serendipity engine).
  Future<List<Connection>> connections({int limit = 12, bool refresh = false}) =>
      _api.connections(limit: limit, refresh: refresh);

  // ---- Concepts ------------------------------------------------------------ //

  /// All deduplicated concepts in the library.
  Future<List<ConceptEntry>> concepts() => _api.listConcepts();

  /// Concepts extracted from a single card (reader strip).
  Future<List<ConceptEntry>> cardConcepts(String cardId) =>
      _api.listConcepts(cardId: cardId);

  /// Concept detail including server-computed related concepts.
  Future<ConceptDetail> conceptDetail(String conceptId) =>
      _api.getConcept(conceptId);

  /// Generate + persist an on-demand definition for a concept.
  Future<ConceptEntry> defineConcept(String conceptId) async {
    final res = await _api.defineConcept(conceptId);
    notifyListeners();
    return res;
  }

  Future<void> deleteConcept(String conceptId) async {
    await _api.deleteConcept(conceptId);
    notifyListeners();
  }


  /// Reconstruct the raw JSON for caching. Uses preserved `rawBlocks` so block
  /// state round-trips losslessly.
  Map<String, dynamic> _rawOf(Card card) => {
        'schema_version': card.schemaVersion,
        'card_id': card.cardId,
        'state': card.state.wire,
        'failure_reason': card.failureReason?.name,
        'source': {
          'url': card.source.url,
          'platform': card.source.platform,
          'creator': card.source.creator,
          'caption': card.source.caption,
          'duration_seconds': card.source.durationSeconds,
          'resolver': card.source.resolver,
        },
        'base': {
          'one_liner': card.base.oneLiner,
          'tldr': card.base.tldr,
          'content_type': card.base.contentType.wire,
          'type_confidence': card.base.typeConfidence,
          'tags': card.base.tags,
        },
        'primary_action': {
          'kind': card.primaryAction.kind.wire,
          'label': card.primaryAction.label,
          'payload': card.primaryAction.payload,
        },
        'action_items': card.actionItems.toJson(),
        'blocks': card.rawBlocks,
        'insight': card.insight == null
            ? null
            : {
                'rabbit_hole': {
                  'questions': card.insight!.rabbitHole.questions,
                  'adjacent_topics': card.insight!.rabbitHole.adjacentTopics,
                  'advanced_concepts': card.insight!.rabbitHole.advancedConcepts,
                },
                'quiz': [
                  for (final q in card.insight!.quiz.questions)
                    {
                      'question': q.question,
                      'options': q.options,
                      'answer_index': q.answerIndex,
                      'explanation': q.explanation,
                    },
                ],
                'deep_research_prompt': card.insight!.deepResearchPrompt,
              },
        'collection_id': card.collectionId,
        'media': {
          'thumbnail': card.media.thumbnail,
          'keyframes': card.media.keyframes,
        },
        'meta': {
          'created_at': card.meta.createdAt?.toIso8601String(),
          'extraction': {
            'transcript': card.meta.extraction.transcript,
            'ocr': card.meta.extraction.ocr,
            'visual': card.meta.extraction.visual,
          },
        },
      };
}

/// Helpers for mutating block JSON for PATCH while preserving unknown fields.
extension BlockJsonMutation on Card {
  /// Returns a deep copy of [rawBlocks] with the checklist item at
  /// (blockId, itemIndex) toggled to [checked].
  List<Map<String, dynamic>> toggleChecklistItem(
    String blockId,
    int itemIndex,
    bool checked,
  ) {
    final copy = _deepCopyBlocks(rawBlocks);
    for (final b in copy) {
      if (b['id'] == blockId && b['type'] == 'checklist') {
        final items = (b['items'] as List?) ?? const [];
        if (itemIndex >= 0 && itemIndex < items.length) {
          (items[itemIndex] as Map<String, dynamic>)['checked'] = checked;
        }
      }
    }
    return copy;
  }

  /// Returns a deep copy of [rawBlocks] with the step at (blockId, stepIndex)
  /// toggled to [checked].
  List<Map<String, dynamic>> toggleStep(
    String blockId,
    int stepIndex,
    bool checked,
  ) {
    final copy = _deepCopyBlocks(rawBlocks);
    for (final b in copy) {
      if (b['id'] == blockId && b['type'] == 'step_list') {
        final steps = (b['steps'] as List?) ?? const [];
        if (stepIndex >= 0 && stepIndex < steps.length) {
          (steps[stepIndex] as Map<String, dynamic>)['checked'] = checked;
        }
      }
    }
    return copy;
  }
}

List<Map<String, dynamic>> _deepCopyBlocks(List<Map<String, dynamic>> blocks) =>
    (jsonDecode(jsonEncode(blocks)) as List)
        .whereType<Map<String, dynamic>>()
        .toList();
