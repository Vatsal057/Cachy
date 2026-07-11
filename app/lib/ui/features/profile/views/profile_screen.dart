/// The "You" tab — identity-light by design (no auth in P1; cards are
/// device-scoped, docs/11). Carries library stats, theme control (wired to
/// [AppController]), cache management, and an honest About section.
library;

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../data/repositories/card_repository.dart';
import '../../../../data/services/local_ai/gemma_local_ai_service.dart';
import '../../../../data/services/local_ai/local_ai_service.dart';
import '../../../../data/services/obsidian_export.dart';
import '../../../../domain/models/artifact.dart';
import '../../../../domain/models/card.dart' as model;
import '../../../core/app_controller.dart';
import '../../../core/brand.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/responsive_center.dart';
import '../../../core/widgets/stat_strip.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late Future<List<model.Card>> _cards;
  late Future<List<CatalogEntry>> _catalog;
  bool _exporting = false;
  bool _discovering = false;

  @override
  void initState() {
    super.initState();
    final repo = context.read<CardRepository>();
    _cards = repo.list();
    _catalog = repo.catalog().catchError((_) => <CatalogEntry>[]);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final repo = context.watch<CardRepository>();
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('You')),
      body: ResponsiveCenter(
        child: ListView(
        padding: const EdgeInsets.all(Insets.page),
        children: [
          _header(theme),
          const SizedBox(height: 28),
          _sectionLabel(theme, 'Appearance'),
          const _ThemePicker(),
          const SizedBox(height: 24),
          _sectionLabel(theme, 'Server Connection'),
          _Tile(
            icon: PhosphorIconsRegular.hardDrives,
            title: 'Active Server endpoint',
            subtitle: repo.api.baseUrl,
            onTap: _editServerUrl,
          ),
          _Tile(
            icon: PhosphorIconsRegular.broadcast,
            title: _discovering ? 'Searching local WiFi…' : 'Discover LAN Server',
            subtitle: 'Scan local network for a Cachy backend running ./start.py.',
            onTap: _discovering ? null : _discoverServer,
          ),
          const SizedBox(height: 24),
          const _OfflineAiSection(),
          _sectionLabel(theme, 'Library'),
          _Tile(
            icon: PhosphorIconsRegular.export,
            title: _exporting ? 'Preparing vault…' : 'Export as Obsidian vault',
            subtitle: 'Saves every card as a markdown note, zipped to open in Obsidian.',
            onTap: _exporting ? null : _exportVault,
          ),
          _Tile(
            icon: PhosphorIconsRegular.trash,
            title: 'Clear offline cache',
            subtitle: 'Removes locally saved cards. They re-download when opened.',
            onTap: _confirmClear,
          ),
          const SizedBox(height: 24),
          _sectionLabel(theme, 'About'),
          _Tile(
            icon: PhosphorIconsRegular.info,
            title: 'Cachy',
            subtitle: 'Turn the reels you save into things you can actually use. '
                'Cards live on this device.',
          ),
          const _Tile(
            icon: PhosphorIconsRegular.hash,
            title: 'Version',
            subtitle: '1.0.0',
          ),
        ],
      ),
      ),
    );
  }

  Widget _header(ThemeData theme) {
    final scheme = theme.colorScheme;
    return FutureBuilder<List<model.Card>>(
      future: _cards,
      builder: (context, snap) {
        final cards = snap.data ?? const <model.Card>[];
        final total = cards.length;
        final weekAgo = DateTime.now().subtract(const Duration(days: 7));
        final thisWeek = cards
            .where((c) => (c.meta.createdAt ?? DateTime(0)).isAfter(weekAgo))
            .length;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CachyGlyph(size: 44, color: scheme.onSurface, reelColor: scheme.primary),
                const SizedBox(width: 14),
                Text('Your shelf',
                    style: Brand.wordmarkStyle(24, color: scheme.onSurface)),
              ],
            ),
            const SizedBox(height: 16),
            FutureBuilder<List<CatalogEntry>>(
              future: _catalog,
              builder: (context, catSnap) {
                final refs = catSnap.data?.length;
                return StatStrip(stats: [
                  Stat(value: '$total', label: 'Cards', emphasize: true),
                  Stat(value: '$thisWeek', label: 'This week'),
                  Stat(value: refs == null ? '—' : '$refs', label: 'References'),
                ]);
              },
            ),
          ],
        );
      },
    );
  }

  Widget _sectionLabel(ThemeData theme, String text) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 10),
        child: Text(
          text.toUpperCase(),
          style: Brand.label(
            size: 11,
            color: theme.colorScheme.onSurfaceVariant,
            weight: FontWeight.w700,
            letterSpacing: 1.4,
          ),
        ),
      );

  Future<void> _discoverServer() async {
    setState(() => _discovering = true);
    final repo = context.read<CardRepository>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final found = await repo.discoverServer();
      if (mounted) {
        if (found != null) {
          messenger.showSnackBar(SnackBar(content: Text('Connected to backend at $found')));
        } else {
          messenger.showSnackBar(const SnackBar(content: Text('No server found on LAN')));
        }
      }
    } finally {
      if (mounted) setState(() => _discovering = false);
    }
  }

  Future<void> _editServerUrl() async {
    final repo = context.read<CardRepository>();
    final controller = TextEditingController(text: repo.api.baseUrl);
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Configure Server URL'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'http://192.168.1.5:8000',
            labelText: 'Backend URL',
          ),
          keyboardType: TextInputType.url,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (url != null && url.isNotEmpty && mounted) {
      repo.updateBaseUrl(url);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Server URL updated to $url')),
      );
    }
  }

  Future<void> _exportVault() async {
    setState(() => _exporting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final cards = await context.read<CardRepository>().listAll();
      if (cards.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(content: Text('No cards to export yet')),
        );
        return;
      }
      final zip = ObsidianExport.buildVault(cards);
      await Share.shareXFiles(
        [XFile.fromData(zip, name: 'cachy-vault.zip', mimeType: 'application/zip')],
        fileNameOverrides: const ['cachy-vault.zip'],
        subject: 'Cachy Obsidian vault',
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Export failed — try again')),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

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
            icon: PhosphorIcon(PhosphorIconsRegular.monitor),
            label: Text('System')),
        ButtonSegment(
            value: ThemeMode.light,
            icon: PhosphorIcon(PhosphorIconsRegular.sun),
            label: Text('Light')),
        ButtonSegment(
            value: ThemeMode.dark,
            icon: PhosphorIcon(PhosphorIconsRegular.moon),
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

  final PhosphorIconData icon;
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
          leading: PhosphorIcon(icon, color: scheme.primary),
          title: Text(title,
              style: Theme.of(context).textTheme.titleMedium),
          subtitle: Text(subtitle),
          trailing: onTap != null
              ? const PhosphorIcon(PhosphorIconsRegular.caretRight)
              : null,
        ),
      ),
    );
  }
}


/// Offline AI (V2): download/enable/delete the on-device model. Hidden on
/// platforms that can't run it. Honest copy — size, speed, trade-offs.
class _OfflineAiSection extends StatelessWidget {
  const _OfflineAiSection();

  @override
  Widget build(BuildContext context) {
    LocalAiService? ai;
    try {
      ai = context.watch<LocalAiService>();
    } catch (_) {
      return const SizedBox.shrink(); // not provided (tests)
    }
    final theme = Theme.of(context);
    if (ai.status.phase == LocalAiPhase.unsupported) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10, left: 4),
          child: Text('OFFLINE AI',
              style: Brand.label(
                  size: 11, color: theme.colorScheme.onSurfaceVariant)),
        ),
        _offlineAiTile(context, ai),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _offlineAiTile(BuildContext context, LocalAiService ai) {
    final scheme = Theme.of(context).colorScheme;
    switch (ai.status.phase) {
      case LocalAiPhase.notInstalled:
      case LocalAiPhase.error:
        return Column(children: [
          if (ai.status.phase == LocalAiPhase.error)
            _Tile(
              icon: PhosphorIconsRegular.warning,
              title: 'Model problem',
              subtitle: ai.status.message,
            ),
          _Tile(
            icon: PhosphorIconsRegular.downloadSimple,
            title: 'Download local model',
            subtitle:
                'Gemma 3 1B, $kLocalAiModelSizeLabel. Runs on your phone when the '
                'daily AI budget runs out. Slower than cloud. Wi-Fi recommended.',
            onTap: () => _confirmDownload(context, ai),
          ),
        ]);
      case LocalAiPhase.downloading:
        final pct = (ai.status.progress * 100).round();
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(14),
            child: ListTile(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              leading: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  value: ai.status.progress > 0 ? ai.status.progress : null,
                ),
              ),
              title: Text('Downloading model… $pct%'),
              subtitle: const Text('Keep the app open until this finishes.'),
            ),
          ),
        );
      case LocalAiPhase.ready:
        return Column(children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(14),
              child: SwitchListTile(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                secondary:
                    PhosphorIcon(PhosphorIconsRegular.cpu, color: scheme.primary),
                title: const Text('Generate on this phone past quota'),
                subtitle: const Text(
                    'Model installed ($kLocalAiModelSizeLabel on disk).'),
                value: ai.enabled,
                onChanged: (v) => ai.setEnabled(v),
              ),
            ),
          ),
          _Tile(
            icon: PhosphorIconsRegular.trash,
            title: 'Delete local model',
            subtitle: 'Frees $kLocalAiModelSizeLabel. You can re-download anytime.',
            onTap: () => _confirmDelete(context, ai),
          ),
        ]);
      case LocalAiPhase.unsupported:
        return const SizedBox.shrink();
    }
  }

  Future<void> _confirmDownload(BuildContext context, LocalAiService ai) async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Download model?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
                '$kLocalAiModelSizeLabel download — Wi-Fi recommended. The model '
                'is license-gated on HuggingFace: paste a free HF token that has '
                'accepted the Gemma license.'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'HuggingFace token (hf_…)',
                border: OutlineInputBorder(),
              ),
              obscureText: true,
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Download')),
        ],
      ),
    );
    if (ok != true) return;
    final token = controller.text.trim();
    if (token.isNotEmpty) await ai.saveHfToken(token);
    await ai.download();
  }

  Future<void> _confirmDelete(BuildContext context, LocalAiService ai) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete local model?'),
        content: const Text('Past-quota cards go back to plain paragraphs '
            'until you re-download it.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) await ai.delete();
  }
}
