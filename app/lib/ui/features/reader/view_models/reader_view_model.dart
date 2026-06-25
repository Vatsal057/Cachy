/// Reader state (MVVM). Loads a card; while it is still processing it subscribes
/// to the SSE pipeline stream and re-fetches as stages complete (progressive
/// render). Checkable blocks toggle optimistically, then PATCH to persist.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../data/repositories/card_repository.dart';
import '../../../../domain/models/artifact.dart';
import '../../../../domain/models/card.dart';
import '../../../../domain/models/pipeline_event.dart';

class ReaderViewModel extends ChangeNotifier {
  ReaderViewModel({required CardRepository repository, required this.cardId})
      : _repository = repository;

  final CardRepository _repository;
  final String cardId;

  Card? _card;
  Card? get card => _card;

  Object? _error;
  Object? get error => _error;

  bool get isLoading => _card == null && _error == null;

  PipelineEvent? _lastEvent;
  PipelineEvent? get lastEvent => _lastEvent;

  List<CatalogEntry> _artifacts = const [];
  List<CatalogEntry> get artifacts => _artifacts;

  StreamSubscription<PipelineEvent>? _sub;
  bool _disposed = false;

  Future<void> init() async {
    // Seed from cache instantly if present (offline-first), then fetch.
    final cached = _repository.cachedCard(cardId);
    if (cached != null) {
      _card = cached;
      notifyListeners();
    }
    await _fetch();
    await _loadArtifacts();
    if (_card?.isProcessing ?? false) {
      _subscribe();
    }
  }

  /// The artifacts this card references — feeds both the inline `[[Name]]` links
  /// and the bottom References strip. Best-effort: failure leaves it empty.
  Future<void> _loadArtifacts() async {
    try {
      _artifacts = await _repository.cardArtifacts(cardId);
      _safeNotify();
    } catch (_) {
      // best-effort; inline links + strip simply stay absent.
    }
  }

  Future<void> _fetch() async {
    try {
      _card = await _repository.getCard(cardId);
      _error = null;
    } catch (e) {
      if (_card == null) _error = e;
    }
    _safeNotify();
  }

  void _subscribe() {
    _sub?.cancel();
    _sub = _repository.stream(cardId).listen(
      (event) async {
        _lastEvent = event;
        _safeNotify();
        // Re-fetch on persisting/terminal so newly-written base/blocks appear.
        if (event.stage == PipelineStage.persisting || event.isTerminal) {
          await _fetch();
        }
        if (event.isTerminal) {
          await _loadArtifacts(); // catalog populated after cards finish
          await _sub?.cancel();
        }
      },
      onError: (_) async {
        // Stream dropped (e.g. backend slept). Poll once as a fallback.
        await _fetch();
      },
      cancelOnError: false,
    );
  }

  /// Retry a failed load / reconnect.
  Future<void> retry() async {
    _error = null;
    _safeNotify();
    await _fetch();
    if (_card?.isProcessing ?? false) _subscribe();
  }

  // ----------------------------------------------------------------------- //
  // Checkable block persistence (optimistic + PATCH)
  // ----------------------------------------------------------------------- //

  Future<void> toggleChecklistItem(String blockId, int index, bool checked) async {
    final current = _card;
    if (current == null) return;
    final updated = current.toggleChecklistItem(blockId, index, checked);
    _applyOptimistic(current, updated);
    await _persist(current, updated);
  }

  Future<void> toggleStep(String blockId, int index, bool checked) async {
    final current = _card;
    if (current == null) return;
    final updated = current.toggleStep(blockId, index, checked);
    _applyOptimistic(current, updated);
    await _persist(current, updated);
  }

  // ----------------------------------------------------------------------- //
  // Action items (docs/13): follow the card's to-dos into the Actions hub,
  // then tick them off. Optimistic + PATCH, same pattern as checkable blocks.
  // ----------------------------------------------------------------------- //

  Future<void> setActionsFollowed(bool followed) async {
    final current = _card;
    if (current == null) return;
    final updated = ActionItems(followed: followed, items: current.actionItems.items);
    await _persistActions(current, updated);
  }

  Future<void> toggleActionItem(String itemId, bool done) async {
    final current = _card;
    if (current == null) return;
    final updated = ActionItems(
      followed: current.actionItems.followed,
      items: [
        for (final it in current.actionItems.items)
          it.id == itemId ? ActionItem(id: it.id, text: it.text, done: done) : it,
      ],
    );
    await _persistActions(current, updated);
  }

  Future<void> _persistActions(Card before, ActionItems updated) async {
    _card = before.copyWith(actionItems: updated); // optimistic
    _safeNotify();
    try {
      _card = await _repository.patchActionItems(cardId, updated.toJson());
    } catch (_) {
      _card = before; // revert on failure
    }
    _safeNotify();
  }

  void _applyOptimistic(Card current, List<Map<String, dynamic>> rawBlocks) {
    _card = Card.fromJson({
      ..._rawShallow(current),
      'blocks': rawBlocks,
    });
    _safeNotify();
  }

  Future<void> _persist(Card before, List<Map<String, dynamic>> rawBlocks) async {
    try {
      final saved = await _repository.patchBlocks(cardId, rawBlocks);
      _card = saved;
      _safeNotify();
    } catch (_) {
      _card = before; // revert on failure
      _safeNotify();
    }
  }

  Map<String, dynamic> _rawShallow(Card c) => {
        'schema_version': c.schemaVersion,
        'card_id': c.cardId,
        'state': c.state.wire,
        'failure_reason': c.failureReason?.name,
        'source': {
          'url': c.source.url,
          'platform': c.source.platform,
          'creator': c.source.creator,
          'caption': c.source.caption,
          'duration_seconds': c.source.durationSeconds,
          'resolver': c.source.resolver,
        },
        'base': {
          'one_liner': c.base.oneLiner,
          'tldr': c.base.tldr,
          'content_type': c.base.contentType.wire,
          'type_confidence': c.base.typeConfidence,
        },
        'primary_action': {
          'kind': c.primaryAction.kind.wire,
          'label': c.primaryAction.label,
          'payload': c.primaryAction.payload,
        },
        'media': {
          'thumbnail': c.media.thumbnail,
          'keyframes': c.media.keyframes,
        },
        'meta': {
          'created_at': c.meta.createdAt?.toIso8601String(),
          'extraction': {
            'transcript': c.meta.extraction.transcript,
            'ocr': c.meta.extraction.ocr,
            'visual': c.meta.extraction.visual,
          },
        },
      };

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    super.dispose();
  }
}
