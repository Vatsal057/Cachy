/// Decides what the user sees first: the animated splash, then (on first run)
/// onboarding, then the home shell. Keeps that branching out of main.dart.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../features/onboarding/views/onboarding_screen.dart';
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
    _phase = app.seenOnboarding ? _Phase.shell : _Phase.onboarding;
  }

  Future<void> _finishOnboarding() async {
    await context.read<AppController>().completeOnboarding();
    if (mounted) setState(() => _phase = _Phase.shell);
  }

  @override
  Widget build(BuildContext context) {
    return switch (_phase) {
      _Phase.splash => const SizedBox.shrink(),
      _Phase.onboarding =>
        OnboardingScreen(key: const ValueKey('onboarding'), onDone: _finishOnboarding),
      _Phase.shell => const HomeShell(key: ValueKey('shell')),
    };
  }
}
