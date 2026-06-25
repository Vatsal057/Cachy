/// App entry: dependency injection (architecture skill — Provider container) and
/// the share-target listener that turns an incoming reel into a card via the
/// visible pipeline (docs/06).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'data/repositories/card_repository.dart';
import 'data/services/api_client.dart';
import 'data/services/local_store.dart';
import 'ui/core/theme.dart';
import 'ui/features/library/views/library_screen.dart';
import 'ui/features/share/views/share_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await LocalStore.open();
  final api = ApiClient();
  final repository = CardRepository(api: api, store: store);
  runApp(CachyApp(repository: repository));
}

class CachyApp extends StatefulWidget {
  const CachyApp({super.key, required this.repository});
  final CardRepository repository;

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
    return Provider<CardRepository>.value(
      value: widget.repository,
      child: MaterialApp(
        title: 'Cachy',
        debugShowCheckedModeBanner: false,
        navigatorKey: _navigatorKey,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.system,
        home: const LibraryScreen(),
      ),
    );
  }
}
