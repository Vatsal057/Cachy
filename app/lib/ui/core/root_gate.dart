/// Decides what the user sees first: the animated splash, then (on first run)
/// onboarding, then the home shell. Keeps that branching out of main.dart.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/card_repository.dart';
import '../../data/services/auth_service.dart';
import '../features/onboarding/views/login_screen.dart';
import '../features/onboarding/views/onboarding_screen.dart';
import '../features/onboarding/views/splash_screen.dart';
import 'app_controller.dart';
import 'home_shell.dart';

enum _Phase { splash, onboarding, login, shell }

class RootGate extends StatefulWidget {
  const RootGate({super.key});

  @override
  State<RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<RootGate> {
  late _Phase _phase;

  _Phase _afterSplash(AppController app) {
    if (!app.seenOnboarding) return _Phase.onboarding;
    if (app.needsLogin) return _Phase.login;
    return _Phase.shell;
  }

  @override
  void initState() {
    super.initState();
    final app = context.read<AppController>();
    _phase = kIsWeb ? _afterSplash(app) : _Phase.splash;
  }

  void _finishSplash() {
    if (!mounted) return;
    setState(() => _phase = _afterSplash(context.read<AppController>()));
  }

  Future<void> _finishOnboarding() async {
    await context.read<AppController>().completeOnboarding();
    if (!mounted) return;
    final app = context.read<AppController>();
    setState(() => _phase = app.needsLogin ? _Phase.login : _Phase.shell);
  }

  /// After the login gate: adopt the legacy name-keyed library under this
  /// Google account before the shell loads, so pre-auth cards appear on first
  /// render. Best-effort — offline or already-claimed never blocks entry.
  Future<void> _finishLogin() async {
    if (!mounted) return;
    final name = context.read<AppController>().userName;
    final user = context.read<AuthService>().currentUser;
    if (name != null && name.isNotEmpty && user != null && !user.isAnonymous) {
      try {
        await context.read<CardRepository>().api.claimLegacyLibrary(name);
      } catch (e) {
        debugPrint('legacy claim skipped: $e');
      }
    }
    if (mounted) setState(() => _phase = _Phase.shell);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 550),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
      child: switch (_phase) {
        _Phase.splash =>
          SplashScreen(key: const ValueKey('splash'), onDone: _finishSplash),
        _Phase.onboarding =>
          OnboardingScreen(key: const ValueKey('onboarding'), onDone: _finishOnboarding),
        _Phase.login =>
          LoginScreen(key: const ValueKey('login'), onDone: _finishLogin),
        _Phase.shell => const HomeShell(key: ValueKey('shell')),
      },
    );
  }
}
