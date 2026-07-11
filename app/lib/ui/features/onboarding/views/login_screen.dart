/// Login gate, shown after onboarding + name. Google is primary; anonymous is
/// a quiet escape hatch with an honest data-loss caveat.
library;

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';

import '../../../../data/services/auth_service.dart';
import '../../../core/brand.dart';
import '../../../core/widgets/responsive_center.dart';

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final auth = context.read<AuthService>();
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
                              await auth.signInWithGoogle();
                            }),
                    icon: const PhosphorIcon(PhosphorIconsRegular.googleLogo,
                        size: 20),
                    label: const Text('Continue with Google'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(56),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Center(
                    child: TextButton(
                      onPressed: _busy
                          ? null
                          : () => _run(() async {
                                await auth.signInAnonymously();
                              }),
                      child: Text(
                        'Or use without login…',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Center(
                    child: Text(
                      'Without an account, your library lives only on this device.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
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
