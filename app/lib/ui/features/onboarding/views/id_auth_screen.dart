/// Cachy ID sign-up / sign-in / password-reset, styled like the login gate.
///
/// Modes:
/// - register: brand-new username + password account. On success the recovery
///   code is shown exactly once with a save-it-or-lose-it warning.
/// - login: existing ID + password, plus a "forgot password" path that
///   consumes the recovery code (there is no email).
/// - link: same form as register, but claims the ID onto the caller's current
///   Firebase account (Google/anonymous) — afterwards both login methods
///   reach the same library.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';

import '../../../../data/services/id_auth_service.dart';
import '../../../core/brand.dart';
import '../../../core/widgets/responsive_center.dart';

enum IdAuthMode { register, login }

class IdAuthScreen extends StatefulWidget {
  const IdAuthScreen({
    super.key,
    required this.mode,
    this.linkFirebaseToken,
    required this.onDone,
  });

  final IdAuthMode mode;

  /// When set, the register form claims the ID onto this Firebase account
  /// instead of creating a standalone one.
  final String? linkFirebaseToken;
  final VoidCallback onDone;

  @override
  State<IdAuthScreen> createState() => _IdAuthScreenState();
}

class _IdAuthScreenState extends State<IdAuthScreen> {
  static final _usernameRule = RegExp(r'^[a-z0-9_]{3,20}$');

  late final IdAuthMode _mode = widget.mode;
  bool _resetting = false;
  bool _busy = false;
  bool _obscure = true;
  String? _error;
  String? _recoveryCode;
  String? _claimedUsername;

  final _username = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _recovery = TextEditingController();

  bool get _linking => widget.linkFirebaseToken != null;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _confirm.dispose();
    _recovery.dispose();
    super.dispose();
  }

  String? _validate() {
    final u = _username.text.trim().toLowerCase();
    if (!_usernameRule.hasMatch(u)) {
      return 'ID: 3-20 characters — lowercase letters, numbers, underscore.';
    }
    if (_password.text.length < 8) {
      return 'Password must be at least 8 characters.';
    }
    if ((_mode == IdAuthMode.register || _resetting) &&
        _password.text != _confirm.text) {
      return 'Passwords do not match.';
    }
    if (_resetting && _recovery.text.trim().isEmpty) {
      return 'Enter your recovery code.';
    }
    return null;
  }

  Future<void> _submit() async {
    final invalid = _validate();
    if (invalid != null) {
      setState(() => _error = invalid);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final idAuth = context.read<IdAuthService>();
      final u = _username.text.trim().toLowerCase();
      if (_resetting) {
        await idAuth.resetPassword(
          username: u,
          recoveryCode: _recovery.text,
          newPassword: _password.text,
        );
      } else if (_mode == IdAuthMode.register) {
        IdRegistration reg;
        if (_linking) {
          reg = await idAuth.link(
            username: u,
            password: _password.text,
            firebaseToken: widget.linkFirebaseToken!,
          );
        } else {
          reg = await idAuth.register(username: u, password: _password.text);
        }
        if (mounted) {
          setState(() {
            _recoveryCode = reg.recoveryCode;
            _claimedUsername = u;
          });
        }
        return;
      } else {
        await idAuth.login(username: u, password: _password.text);
      }
      if (mounted) widget.onDone();
    } on IdAuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = "That didn't work. Try again.");
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
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
              child: _recoveryCode != null
                  ? _recoveryView(theme, scheme)
                  : _formView(theme, scheme),
            ),
          ),
        ),
      ),
    );
  }

  Widget _formView(ThemeData theme, ColorScheme scheme) {
    final isRegister = _mode == IdAuthMode.register;
    final title = _resetting
        ? 'Reset your\npassword.'
        : isRegister
            ? (_linking ? 'Claim your\nCachy ID.' : 'Create your\nCachy ID.')
            : 'Welcome\nback.';
    final subtitle = _resetting
        ? 'Enter your ID, the recovery code you saved at signup, and a new password.'
        : isRegister
            ? (_linking
                ? 'This ID will sign you into the same library as your current account — use either login from now on.'
                : 'A simple ID + password. No email needed.')
            : 'Sign in with the ID you created.';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        const CachyGlyph(size: 56),
        const SizedBox(height: 32),
        Text(title, style: theme.textTheme.displaySmall),
        const SizedBox(height: 16),
        Text(subtitle,
            style: theme.textTheme.bodyLarge?.copyWith(
                color: scheme.onSurfaceVariant, height: 1.5)),
        const SizedBox(height: 28),
        _field(
          controller: _username,
          label: 'Cachy ID',
          hint: 'e.g. vatsal_42',
          keyboardType: TextInputType.text,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[a-z0-9_]')),
          ],
        ),
        const SizedBox(height: 14),
        if (_resetting)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: _field(
              controller: _recovery,
              label: 'Recovery code',
              hint: 'xxxx-xxxx-xxxx',
            ),
          ),
        _field(
          controller: _password,
          label: _resetting ? 'New password' : 'Password',
          obscure: _obscure,
          suffix: IconButton(
            icon: PhosphorIcon(
              _obscure
                  ? PhosphorIconsRegular.eye
                  : PhosphorIconsRegular.eyeSlash,
              size: 20,
            ),
            onPressed: () => setState(() => _obscure = !_obscure),
          ),
        ),
        if (isRegister || _resetting) ...[
          const SizedBox(height: 14),
          _field(
            controller: _confirm,
            label: 'Confirm password',
            obscure: true,
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 16),
          Text(_error!, style: TextStyle(color: scheme.error)),
        ],
        const Spacer(),
        FilledButton(
          onPressed: _busy ? null : _submit,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(56),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
          ),
          child: _busy
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5))
              : Text(_resetting
                  ? 'Reset password'
                  : isRegister
                      ? (_linking ? 'Claim ID' : 'Create ID')
                      : 'Sign in'),
        ),
        const SizedBox(height: 12),
        if (!_resetting && _mode == IdAuthMode.login)
          Center(
            child: TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                        _resetting = true;
                        _error = null;
                      }),
              child: const Text('Forgot password?'),
            ),
          ),
        if (_resetting)
          Center(
            child: TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                        _resetting = false;
                        _error = null;
                      }),
              child: const Text('Back to sign in'),
            ),
          ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    String? hint,
    bool obscure = false,
    Widget? suffix,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      autocorrect: false,
      enableSuggestions: false,
      textCapitalization: TextCapitalization.none,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        suffixIcon: suffix,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      ),
      onSubmitted: (_) => _submit(),
    );
  }

  /// Shown exactly once after register/link: the recovery code the user must
  /// save. There is no email, so losing this means losing the account.
  Widget _recoveryView(ThemeData theme, ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        const CachyGlyph(size: 56),
        const SizedBox(height: 32),
        Text('Save this\nrecovery code.',
            style: theme.textTheme.displaySmall),
        const SizedBox(height: 16),
        Text(
          _linking
              ? 'Cachy does not send reset emails. If you ever forget your Cachy ID password, '
                'you can use this code to reset it, or simply sign in with your Google account.'
              : 'There is no email on your Cachy ID, so Cachy cannot send password reset emails. '
                'This code is the ONLY way to reset your password. Write it down somewhere safe.',
          style: theme.textTheme.bodyLarge?.copyWith(
              color: scheme.onSurfaceVariant, height: 1.5),
        ),
        const SizedBox(height: 28),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Column(
            children: [
              if (_claimedUsername != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('@$_claimedUsername',
                      style: theme.textTheme.titleMedium),
                ),
              SelectableText(
                _recoveryCode!,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontFamily: 'monospace',
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () => Clipboard.setData(
                    ClipboardData(text: _recoveryCode!)),
                icon: const PhosphorIcon(PhosphorIconsRegular.copy, size: 18),
                label: const Text('Copy'),
              ),
            ],
          ),
        ),
        const Spacer(),
        FilledButton(
          onPressed: widget.onDone,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(56),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
          ),
          child: const Text("I've saved it — continue"),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}
