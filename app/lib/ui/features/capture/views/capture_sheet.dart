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
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
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
            _GradientButton(
              label: 'Capture',
              icon: Icons.auto_awesome_rounded,
              onTap: () => _capture(_controller.text),
            ),
          ],
        ),
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
      color: Brand.violet.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              const Icon(Icons.content_paste_rounded, size: 20, color: Brand.violet),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Capture from clipboard',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: Brand.violet, fontWeight: FontWeight.w700)),
                    Text(url,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_rounded, size: 18, color: Brand.violet),
            ],
          ),
        ),
      ),
    );
  }
}

/// Brand-gradient CTA used across capture/reader. Local to keep brand.dart
/// widget-light; promote later if a third caller appears.
class _GradientButton extends StatelessWidget {
  const _GradientButton({required this.label, required this.icon, required this.onTap});
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 54,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: Brand.gradient,
          borderRadius: BorderRadius.circular(16),
          boxShadow: Brand.glow(opacity: 0.35, blur: 18, y: 6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Text(label,
                style: Brand.wordmarkStyle(16, color: Colors.white)
                    .copyWith(letterSpacing: 0.2, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}
