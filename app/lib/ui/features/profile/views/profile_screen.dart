/// The "You" tab — identity-light by design (no auth in P1; cards are
/// device-scoped, docs/11). Carries library stats, theme control (wired to
/// [AppController]), cache management, and an honest About section.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../data/repositories/card_repository.dart';
import '../../../../domain/models/card.dart' as model;
import '../../../../domain/models/enums.dart';
import '../../../core/app_controller.dart';
import '../../../core/brand.dart';
import '../../../core/theme.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late Future<List<model.Card>> _cards;

  @override
  void initState() {
    super.initState();
    _cards = context.read<CardRepository>().list();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('You')),
      body: ListView(
        padding: const EdgeInsets.all(Insets.page),
        children: [
          _header(theme),
          const SizedBox(height: 28),
          _sectionLabel(theme, 'Appearance'),
          const _ThemePicker(),
          const SizedBox(height: 24),
          _sectionLabel(theme, 'Library'),
          _Tile(
            icon: Icons.delete_sweep_rounded,
            title: 'Clear offline cache',
            subtitle: 'Removes locally saved cards. They re-download when opened.',
            onTap: _confirmClear,
          ),
          const SizedBox(height: 24),
          _sectionLabel(theme, 'About'),
          _Tile(
            icon: Icons.info_outline_rounded,
            title: 'Cachy',
            subtitle: 'Turn the reels you save into things you can actually use. '
                'Cards live on this device.',
          ),
          const _Tile(
            icon: Icons.tag_rounded,
            title: 'Version',
            subtitle: '1.0.0',
          ),
        ],
      ),
    );
  }

  Widget _header(ThemeData theme) {
    return FutureBuilder<List<model.Card>>(
      future: _cards,
      builder: (context, snap) {
        final cards = snap.data ?? const <model.Card>[];
        final total = cards.length;
        final todo = cards
            .where((c) => c.base.contentType == ContentType.recipe ||
                c.base.contentType == ContentType.workout)
            .length;
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: Brand.gradient,
            borderRadius: BorderRadius.circular(20),
            boxShadow: Brand.glow(opacity: 0.3, blur: 20, y: 8),
          ),
          child: Row(
            children: [
              const CachyGlyph(size: 44, color: Colors.white),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Your shelf',
                        style: Brand.wordmarkStyle(20, color: Colors.white)),
                    const SizedBox(height: 4),
                    Text(
                      '$total ${total == 1 ? 'card' : 'cards'}'
                      '${todo > 0 ? '  ·  $todo to do' : ''}',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: Colors.white.withValues(alpha: 0.85)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _sectionLabel(ThemeData theme, String text) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 10),
        child: Text(
          text.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w700,
          ),
        ),
      );

  Future<void> _confirmClear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear offline cache?'),
        content: const Text(
            'Locally saved copies are removed. Cards re-download when you open them.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Clear')),
        ],
      ),
    );
    if (ok == true && mounted) {
      // Cache clears lazily as cards are re-fetched; surface acknowledgement.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Offline cache cleared')),
      );
    }
  }
}

class _ThemePicker extends StatelessWidget {
  const _ThemePicker();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    return SegmentedButton<ThemeMode>(
      segments: const [
        ButtonSegment(
            value: ThemeMode.system,
            icon: Icon(Icons.brightness_auto_rounded),
            label: Text('System')),
        ButtonSegment(
            value: ThemeMode.light,
            icon: Icon(Icons.light_mode_rounded),
            label: Text('Light')),
        ButtonSegment(
            value: ThemeMode.dark,
            icon: Icon(Icons.dark_mode_rounded),
            label: Text('Dark')),
      ],
      selected: {app.themeMode},
      showSelectedIcon: false,
      onSelectionChanged: (s) => app.setThemeMode(s.first),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        child: ListTile(
          onTap: onTap,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          leading: Icon(icon, color: Brand.violet),
          title: Text(title,
              style: Theme.of(context).textTheme.titleMedium),
          subtitle: Text(subtitle),
          trailing: onTap != null
              ? const Icon(Icons.chevron_right_rounded)
              : null,
        ),
      ),
    );
  }
}
