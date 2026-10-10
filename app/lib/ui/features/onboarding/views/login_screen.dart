/// Login gate, shown right after onboarding. Google is primary; "use without
/// login" runs anonymous auth and can be upgraded to Google later (the uid is
/// preserved via account linking, so guest data carries over).
library;

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';

import '../../../../data/services/id_auth_service.dart';
import '../../../core/brand.dart';
import '../../../core/widgets/responsive_center.dart';
import 'id_auth_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.onDone});
  final VoidCallback onDone;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (mounted) widget.onDone();
    } catch (_) {
      if (mounted) {
        setState(() =>
            _error = "Couldn't sign in. Check your connection and try again.");
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Push the Cachy ID form; its own onDone completes the login gate.
  void _openIdAuth(IdAuthMode mode) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => IdAuthScreen(mode: mode, onDone: widget.onDone),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      body: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -0.45),
            radius: 1.3,
            colors: [
              scheme.primary.withValues(alpha: 0.12),
              Colors.transparent,
            ],
          ),
        ),
        child: SafeArea(
          child: ResponsiveCenter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 48),
                  const CachyGlyph(size: 56),
                  const SizedBox(height: 32),
                  Text('Keep your\nlibrary safe.',
                      style: theme.textTheme.displaySmall),
                  const SizedBox(height: 16),
                  Text(
                    'Sign in so your cards follow you to any device — and survive a reinstall.',
                    style: theme.textTheme.bodyLarge?.copyWith(
                        color: scheme.onSurfaceVariant, height: 1.5),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(_error!, style: TextStyle(color: scheme.error)),
                  ],
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _run(() async {
                              final idAuth = context.read<IdAuthService>();
                              await idAuth.loginJudgeDemo();
                            }),
                    icon: const PhosphorIcon(PhosphorIconsRegular.sparkle,
                        size: 20),
                    label: const Text('Explore Hackathon Demo Shelf'),
                    style: FilledButton.styleFrom(
                      backgroundColor: scheme.primary,
                      foregroundColor: scheme.onPrimary,
                      minimumSize: const Size.fromHeight(56),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _openIdAuth(IdAuthMode.login),
                    icon: const PhosphorIcon(PhosphorIconsRegular.user,
                        size: 20),
                    label: const Text('Sign in with Cachy ID'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(56),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Center(
                    child: TextButton.icon(
                      onPressed:
                          _busy ? null : () => _openIdAuth(IdAuthMode.register),
                      icon: const PhosphorIcon(PhosphorIconsRegular.at, size: 16),
                      label: Text(
                        'Create a new Cachy ID',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
