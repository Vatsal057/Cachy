/// Bottom sheet shown when the app opens a Cachy share link (`/s/<token>` or
/// `cachy://s/<token>`): previews the shared card and offers "Save to my
/// library", which clones it into the caller's account.
library;

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';

import '../../../../data/repositories/card_repository.dart';
import '../../../../data/services/api_client.dart';
import '../../../reader/views/reader_screen.dart';

Future<void> showSharedCardSheet(BuildContext context, String token) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _SharedCardSheet(token: token),
  );
}

class _SharedCardSheet extends StatefulWidget {
  const _SharedCardSheet({required this.token});
  final String token;

  @override
  State<_SharedCardSheet> createState() => _SharedCardSheetState();
}

class _SharedCardSheetState extends State<_SharedCardSheet> {
  late final Future<Map<String, dynamic>> _future;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _future = context.read<CardRepository>().api.getSharedCard(widget.token);
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final cardId = await context
          .read<CardRepository>()
          .api
          .saveSharedCard(widget.token);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved to your library')),
      );
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ReaderScreen(cardId: cardId)),
      );
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.friendlyMessage);
    } catch (_) {
      if (mounted) setState(() => _error = "Couldn't save this card. Try again.");
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SafeArea(
      child: Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: FutureBuilder<Map<String, dynamic>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const SizedBox(
                height: 280,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snap.hasError || !snap.hasData) {
              final msg = snap.error is ApiException
                  ? (snap.error as ApiException).friendlyMessage
                  : "Couldn't load this card.";
              return _shell(theme, scheme,
                  child: _message(theme, scheme, msg,
                      'The link may have been revoked or the card deleted.'));
            }
            final data = snap.data!;
            return _shell(theme, scheme, child: _preview(theme, scheme, data));
          },
        ),
      ),
    );
  }

  Widget _shell(ThemeData theme, ColorScheme scheme, {required Widget child}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
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
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Flexible(child: SingleChildScrollView(child: child)),
        ],
      ),
    );
  }

  Widget _message(ThemeData theme, ColorScheme scheme, String title, String sub) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        PhosphorIcon(PhosphorIconsRegular.linkBreak,
            size: 40, color: scheme.onSurfaceVariant),
        const SizedBox(height: 12),
        Text(title,
            textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
        const SizedBox(height: 6),
        Text(sub,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: scheme.onSurfaceVariant)),
        const SizedBox(height: 16),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _preview(
      ThemeData theme, ColorScheme scheme, Map<String, dynamic> data) {
    final title = (data['one_liner'] as String?) ?? 'Shared card';
    final tldr = (data['tldr'] as String?) ?? '';
    final thumb = data['thumbnail_url'] as String?;
    final ctype =
        ((data['content_type'] as String?) ?? 'card').replaceAll('_', ' ');
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const PhosphorIcon(PhosphorIconsRegular.shareNetwork, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Someone shared a card with you',
                  style: theme.textTheme.titleSmall?.copyWith(
                      color: scheme.onSurfaceVariant)),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (thumb != null && thumb.isNotEmpty)
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(thumb,
                height: 160, width: double.infinity, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink()),
          ),
        if (thumb != null && thumb.isNotEmpty) const SizedBox(height: 12),
        Text(title, style: theme.textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(ctype.toUpperCase(),
            style: theme.textTheme.labelSmall
                ?.copyWith(color: scheme.onSurfaceVariant)),
        if (tldr.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(tldr,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant)),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: TextStyle(color: scheme.error)),
        ],
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const PhosphorIcon(PhosphorIconsRegular.bookmarkSimple, size: 20),
          label: const Text('Save to my library'),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'A copy lands in your library — the original stays theirs.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
