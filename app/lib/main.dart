/// App entry: dependency injection (architecture skill — Provider container) and
/// the share-target listener that turns an incoming reel into a card via the
/// visible pipeline (docs/06).
library;

import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:provider/provider.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'data/repositories/card_repository.dart';
import 'data/services/api_client.dart';
import 'data/services/local_store.dart';
import 'ui/core/app_controller.dart';
import 'ui/core/root_gate.dart';
import 'ui/core/theme.dart';
import 'ui/features/share/views/share_screen.dart';

Future<void> main() async {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  final store = await LocalStore.open();
  final api = ApiClient();
  final repository = CardRepository(api: api, store: store);
  final appController = AppController(store);
  FlutterNativeSplash.remove();
  runApp(CachyApp(repository: repository, appController: appController));
}

class CachyApp extends StatefulWidget {
  const CachyApp({
    super.key,
    required this.repository,
    required this.appController,
  });
  final CardRepository repository;
  final AppController appController;

  @override
  State<CachyApp> createState() => _CachyAppState();
}

class _CachyAppState extends State<CachyApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  StreamSubscription<List<SharedMediaFile>>? _intentSub;

  @override
  void initState() {
    super.initState();
    _wireShareIntent();
  }

  /// Register as a share target: handle both a cold-start share and shares that
  /// arrive while the app is already running. Degrades silently if the platform
  /// channel is unavailable (e.g. desktop/test).
  void _wireShareIntent() {
    if (kIsWeb) return;
    try {
      final instance = ReceiveSharingIntent.instance;
      instance.getInitialMedia().then((files) {
        _handleShared(files);
        instance.reset();
      }).catchError((_) {});
      _intentSub = instance.getMediaStream().listen(
        _handleShared,
        onError: (_) {},
      );
    } catch (_) {
      // No share channel on this platform — link paste still works.
    }
  }

  void _handleShared(List<SharedMediaFile> files) {
    if (files.isEmpty) return;
    for (final f in files) {
      final url = _extractUrl(f.path);
      if (url != null) {
        _navigatorKey.currentState?.push(
          MaterialPageRoute(builder: (_) => ShareScreen(sharedUrl: url)),
        );
        return; // one card per share invocation
      }
    }
  }

  static final _urlPattern = RegExp(r'https?://[^\s]+');

  String? _extractUrl(String raw) {
    final match = _urlPattern.firstMatch(raw);
    if (match != null) return match.group(0);
    final trimmed = raw.trim();
    return trimmed.startsWith('http') ? trimmed : null;
  }

  @override
  void dispose() {
    _intentSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<CardRepository>.value(value: widget.repository),
        ChangeNotifierProvider<AppController>.value(value: widget.appController),
      ],
      child: Consumer<AppController>(
        builder: (context, app, _) => MaterialApp(
          title: 'Cachy',
          debugShowCheckedModeBanner: false,
          navigatorKey: _navigatorKey,
          scrollBehavior: const DesktopScrollBehavior(),
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: app.themeMode,
          // RootGate shows the splash, routes first-run users into onboarding,
          // then settles on the home shell.
          home: const RootGate(),
        ),
      ),
    );
  }
}

/// Enables mouse drag, trackpad touch, and scroll wheel navigation on PC/desktop.
class DesktopScrollBehavior extends MaterialScrollBehavior {
  const DesktopScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };
}
