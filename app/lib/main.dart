/// App entry: dependency injection (architecture skill — Provider container) and
/// the share-target listener that turns an incoming reel into a card via the
/// visible pipeline (docs/06).
library;

import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:provider/provider.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:window_manager/window_manager.dart';

import 'data/repositories/card_repository.dart';
import 'data/services/auth_service.dart';
import 'data/services/local_ai/gemma_local_ai_service.dart';
import 'data/services/local_ai/local_ai_service.dart';
import 'data/services/api_client.dart';
import 'data/services/highlight_store.dart';
import 'data/services/local_store.dart';
import 'firebase_options.dart';
import 'ui/core/app_controller.dart';
import 'ui/core/root_gate.dart';
import 'ui/core/theme.dart';
import 'ui/core/ui_bus.dart';
import 'ui/features/share/views/share_screen.dart';

Future<void> main() async {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  await _setupDesktopWindow();
  // Firebase identity (uid = backend owner_id). Only Android is configured in
  // firebase_options.dart today; register a web/iOS app + re-run
  // `flutterfire configure` to enable those platforms.
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  final authService = FirebaseAuthService();
  final store = await LocalStore.open();
  final highlightStore = await HighlightStore.open();
  final api = ApiClient(baseUrl: await ApiClient.resolveBaseUrl(store: store), store: store);
  final repository = CardRepository(api: api, store: store);
  final appController = AppController(store);
  final localAi = GemmaLocalAiService(store: store);
  FlutterNativeSplash.remove();
  runApp(CachyApp(
    repository: repository,
    appController: appController,
    authService: authService,
    highlightStore: highlightStore,
    localAi: localAi,
  ));
}

/// Configure the native desktop window (size, minimum size, title) before the
/// app renders. Desktop-only and platform-guarded: Android/Web skip this path
/// entirely. `Platform` from dart:io is only referenced after the `kIsWeb`
/// guard so web compilation stays safe. Failures are logged and swallowed so
/// the app still launches with default OS window behavior.
Future<void> _setupDesktopWindow() async {
  if (kIsWeb) return;
  if (!(Platform.isMacOS || Platform.isWindows || Platform.isLinux)) return;
  try {
    await windowManager.ensureInitialized();
    const WindowOptions windowOptions = WindowOptions(
      size: Size(1200, 800),
      minimumSize: Size(800, 600),
      center: true,
      title: 'Cachy',
      titleBarStyle: TitleBarStyle.normal,
    );
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  } catch (e) {
    debugPrint('Desktop window setup failed: $e');
  }
}

class CachyApp extends StatefulWidget {
  const CachyApp({
    super.key,
    required this.repository,
    required this.appController,
    required this.authService,
    required this.highlightStore,
    required this.localAi,
  });
  final CardRepository repository;
  final AppController appController;
  final AuthService authService;
  final HighlightStore highlightStore;
  final LocalAiService localAi;

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
        Provider<AuthService>.value(value: widget.authService),
        ChangeNotifierProvider<HighlightStore>.value(value: widget.highlightStore),
        ChangeNotifierProvider<LocalAiService>.value(value: widget.localAi),
        ChangeNotifierProvider<UiBus>(create: (_) => UiBus()),
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
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());
  }

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };
}
