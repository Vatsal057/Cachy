/// A modal that's a bottom sheet on mobile/narrow widths and a centered
/// dialog on desktop widths — so the same content reads as a native sheet on
/// a phone and a website-style modal on a wide window, not a bottom sheet
/// glued to a PC monitor.
library;

import 'package:flutter/material.dart';

import '../theme.dart';

/// [builder] receives `dialog: true` when rendered as a desktop dialog, so
/// the content can drop its drag-handle pill and round all four corners
/// instead of just the top.
Future<T?> showAdaptiveModal<T>({
  required BuildContext context,
  required Widget Function(BuildContext context, bool dialog) builder,
  double dialogMaxWidth = 480,
}) {
  final isDesktop = MediaQuery.sizeOf(context).width >= Insets.desktop;
  if (!isDesktop) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => builder(ctx, false),
    );
  }
  return showDialog<T>(
    context: context,
    builder: (ctx) => Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: dialogMaxWidth),
        child: Material(
          color: Colors.transparent,
          child: builder(ctx, true),
        ),
      ),
    ),
  );
}
