/// Decides what the user sees first: the animated splash, then (on first run)
/// onboarding, then the home shell. Keeps that branching out of main.dart.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../features/onboarding/views/login_screen.dart';
import '../features/onboarding/views/name_screen.dart';
import '../features/onboarding/views/onboarding_screen.dart';
import '../features/onboarding/views/splash_screen.dart';
import 'app_controller.dart';
import 'home_shell.dart';

enum _Phase { splash, onboarding, nameEntry, login, shell }

class RootGate extends StatefulWidget {
  const RootGate({super.key});

  @override
  State<RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<RootGate> {
  late _Phase _phase;

  _Phase _afterSplash(AppController app) {
    if (!app.seenOnboarding) return _Phase.onboarding;
    if (!app.hasUserName) return _Phase.nameEntry;
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
    setState(() => _phase = app.hasUserName
        ? (app.needsLogin ? _Phase.login : _Phase.shell)
        : _Phase.nameEntry);
  }

  void _finishNameEntry() {
    if (!mounted) return;
    final app = context.read<AppController>();
    setState(() => _phase = app.needsLogin ? _Phase.login : _Phase.shell);
  }

  void _finishLogin() {
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
        _Phase.nameEntry =>
          NameScreen(key: const ValueKey('nameEntry'), onDone: _finishNameEntry),
        _Phase.login =>
          LoginScreen(key: const ValueKey('login'), onDone: _finishLogin),
        _Phase.shell => const HomeShell(key: ValueKey('shell')),
      },
    );
  }
}
