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
import '../../domain/models/graph.dart';
import '../../domain/models/pipeline_event.dart';
import '../services/api_client.dart';
import '../services/local_store.dart';

class CardRepository extends ChangeNotifier {
  CardRepository({required ApiClient api, required LocalStore store})
      : _api = api,
        _store = store;

  final ApiClient _api;
  final LocalStore _store;

  ApiClient get api => _api;

  /// Submit a shared URL. On network failure the URL is queued locally and the
  /// caller is told it is pending (offline share queue, docs/06).
  Future<CreateCardResult> share(String url) async {
    try {
      final result = await _api.createCard(url);
      await flushPendingShares();
      notifyListeners();
      return result;
    } catch (_) {
      await _store.enqueueShare(url);
      notifyListeners();
      rethrow;
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
  /// previously-seen cards remain browsable offline. On success, silently
  /// restores any locally-cached cards missing from the server (e.g. after HF restart).
  Future<List<Card>> list({CardState? state}) async {
    try {
      final cards = await _api.listCards(state: state, limit: 100);
      for (final c in cards) {
        await _store.cacheCard(c.cardId, _rawOf(c));
      }
      // Fire-and-forget: restore phone-only cards back to server
      _syncMissingToServer(cards);
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

  /// Restore locally-cached READY cards that the server doesn't have.
  /// Runs silently in the background; errors are swallowed.
  Future<void> _syncMissingToServer(List<Card> serverCards) async {
    try {
      final serverUrls = serverCards.map((c) => c.source.url).toSet();
      final missing = _store
          .readAllCards()
          .map(Card.fromJson)
          .where((c) =>
              c.state == CardState.ready &&
              !serverUrls.contains(c.source.url))
          .toList();
      if (missing.isEmpty) return;
      await _api.importCards(missing.map(_rawOf).toList());
      // Refresh cache with new server-assigned IDs
      final refreshed = await _api.listCards(limit: 200);
      for (final c in refreshed) {
        await _store.cacheCard(c.cardId, _rawOf(c));
      }
      notifyListeners();
    } catch (_) {
      // Silent: will retry on next list() call
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

  Future<void> delete(String cardId) async {
    // Phone is source of truth: remove from cache first so the card is never
    // re-pushed to the server by _syncMissingToServer after a restart.
    await _store.removeCard(cardId);
    notifyListeners();
    try {
      await _api.deleteCard(cardId);
    } catch (_) {
      // Best-effort; card is already gone from local cache.
    }
  }

  Future<List<Card>> search(String query) => _api.search(query);

  /// Grounded chat over one card (docs/13). Network-only; the conversation is
  /// held in the view model and replayed each turn.
  Future<String> chat(String cardId, List<Map<String, String>> messages) =>
      _api.chat(cardId, messages);

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
  Future<LibraryChatResult> libraryChat(List<Map<String, String>> messages) =>
      _api.libraryChat(messages);

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
                'topic_map': card.insight!.topicMap == null
                    ? null
                    : {
                        'center': card.insight!.topicMap!.center,
                        'nodes': card.insight!.topicMap!.nodes,
                      },
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
