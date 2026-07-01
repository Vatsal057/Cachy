/// A single library tile: a content-visual face with a calm scrim carrying the
/// one-liner and a state badge. Tapping opens the reader via a shared-element
/// transition on the face (docs/07 motion token).
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../data/services/api_client.dart';
import '../../../../domain/models/card.dart' as model;
import '../../../core/brand.dart';
import '../../../core/content_accent.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/card_face.dart';
import '../../../core/widgets/context_menu.dart';
import '../../../core/widgets/state_badge.dart';

class CardTile extends StatefulWidget {
  const CardTile({
    super.key,
    required this.card,
    required this.api,
    required this.onTap,
    required this.onDelete,
    this.confirmTitle = 'Delete card?',
    this.confirmBody = 'This removes the card and its media.',
    this.confirmAction = 'Delete',
    this.selected = false,
    this.onSelectToggle,
    this.onRangeSelect,
    this.onEnterSelectionMode,
    this.onOpenInNewTab,
    this.focusNode,
  });

  final model.Card card;
  final ApiClient api;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  /// Long-press confirm copy; overridable so the same tile can mean "remove"
  /// rather than "delete the card" depending on context.
  final String confirmTitle;
  final String confirmBody;
  final String confirmAction;

  /// Whether this tile is currently part of a multi-selection.
  final bool selected;

  /// Called when the user Ctrl/Cmd-clicks or taps while in selection mode.
  final VoidCallback? onSelectToggle;

  /// Called when the user Shift-clicks (range select).
  final VoidCallback? onRangeSelect;

  /// Called on long-press on mobile to enter selection mode.
  final VoidCallback? onEnterSelectionMode;

  /// Optional desktop-only "open in new tab" callback; hidden in menu when null.
  final Future<void> Function()? onOpenInNewTab;

  /// Optional external [FocusNode] for programmatic focus management (e.g.,
  /// arrow-key grid navigation from a parent widget).
  final FocusNode? focusNode;

  @override
  State<CardTile> createState() => _CardTileState();
}

class _CardTileState extends State<CardTile> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = ContentAccent.of(widget.card.base.contentType);
    final title = widget.card.base.oneLiner.isNotEmpty
        ? widget.card.base.oneLiner
        : (widget.card.isProcessing ? 'Working on it…' : 'Untitled');

    final tile = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        onLongPress: widget.onEnterSelectionMode != null
            ? () => widget.onEnterSelectionMode!()
            : () => _confirmDelete(context),
        onSecondaryTapDown: (TapDownDetails d) =>
            _showContextMenu(context, d.globalPosition),
        behavior: HitTestBehavior.opaque,
        child: AnimatedScale(
          scale: _hovered ? 1.025 : 1.0,
          duration: Motion.fast,
          curve: Motion.spring,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              boxShadow: _hovered
                  ? [
                      BoxShadow(
                        color: accent.color.withValues(alpha: 0.28),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ]
                  : null,
              border: _hovered
                  ? Border.all(
                      color: Colors.white.withValues(alpha: 0.35), width: 1.2)
                  : null,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Hero(
                    tag: 'card-face-${widget.card.cardId}',
                    child: CardFace(card: widget.card, api: widget.api),
                  ),
                  // Bottom scrim so text stays legible over any face.
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.45),
                          Colors.black.withValues(alpha: 0.88),
                        ],
                        stops: const [0.35, 0.65, 1.0],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 12,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            PhosphorIcon(accent.icon,
                                size: 13, color: Colors.white70),
                            const SizedBox(width: 5),
                            Flexible(
                              child: Text(
                                widget.card.base.contentType.label
                                    .toUpperCase(),
                                style: Brand.label(
                                    size: 9,
                                    color: Colors.white70,
                                    weight: FontWeight.w700),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (widget.card.base.tags.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              Container(
                                constraints:
                                    const BoxConstraints(maxWidth: 64),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  widget.card.base.tags.first,
                                  style: Brand.label(
                                      size: 7.5,
                                      color: Colors.white60,
                                      weight: FontWeight.w600),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 5),
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: Colors.white,
                            height: 1.15,
                          ),
                        ),
                        if (widget.card.isReady) _MetaPills(card: widget.card),
                      ],
                    ),
                  ),
                  Positioned(
                    top: 10,
                    right: 10,
                    child: StateBadge(
                      state: widget.card.state,
                      reason: widget.card.failureReason,
                    ),
                  ),
                  // Selection overlay — drawn when this tile is selected.
                  if (widget.selected) ...[
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          border:
                              Border.all(color: scheme.primary, width: 2.5),
                          color: scheme.primary.withValues(alpha: 0.12),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 10,
                      left: 10,
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          shape: BoxShape.circle,
                        ),
                        child: PhosphorIcon(
                          PhosphorIconsRegular.check,
                          size: 14,
                          color: scheme.onPrimary,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );

    return FocusableActionDetector(
      focusNode: widget.focusNode,
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onTap();
            return null;
          },
        ),
      },
      onShowFocusHighlight: (focused) => setState(() => _focused = focused),
      child: Stack(
        children: [
          tile,
          // Focus ring — overlaid outside the ClipRRect so it is fully visible.
          if (_focused)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: scheme.primary, width: 2.5),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _showContextMenu(
      BuildContext context, Offset globalPosition) async {
    final isDesktopPlatform =
        !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

    final actions = buildCardMenuActions(
      isDesktopPlatform: isDesktopPlatform,
      onOpen: () async => widget.onTap(),
      onOpenNewTab: () async => widget.onOpenInNewTab?.call(),
      onCopyLink: () async {
        final url = widget.card.source.url;
        if (url.isNotEmpty) {
          await Clipboard.setData(ClipboardData(text: url));
        } else {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('No link available')),
            );
          }
        }
      },
      onDelete: () async => widget.onDelete(),
    );

    await showCardContextMenu(
      context: context,
      globalPosition: globalPosition,
      actions: actions,
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(widget.confirmTitle),
        content: Text(widget.confirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(widget.confirmAction),
          ),
        ],
      ),
    );
    if (ok == true) widget.onDelete();
  }
}

/// Compact at-a-glance counts on a tile scrim — how much a card carries before
/// you open it (actions to do, steps inside, deeper analysis). Renders nothing
/// when the card has none.
class _MetaPills extends StatelessWidget {
  const _MetaPills({required this.card});
  final model.Card card;

  @override
  Widget build(BuildContext context) {
    final actions = card.actionItems.items.length;
    var steps = 0;
    for (final b in card.rawBlocks) {
      final type = b['type'];
      if (type == 'step_list') steps += (b['steps'] as List?)?.length ?? 0;
      if (type == 'checklist') steps += (b['items'] as List?)?.length ?? 0;
    }
    final hasInsight = card.insight?.hasContent ?? false;

    final pills = <String>[
      if (actions > 0) '$actions ${actions == 1 ? 'action' : 'actions'}',
      if (steps > 0) '$steps steps',
    ];
    if (pills.isEmpty && !hasInsight) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 7),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final p in pills) _Pill(label: p),
          if (hasInsight) const _Pill(label: 'Deep', highlight: true),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, this.highlight = false});
  final String label;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: highlight
            ? Colors.white.withValues(alpha: 0.92)
            : Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Brand.label(
          size: 9.5,
          color: highlight ? Colors.black87 : Colors.white,
          weight: FontWeight.w700,
        ),
      ),
    );
  }
}
