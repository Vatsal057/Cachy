/// The Verdict Timeline (backend schema 1.8): per-window factual-claim
/// verdicts with dated evidence, rendered inside the card view. Each claim
/// gets a verdict tick — green (corroborated), amber (single source), red
/// (contradicted), grey (not enough evidence) — plus the sources behind it
/// as tappable chips. A re-check button re-runs the agent live.
library;

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../domain/models/verdict.dart';
import '../../../core/brand.dart';
import '../../../core/content_accent.dart';

/// Semantic verdict colors — fixed hues that read in light and dark mode.
Color _verdictColor(String verdict, ColorScheme scheme) {
  switch (verdict) {
    case 'green':
      return const Color(0xFF2E9E5B);
    case 'amber':
      return const Color(0xFFD9930D);
    case 'red':
      return const Color(0xFFE5484D);
    default:
      return scheme.outline;
  }
}

String _verdictLabel(String verdict) {
  switch (verdict) {
    case 'green':
      return 'Confirmed';
    case 'amber':
      return 'One source';
    case 'red':
      return 'Contradicted';
    default:
      return 'Unverified';
  }
}

String _formatDate(DateTime? dt) {
  if (dt == null) return '';
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
}

class VerdictSection extends StatefulWidget {
  const VerdictSection({
    super.key,
    required this.cardId,
    required this.timeline,
    required this.accent,
    required this.api,
  });

  final String cardId;
  final VerdictTimeline timeline;
  final ContentAccent accent;

  /// ApiClient — dynamic like _FaceAppBar to avoid import cycles.
  final dynamic api;

  @override
  State<VerdictSection> createState() => _VerdictSectionState();
}

class _VerdictSectionState extends State<VerdictSection> {
  late VerdictTimeline _timeline;
  bool _rechecking = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _timeline = widget.timeline;
  }

  Future<void> _recheck() async {
    if (_rechecking) return;
    setState(() {
      _rechecking = true;
      _error = null;
    });
    try {
      final fresh =
          await widget.api.recheckVerdicts(widget.cardId) as VerdictTimeline;
      if (!mounted) return;
      setState(() => _timeline = fresh);
    } catch (_) {
      if (!mounted) return;
      setState(
          () => _error = 'Re-check failed. Showing the last verified timeline.');
    } finally {
      if (mounted) setState(() => _rechecking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final counts = _timeline.counts;
    final summaryParts = <String>[];
    if ((counts['green'] ?? 0) > 0) {
      summaryParts.add("${counts['green']} confirmed");
    }
    if ((counts['amber'] ?? 0) > 0) {
      summaryParts.add("${counts['amber']} one source");
    }
    if ((counts['red'] ?? 0) > 0) {
      summaryParts.add("${counts['red']} contradicted");
    }
    if ((counts['grey'] ?? 0) > 0) {
      summaryParts.add("${counts['grey']} unverified");
    }
    final checked = _formatDate(_timeline.checkedAt);

    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              PhosphorIcon(PhosphorIconsRegular.sealCheck,
                  size: 16, color: widget.accent.color),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  'VERDICT TIMELINE',
                  style: Brand.label(
                      size: 11,
                      color: widget.accent.color,
                      weight: FontWeight.w700),
                ),
              ),
              TextButton.icon(
                onPressed: _rechecking ? null : _recheck,
                icon: _rechecking
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const PhosphorIcon(PhosphorIconsRegular.arrowClockwise,
                        size: 14),
                label: Text(_rechecking ? 'Checking' : 'Re-check'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            [
              if (checked.isNotEmpty) 'Checked $checked',
              '${_timeline.claims.length} claims',
              ...summaryParts,
            ].join('  ·  '),
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.error),
            ),
          ],
          const SizedBox(height: 14),
          for (var i = 0; i < _timeline.claims.length; i++)
            _VerdictRow(
              claim: _timeline.claims[i],
              isLast: i == _timeline.claims.length - 1,
            ),
        ],
      ),
    );
  }
}

class _VerdictRow extends StatelessWidget {
  const _VerdictRow({required this.claim, required this.isLast});

  final ClaimVerdict claim;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = _verdictColor(claim.verdict, scheme);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Timeline rail: verdict dot + connecting line.
          SizedBox(
            width: 20,
            child: Column(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  margin: const EdgeInsets.only(top: 4),
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: scheme.outlineVariant,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '${claim.windowLabel}  ·  ${_verdictLabel(claim.verdict)}',
                          style: Brand.label(
                              size: 10, color: color, weight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    claim.claim,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  if (claim.note.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      claim.note,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                  if (claim.evidence.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final ev in claim.evidence)
                          _EvidenceChip(evidence: ev),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EvidenceChip extends StatelessWidget {
  const _EvidenceChip({required this.evidence});

  final VerdictEvidence evidence;

  Future<void> _open() async {
    final uri = Uri.tryParse(evidence.link);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = evidence.displaySource.isNotEmpty
        ? evidence.displaySource
        : 'Source';
    final sub = evidence.date.isNotEmpty ? ' · ${evidence.date}' : '';
    return Material(
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _open,
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$label$sub',
                style: Brand.label(
                    size: 11,
                    color: scheme.onSurfaceVariant,
                    weight: FontWeight.w600),
              ),
              const SizedBox(width: 4),
              PhosphorIcon(PhosphorIconsRegular.arrowSquareOut,
                  size: 12, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
