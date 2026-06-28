/// Decides what the user sees first: the animated splash, then (on first run)
/// onboarding, then the home shell. Keeps that branching out of main.dart.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../features/onboarding/views/onboarding_screen.dart';
import '../features/onboarding/views/splash_screen.dart';
import 'app_controller.dart';
import 'home_shell.dart';

enum _Phase { splash, onboarding, shell }

class RootGate extends StatefulWidget {
  const RootGate({super.key});

  @override
  State<RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<RootGate> {
  late _Phase _phase;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppController>();
    _phase = kIsWeb
        ? (app.seenOnboarding ? _Phase.shell : _Phase.onboarding)
        : _Phase.splash;
  }

  void _finishSplash() {
    if (!mounted) return;
    final app = context.read<AppController>();
    setState(() => _phase = app.seenOnboarding ? _Phase.shell : _Phase.onboarding);
  }

  Future<void> _finishOnboarding() async {
    await context.read<AppController>().completeOnboarding();
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
        _Phase.shell => const HomeShell(key: ValueKey('shell')),
      },
    );
  }
}
