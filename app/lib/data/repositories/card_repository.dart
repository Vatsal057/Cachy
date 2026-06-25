/// Single source of truth for cards (architecture skill: Repository pattern).
/// Consumes [ApiClient] + [LocalStore], transforms raw JSON into domain [Card]s,
/// caches for offline reading, and queues shares made while offline.
library;

import 'dart:convert';

import '../../domain/models/artifact.dart';
import '../../domain/models/card.dart';
import '../../domain/models/collection.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/graph.dart';
import '../../domain/models/pipeline_event.dart';
import '../services/api_client.dart';
import '../services/local_store.dart';

class CardRepository {
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
      return result;
    } catch (_) {
      await _store.enqueueShare(url);
      rethrow;
    }
  }

  /// Best-effort retry of shares captured while offline.
  Future<void> flushPendingShares() async {
    for (final url in _store.pendingShares()) {
      try {
        await _api.createCard(url);
        await _store.removeShare(url);
      } catch (_) {
        break; // still offline; keep the rest queued
      }
    }
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

  Stream<PipelineEvent> stream(String cardId) => _api.streamCard(cardId);

  /// Optimistically persist toggled checklist/step state. The full block list is
  /// PATCHed (server stores blocks JSON verbatim).
  Future<Card> patchBlocks(String cardId, List<Map<String, dynamic>> blocks) async {
    final card = await _api.patchCardBlocks(cardId, blocks);
    await _store.cacheCard(cardId, _rawOf(card));
    return card;
  }

  Future<void> delete(String cardId) async {
    await _api.deleteCard(cardId);
    await _store.removeCard(cardId);
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

  Future<void> deleteCatalogEntry(String artifactId) =>
      _api.deleteCatalogEntry(artifactId);

  /// Save a referenced artifact into the catalog tab (long-press to save).
  Future<CatalogEntry> saveCatalogEntry(String artifactId) =>
      _api.saveCatalogEntry(artifactId);

  /// Generate the on-demand LLM detail for a catalog item (Fetch info button).
  Future<CatalogEntry> fetchCatalogInfo(String artifactId) =>
      _api.fetchCatalogInfo(artifactId);

  /// Artifacts a single card references (docs/12) — reader "References" strip.
  Future<List<CatalogEntry>> cardArtifacts(String cardId) =>
      _api.cardArtifacts(cardId);

  /// The knowledge graph: cards as nodes, similarity as edges. Network-only.
  Future<GraphData> graph({double threshold = 0.55, int topK = 4}) =>
      _api.graph(threshold: threshold, topK: topK);

  /// Cross-card grounded Q&A (docs/09). Network-only; history held client-side.
  Future<LibraryChatResult> libraryChat(List<Map<String, String>> messages) =>
      _api.libraryChat(messages);

  // --- collections (docs/09) — user-created groups of cards --------------- //
  Future<List<Collection>> listCollections() => _api.listCollections();

  Future<CollectionDetail> getCollection(String id) => _api.getCollection(id);

  Future<Collection> createCollection(String name) =>
      _api.createCollection(name);

  Future<void> deleteCollection(String id) => _api.deleteCollection(id);

  Future<Collection> addCardToCollection(String id, String cardId) =>
      _api.addCardToCollection(id, cardId);

  Future<Collection> removeCardFromCollection(String id, String cardId) =>
      _api.removeCardFromCollection(id, cardId);

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
        'blocks': card.rawBlocks,
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
