/// The transparent pipeline (docs/01, docs/06): a stepped track showing
/// Downloading → Extracting → Structuring → Finishing as SSE stages arrive, so
/// the user sees the work happening. Shared by the share receiver and the
/// reader's processing state.
///
/// Branded: done nodes fill with the brand gradient, the active node pulses, and
/// connectors fill as work advances — the signature "watch the magic" moment.
library;

import 'package:flutter/material.dart';

import '../../../domain/models/pipeline_event.dart';

class PipelineProgress extends StatelessWidget {
  const PipelineProgress({
    super.key,
    required this.current,
    this.detail = '',
  });

  final PipelineStage current;
  final String detail;

  int get _currentIndex {
    final i = PipelineStage.track.indexOf(current);
    if (i >= 0) return i;
    // snapshot → before step 0; done/persisting → complete.
    if (current == PipelineStage.done) return PipelineStage.track.length;
    if (current == PipelineStage.snapshot) return -1;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final idx = _currentIndex;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < PipelineStage.track.length; i++)
          _StageRow(
            label: PipelineStage.track[i].label,
            done: i < idx,
            active: i == idx,
            detail: i == idx ? detail : '',
            isLast: i == PipelineStage.track.length - 1,
          ),
        if (detail.isNotEmpty && idx < 0)
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 40),
            child: Text(detail, style: theme.textTheme.bodySmall),
          ),
      ],
    );
  }
}

class _StageRow extends StatelessWidget {
  const _StageRow({
    required this.label,
    required this.done,
    required this.active,
    required this.detail,
    required this.isLast,
  });

  final String label;
  final bool done;
  final bool active;
  final String detail;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final lit = done || active;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              _node(scheme),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2.5,
                    margin: const EdgeInsets.symmetric(vertical: 3),
                    decoration: BoxDecoration(
                      color: done ? scheme.primary : scheme.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 5, bottom: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: active ? FontWeight.w800 : FontWeight.w500,
                      color: lit ? scheme.onSurface : scheme.onSurfaceVariant,
                    ),
                  ),
                  if (active && detail.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(detail,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant)),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _node(ColorScheme scheme) {
    if (done) {
      return Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: Icon(Icons.check_rounded, size: 17, color: scheme.onPrimary),
      );
    }
    if (active) {
      return Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: SizedBox(
          width: 13,
          height: 13,
          child: CircularProgressIndicator(
            strokeWidth: 2.2,
            valueColor: AlwaysStoppedAnimation(scheme.onPrimary),
          ),
        ),
      );
    }
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        shape: BoxShape.circle,
        border: Border.all(color: scheme.outlineVariant),
      ),
    );
  }
}
