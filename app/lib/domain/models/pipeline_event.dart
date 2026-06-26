/// A single SSE stage event from `GET /cards/{id}/stream`, mirroring the backend
/// StageEvent (backend services/events.py). Drives the transparent-pipeline UI.
library;

import 'enums.dart';

enum PipelineStage {
  snapshot,
  downloading,
  extracting,
  structuring,
  persisting,
  analyzing,
  done,
  failed,
  unknown;

  static PipelineStage fromWire(String? value) {
    switch (value) {
      case 'snapshot':
        return PipelineStage.snapshot;
      case 'downloading':
        return PipelineStage.downloading;
      case 'extracting':
        return PipelineStage.extracting;
      case 'structuring':
        return PipelineStage.structuring;
      case 'persisting':
        return PipelineStage.persisting;
      case 'analyzing':
        return PipelineStage.analyzing;
      case 'done':
        return PipelineStage.done;
      case 'failed':
        return PipelineStage.failed;
      default:
        return PipelineStage.unknown;
    }
  }

  /// User-facing label for the progress UI (docs/06 visible pipeline).
  String get label {
    switch (this) {
      case PipelineStage.snapshot:
        return 'Starting';
      case PipelineStage.downloading:
        return 'Downloading';
      case PipelineStage.extracting:
        return 'Extracting';
      case PipelineStage.structuring:
        return 'Structuring';
      case PipelineStage.persisting:
        return 'Finishing';
      case PipelineStage.analyzing:
        return 'Analyzing';
      case PipelineStage.done:
        return 'Ready';
      case PipelineStage.failed:
        return 'Failed';
      case PipelineStage.unknown:
        return 'Working';
    }
  }

  /// A fixed one-line subtitle describing what each step does — shown beneath the
  /// label so the pipeline reads as a narrated sequence, not bare keywords.
  String get description {
    switch (this) {
      case PipelineStage.snapshot:
        return 'Getting ready';
      case PipelineStage.downloading:
        return 'Fetching the video source';
      case PipelineStage.extracting:
        return 'Transcript + on-screen text';
      case PipelineStage.structuring:
        return 'Building your knowledge card';
      case PipelineStage.persisting:
        return 'Saving to your library';
      case PipelineStage.analyzing:
        return 'Surfacing deeper insight';
      case PipelineStage.done:
        return 'Card ready';
      case PipelineStage.failed:
        return 'Something went wrong';
      case PipelineStage.unknown:
        return '';
    }
  }

  /// Ordered pipeline steps shown as a progress track (excludes terminal/meta).
  static const List<PipelineStage> track = [
    PipelineStage.downloading,
    PipelineStage.extracting,
    PipelineStage.structuring,
    PipelineStage.persisting,
  ];
}

class PipelineEvent {
  const PipelineEvent({
    required this.cardId,
    required this.stage,
    required this.state,
    this.detail = '',
    this.reason,
  });

  final String cardId;
  final PipelineStage stage;
  final CardState state;
  final String detail;
  final String? reason;

  bool get isTerminal =>
      state == CardState.ready || state == CardState.failed;

  factory PipelineEvent.fromJson(Map<String, dynamic> json) => PipelineEvent(
        cardId: (json['card_id'] as String?) ?? '',
        stage: PipelineStage.fromWire(json['stage'] as String?),
        state: CardState.fromWire(json['state'] as String?),
        detail: (json['detail'] as String?) ?? '',
        reason: json['reason'] as String?,
      );
}
