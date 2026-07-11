/// The "You" tab — identity-light by design (no auth in P1; cards are
/// device-scoped, docs/11). Carries library stats, theme control (wired to
/// [AppController]), cache management, and an honest About section.
library;

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../data/repositories/card_repository.dart';
import '../../../../data/services/api_client.dart';
import '../../../../data/services/auth_service.dart';
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

// ponytail: client-side gate only (extractable from the APK) — it hides the
// developer server controls from casual users, it is not real security.
const _kDeveloperPassword = 'vatxzz';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late Future<List<model.Card>> _cards;
  late Future<List<CatalogEntry>> _catalog;
  late Future<QuotaStatus> _quota;
  bool _exporting = false;
  bool _signingIn = false;

  // Hidden developer gate: tapping the version row seven times prompts for a
  // password before revealing the server-connection controls.
  int _versionTaps = 0;

  @override
  void initState() {
    super.initState();
    final repo = context.read<CardRepository>();
    _cards = repo.list();
    _catalog = repo.catalog().catchError((_) => <CatalogEntry>[]);
    _quota = repo.api.quota();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
          _quotaMeter(theme),
          const SizedBox(height: 24),
          _sectionLabel(theme, 'About'),
          _Tile(
            icon: PhosphorIconsRegular.info,
            title: 'Cachy',
            subtitle: 'Turn the reels you save into things you can actually use. '
                'Cards live on this device.',
          ),
          _Tile(
            icon: PhosphorIconsRegular.hash,
            title: 'Version',
            subtitle: '1.0.0',
            showChevron: false, // hidden developer gate — looks inert
            onTap: _onVersionTap,
          ),
          const SizedBox(height: 24),
          _sectionLabel(theme, 'Account'),
          _accountSection(theme),
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

  /// Count taps on the version row; the seventh opens the password prompt.
  void _onVersionTap() {
    _versionTaps++;
    if (_versionTaps >= 7) {
      _versionTaps = 0;
      _promptDeveloperAccess();
    }
  }

  Future<void> _promptDeveloperAccess() async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Developer access'),
        content: TextField(
          controller: controller,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Password'),
          onSubmitted: (_) =>
              Navigator.pop(ctx, controller.text == _kDeveloperPassword),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx), // null = cancelled
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(ctx, controller.text == _kDeveloperPassword),
            child: const Text('Unlock'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (ok == true) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const _DeveloperScreen()),
      );
    } else if (ok == false) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Incorrect password')));
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
      final removed = await context.read<CardRepository>().clearCardCache();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(removed == 0
                ? 'Nothing cached yet'
                : 'Cleared $removed offline ${removed == 1 ? 'card' : 'cards'}'),
          ),
        );
      }
    }
  }

  Future<void> _confirmSignOut() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
            'Your name will be cleared and you\'ll be taken back to the setup screen. '
            'Your cards on the server are not affected.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      await context.read<AppController>().logout();
    }
  }

  /// Quota meter — a nicety, never a blocker: hidden while loading or on any
  /// error (unauthenticated, offline, backend down).
  Widget _quotaMeter(ThemeData theme) {
    return FutureBuilder<QuotaStatus>(
      future: _quota,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done ||
            snap.hasError ||
            !snap.hasData) {
          return const SizedBox.shrink();
        }
        final q = snap.data!;
        return _Tile(
          icon: PhosphorIconsRegular.gauge,
          title: 'AI usage today',
          subtitle:
              '${q.cardsUsed}/${q.cardsLimit} cards · ${q.chatUsed}/${q.chatLimit} chats',
          showChevron: false,
        );
      },
    );
  }

  /// Signed-in-with-Google shows the account row; everyone else (anonymous or
  /// not-yet-signed-in) gets the backup nudge. Sign out sits below either way.
  Widget _accountSection(ThemeData theme) {
    final user = context.watch<AppController>().authUser;
    final signedIn = user != null && !user.isAnonymous;
    return Column(
      children: [
        if (signedIn)
          _accountRow(theme, user)
        else
          _backupBanner(theme),
        if (signedIn &&
            (context.read<AppController>().userName ?? '').isNotEmpty)
          _Tile(
            icon: PhosphorIconsRegular.clockCounterClockwise,
            title: 'Restore old library',
            subtitle: 'Bring in cards saved under your name before sign-in.',
            onTap: () =>
                _offerClaim(context.read<AppController>().userName!),
          ),
        _Tile(
          icon: PhosphorIconsRegular.signOut,
          title: 'Sign out',
          subtitle: signedIn
              ? 'Your cards stay safe in your account.'
              : 'Clear your name and reset the app to the setup screen.',
          onTap: _confirmSignOut,
          destructive: true,
        ),
      ],
    );
  }

  Widget _accountRow(ThemeData theme, AuthUser user) {
    final scheme = theme.colorScheme;
    final source = (user.displayName?.trim().isNotEmpty ?? false)
        ? user.displayName!.trim()
        : (user.email?.trim() ?? '');
    final initial = source.isNotEmpty ? source[0].toUpperCase() : '?';
    final hasPhoto = user.photoUrl != null && user.photoUrl!.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        child: ListTile(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          leading: CircleAvatar(
            backgroundColor: scheme.primaryContainer,
            foregroundColor: scheme.onPrimaryContainer,
            backgroundImage: hasPhoto ? NetworkImage(user.photoUrl!) : null,
            child: hasPhoto ? null : Text(initial),
          ),
          title: Text(user.displayName ?? 'Signed in',
              style: theme.textTheme.titleMedium),
          subtitle: user.email != null ? Text(user.email!) : null,
        ),
      ),
    );
  }

  Widget _backupBanner(ThemeData theme) {
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: scheme.primaryContainer.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: scheme.primary.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                PhosphorIcon(PhosphorIconsRegular.warningCircle,
                    color: scheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text("Your library isn't backed up",
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Sign in with Google — if you uninstall or clear data, your cards are gone.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _signingIn ? null : _signInAndMaybeClaim,
                icon: _signingIn
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const PhosphorIcon(PhosphorIconsRegular.googleLogo,
                        size: 18),
                label: const Text('Sign in'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Google sign-in from the backup banner; on success, offer to adopt the
  /// legacy name-keyed library if the user still has a local name.
  Future<void> _signInAndMaybeClaim() async {
    setState(() => _signingIn = true);
    final app = context.read<AppController>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await app.signInWithGoogle();
    } catch (_) {
      messenger.showSnackBar(
          const SnackBar(content: Text("Couldn't sign in. Try again.")));
      return;
    } finally {
      if (mounted) setState(() => _signingIn = false);
    }
    if (!mounted) return;
    final name = app.userName;
    if (name != null && name.isNotEmpty) await _offerClaim(name);
  }

  Future<void> _offerClaim(String name) async {
    final restore = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore your old library?'),
        content: Text('Bring the cards you saved as "$name" into this account.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Not now')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Restore')),
        ],
      ),
    );
    if (restore != true || !mounted) return;
    final api = context.read<CardRepository>().api;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final n = await api.claimLegacyLibrary(name);
      messenger.showSnackBar(SnackBar(
          content: Text(n == 0 ? 'Nothing to restore' : 'Restored $n cards')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text(e.statusCode == 409
              ? 'That name was already claimed.'
              : 'Restore failed — try again')));
    } catch (_) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Restore failed — try again')));
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
    this.destructive = false,
    this.showChevron = true,
  });

  final PhosphorIconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool destructive;

  /// Show the trailing chevron for tappable tiles. Off for the hidden
  /// developer gate so the row reads as inert.
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = destructive ? scheme.error : scheme.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        child: ListTile(
          onTap: onTap,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          leading: PhosphorIcon(icon, color: color),
          title: Text(title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: destructive ? scheme.error : null,
                  )),
          subtitle: Text(subtitle),
          trailing: (onTap != null && showChevron)
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
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Download model?'),
        content: const Text(
            '$kLocalAiModelSizeLabel download — Wi-Fi recommended. Runs entirely '
            'on your phone once installed; no account or sign-in needed. Keep the '
            'app open until it finishes.'),
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

// ── Developer settings (hidden behind the version-tap gate) ───────────────── //

/// Manual server-connection controls. Reachable only after unlocking the
/// developer gate on the profile screen. End users never see this — the app
/// connects to the hosted backend by default.
class _DeveloperScreen extends StatefulWidget {
  const _DeveloperScreen();

  @override
  State<_DeveloperScreen> createState() => _DeveloperScreenState();
}

class _DeveloperScreenState extends State<_DeveloperScreen> {
  bool _discovering = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final repo = context.watch<CardRepository>();
    return Scaffold(
      appBar: AppBar(title: const Text('Developer')),
      body: ListView(
        padding: const EdgeInsets.all(Insets.page),
        children: [
          _Tile(
            icon: PhosphorIconsRegular.hardDrives,
            title: 'Active server endpoint',
            subtitle: repo.api.baseUrl.isEmpty
                ? '(same origin)'
                : repo.api.baseUrl,
            onTap: _editServerUrl,
          ),
          _Tile(
            icon: PhosphorIconsRegular.broadcast,
            title: _discovering ? 'Searching local WiFi…' : 'Discover LAN server',
            subtitle: 'Scan the local network for a Cachy backend running ./start.py.',
            onTap: _discovering ? null : _discoverServer,
          ),
          _Tile(
            icon: PhosphorIconsRegular.arrowCounterClockwise,
            title: 'Reset to default backend',
            subtitle: 'Clear the override and reconnect to the hosted Space.',
            onTap: () => _setUrl(repo, ApiClient.defaultBaseUrl),
          ),
          const SizedBox(height: 12),
          Text(
            'Changes take effect immediately and persist across launches.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  void _setUrl(CardRepository repo, String url) {
    repo.updateBaseUrl(url);
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Backend set to ${url.isEmpty ? '(same origin)' : url}')),
    );
  }

  Future<void> _discoverServer() async {
    setState(() => _discovering = true);
    final repo = context.read<CardRepository>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final found = await repo.discoverServer();
      if (mounted) {
        setState(() {});
        messenger.showSnackBar(SnackBar(
          content: Text(found != null
              ? 'Connected to backend at $found'
              : 'No server found on LAN'),
        ));
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
        title: const Text('Configure server URL'),
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
      _setUrl(repo, url);
    }
  }
}
