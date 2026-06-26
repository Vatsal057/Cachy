/// Compact state badge for the library grid (docs/06): queued / processing /
/// ready / failed. Ready cards show no badge — the face speaks for itself.
library;

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../domain/models/enums.dart';

class StateBadge extends StatelessWidget {
  const StateBadge({super.key, required this.state, this.reason});
  final CardState state;
  final FailureReason? reason;

  @override
  Widget build(BuildContext context) {
    if (state == CardState.ready) return const SizedBox.shrink();
    final (label, color, icon, spin) = _spec();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (spin)
            const SizedBox(
              width: 11,
              height: 11,
              child: CircularProgressIndicator(
                strokeWidth: 1.8,
                valueColor: AlwaysStoppedAnimation(Colors.white),
              ),
            )
          else
            PhosphorIcon(icon, size: 13, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  (String, Color, PhosphorIconData, bool) _spec() {
    switch (state) {
      case CardState.queued:
        return ('Queued', Colors.white70, PhosphorIconsRegular.clock, false);
      case CardState.processing:
        return ('Working', Colors.white, PhosphorIconsRegular.lightning, true);
      case CardState.failed:
        return (
          reason?.label ?? 'Failed',
          const Color(0xFFFF8A7A),
          PhosphorIconsRegular.warning,
          false
        );
      case CardState.ready:
        return ('Ready', Colors.white, PhosphorIconsRegular.check, false);
    }
  }
}
