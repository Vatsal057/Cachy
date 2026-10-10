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
import 'package:app_links/app_links.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:provider/provider.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:window_manager/window_manager.dart';

import 'data/repositories/card_repository.dart';
import 'data/services/auth_service.dart';
import 'data/services/id_auth_service.dart';
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
import 'ui/features/share/views/shared_card_sheet.dart';

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
  // The Cachy ID JWT (username + password session) wins while present;
  // otherwise the Firebase ID token is used. `late` because baseUrlOf is only
  // called on requests, after api is assigned below.
  late final ApiClient api;
  final idAuth = IdAuthService(baseUrlOf: () => api.baseUrl, store: store);
  api = ApiClient(
    baseUrl: await ApiClient.resolveBaseUrl(store: store),
    store: store,
    // Every request carries a bearer token (uid = backend owner_id);
    // without this the backend 401s all data routes.
    tokenProvider: ({bool forceRefresh = false}) async =>
        idAuth.validToken ?? authService.idToken(forceRefresh: forceRefresh),
  );
  final repository = CardRepository(api: api, store: store);
  final appController = AppController(store, authService, idAuth);
  final localAi = GemmaLocalAiService(store: store);
  runApp(CachyApp(
    repository: repository,
    appController: appController,
    authService: authService,
    idAuthService: idAuth,
    highlightStore: highlightStore,
    localAi: localAi,
  ));
  WidgetsBinding.instance.addPostFrameCallback((_) {
    FlutterNativeSplash.remove();
  });
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
    required this.idAuthService,
    required this.highlightStore,
    required this.localAi,
  });
  final CardRepository repository;
  final AppController appController;
  final AuthService authService;
  final IdAuthService idAuthService;
  final HighlightStore highlightStore;
  final LocalAiService localAi;

  @override
  State<CachyApp> createState() => _CachyAppState();
}

class _CachyAppState extends State<CachyApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  StreamSubscription<List<SharedMediaFile>>? _intentSub;
  StreamSubscription<Uri>? _linkSub;
  final List<String> _pendingShareTokens = [];
  bool _saveSheetOpen = false;

  @override
  void initState() {
    super.initState();
    _wireShareIntent();
    _wireDeepLinks();
    widget.appController.addListener(_drainPendingShareTokens);
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _drainPendingShareTokens());
  }

  /// Cachy share links: `https://<host>/s/<token>` and `cachy://s/<token>`
  /// (fired by the share page's "Save to my Cachy" button).
  void _wireDeepLinks() {
    late final AppLinks appLinks;
    try {
      appLinks = AppLinks();
    } catch (_) {
      return; // plugin unavailable on this platform
    }
    appLinks.getInitialLink().then((uri) {
      if (uri != null) _onDeepLink(uri);
    }).catchError((_) {});
    _linkSub = appLinks.uriLinkStream.listen(_onDeepLink, onError: (_) {});
  }

  String? _shareTokenFromUri(Uri uri) {
    if (uri.scheme == 'cachy' &&
        uri.host == 's' &&
        uri.pathSegments.isNotEmpty) {
      return uri.pathSegments.first;
    }
    if ((uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.pathSegments.length >= 2 &&
        uri.pathSegments[0] == 's') {
      return uri.pathSegments[1];
    }
    return null;
  }

  void _onDeepLink(Uri uri) {
    final token = _shareTokenFromUri(uri);
    if (token == null || _pendingShareTokens.contains(token)) return;
    _pendingShareTokens.add(token);
    _drainPendingShareTokens();
  }

  /// Show the save sheet once the navigator exists and the user is signed in.
  /// Tokens that arrive before login wait — AppController notifies on auth
  /// changes, which re-triggers the drain.
  void _drainPendingShareTokens() {
    if (_saveSheetOpen || _pendingShareTokens.isEmpty) return;
    // The navigator's own context can't locate the Navigator (only ancestors
    // are searched) — the overlay's context sits below it, so sheet lookups
    // resolve correctly.
    final overlayCtx = _navigatorKey.currentState?.overlay?.context;
    if (overlayCtx == null) return;
    final app = Provider.of<AppController>(overlayCtx, listen: false);
    final idAuth = Provider.of<IdAuthService>(overlayCtx, listen: false);
    if (app.authUser == null && !idAuth.isSignedIn) return;
    final token = _pendingShareTokens.removeAt(0);
    _saveSheetOpen = true;
    showSharedCardSheet(overlayCtx, token).whenComplete(() {
      _saveSheetOpen = false;
      _drainPendingShareTokens();
    });
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
    _linkSub?.cancel();
    widget.appController.removeListener(_drainPendingShareTokens);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<CardRepository>.value(value: widget.repository),
        ChangeNotifierProvider<AppController>.value(value: widget.appController),
        Provider<AuthService>.value(value: widget.authService),
        ChangeNotifierProvider<IdAuthService>.value(value: widget.idAuthService),
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
