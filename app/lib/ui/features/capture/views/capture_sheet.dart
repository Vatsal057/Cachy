/// The Capture entry sheet — the in-app twin of the OS share target (docs/06).
/// Tapping the center Capture button opens this. It auto-detects a reel URL on
/// the clipboard for one-tap capture, or takes a pasted link, then hands off to
/// the visible pipeline ([ShareScreen]). The OS-share path (main.dart) reaches
/// the same pipeline directly.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/brand.dart';
import '../../../core/theme.dart';
import '../../share/views/share_screen.dart';

/// Opens the capture sheet as a modal bottom sheet.
Future<void> showCaptureSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _CaptureSheet(),
  );
}

class _CaptureSheet extends StatefulWidget {
  const _CaptureSheet();

  @override
  State<_CaptureSheet> createState() => _CaptureSheetState();
}

class _CaptureSheetState extends State<_CaptureSheet> {
  final _controller = TextEditingController();
  String? _clipboardUrl;

  static final _urlPattern = RegExp(r'https?://[^\s]+');

  @override
  void initState() {
    super.initState();
    _sniffClipboard();
  }

  Future<void> _sniffClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final match = _urlPattern.firstMatch(data?.text ?? '');
      if (match != null && mounted) {
        setState(() => _clipboardUrl = match.group(0));
      }
    } catch (_) {
      // No clipboard access — paste still works.
    }
  }

  void _capture(String url) {
    final cleaned = url.trim();
    if (cleaned.isEmpty) return;
    Navigator.of(context).pop(); // close the sheet
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ShareScreen(sharedUrl: cleaned)),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(top: BorderSide(color: scheme.outlineVariant)),
          boxShadow: Brand.softShadow(opacity: 0.16, blur: 28, y: -4),
        ),
        padding: const EdgeInsets.fromLTRB(Insets.page, 12, Insets.page, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.outlineVariant,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text('Capture a reel', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 6),
            Text(
              'Paste a link, or share to Cachy from Instagram, TikTok or YouTube.',
              style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),

            // Supported-platform affordance — sets expectations at a glance.
            const Row(
              children: [
                _PlatformChip(label: 'Instagram', dot: Color(0xFFE1306C)),
                SizedBox(width: 8),
                _PlatformChip(label: 'TikTok', dot: Color(0xFF22C3D6)),
                SizedBox(width: 8),
                _PlatformChip(label: 'YouTube', dot: Color(0xFFE0301E)),
              ],
            ),
            const SizedBox(height: 20),

            // One-tap capture of a URL already on the clipboard.
            if (_clipboardUrl != null) ...[
              _ClipboardChip(url: _clipboardUrl!, onTap: () => _capture(_clipboardUrl!)),
              const SizedBox(height: 14),
            ],

            TextField(
              controller: _controller,
              autofocus: _clipboardUrl == null,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.go,
              onSubmitted: _capture,
              decoration: InputDecoration(
                hintText: 'Paste a reel link…',
                prefixIcon: const Icon(Icons.link_rounded),
                filled: true,
                fillColor: scheme.surfaceContainerHigh,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _capture(_controller.text),
              icon: const Icon(Icons.auto_awesome_rounded, size: 20),
              label: const Text('Capture'),
            ),
          ],
        ),
      ),
    );
  }
}

/// A small static chip naming a supported source platform (colored dot + label).
class _PlatformChip extends StatelessWidget {
  const _PlatformChip({required this.label, required this.dot});
  final String label;
  final Color dot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Text(label,
              style: theme.textTheme.labelMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _ClipboardChip extends StatelessWidget {
  const _ClipboardChip({required this.url, required this.onTap});
  final String url;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.primary.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: scheme.primary.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              Icon(Icons.content_paste_rounded, size: 20, color: scheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('CAPTURE FROM CLIPBOARD',
                        style: Brand.label(size: 10, color: scheme.primary, weight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(url,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_rounded, size: 18, color: scheme.primary),
            ],
          ),
        ),
      ),
    );
  }
}
