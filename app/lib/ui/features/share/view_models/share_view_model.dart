/// Share-receiver state (MVVM): the visible pipeline (docs/06). Submits a shared
/// or pasted URL, then surfaces live stage progress from the SSE stream so the
/// user watches the work instead of waiting blindly.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../data/repositories/card_repository.dart';
import '../../../../data/services/api_client.dart';
import '../../../../data/services/local_ai/local_ai_service.dart';
import '../../../../domain/models/pipeline_event.dart';

enum ShareStatus {
  idle,
  submitting,
  processing,

  /// Past quota + local model installed: structuring on the user's phone
  /// before opening the reader (V2 on-device AI).
  generatingLocally,
  ready,
  failed,
  queuedOffline,
}

class ShareViewModel extends ChangeNotifier {
  ShareViewModel({required CardRepository repository, LocalAiService? localAi})
      : _repository = repository,
        _localAi = localAi;

  final CardRepository _repository;
  final LocalAiService? _localAi;
  bool _quotaDegraded = false;

  ShareStatus _status = ShareStatus.idle;
  ShareStatus get status => _status;

  String? _cardId;
  String? get cardId => _cardId;

  PipelineStage _stage = PipelineStage.snapshot;
  PipelineStage get stage => _stage;

  String _detail = '';
  String get detail => _detail;

  String? _failureReason;
  String? get failureReason => _failureReason;

  String? _error;
  String? get error => _error;

  StreamSubscription<PipelineEvent>? _sub;
  bool _disposed = false;

  /// Submit a URL. Returns the resulting card id (existing card if deduped).
  Future<String?> submit(String url) async {
    final cleaned = url.trim();
    if (cleaned.isEmpty) return null;
    _status = ShareStatus.submitting;
    _error = null;
    _failureReason = null;
    notifyListeners();

    try {
      final result = await _repository.share(cleaned);
      _cardId = result.cardId;
      _quotaDegraded = result.quotaDegraded;
      if (result.cached) {
        // Deduped — card already exists; jump straight to it.
        _status = ShareStatus.ready;
        notifyListeners();
        return _cardId;
      }
      _status = ShareStatus.processing;
      notifyListeners();
      _watch(result.cardId);
      return _cardId;
    } catch (e) {
      if (e is ApiException) {
        _status = ShareStatus.failed;
        _failureReason = e.friendlyMessage;
      } else {
        // Network down: repository has queued the share for later.
        _status = ShareStatus.queuedOffline;
        _error = friendlyError(e);
      }
      notifyListeners();
      return null;
    }
  }

  void _watch(String cardId) {
    _sub?.cancel();
    _sub = _repository.stream(cardId).listen(
      (event) {
        _stage = event.stage;
        _detail = event.detail;
        if (event.isTerminal) {
          if (event.state.name == 'failed') {
            _status = ShareStatus.failed;
            _failureReason = event.reason;
          } else if (_quotaDegraded && (_localAi?.canStructure ?? false)) {
            _upgradeOnDevice(cardId);
          } else {
            _status = ShareStatus.ready;
          }
        }
        _safeNotify();
      },
      onError: (e) {
        _error = friendlyError(e);
        _safeNotify();
      },
      cancelOnError: false,
    );
  }

  /// Structure the degraded card on-device, then open it. Failure is silent —
  /// the paragraph card is already READY and never made worse.
  Future<void> _upgradeOnDevice(String cardId) async {
    _status = ShareStatus.generatingLocally;
    _safeNotify();
    await _repository.upgradeOnDevice(cardId, _localAi!);
    _status = ShareStatus.ready;
    _safeNotify();
  }

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
