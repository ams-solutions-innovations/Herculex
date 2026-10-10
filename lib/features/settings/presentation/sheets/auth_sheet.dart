import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/core/utils/auth_validator.dart';
import 'package:herculex/core/utils/env.dart';
import 'package:herculex/design_system/components/components.dart';
import 'package:herculex/design_system/tokens/tokens.dart';

/// Email / Google sign-in sheet for the optional cloud account.
class AuthSheet extends ConsumerStatefulWidget {
  const AuthSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const AuthSheet(),
    );
  }

  @override
  ConsumerState<AuthSheet> createState() => _AuthSheetState();
}

class _AuthSheetState extends ConsumerState<AuthSheet> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _rateLimiter = AuthRateLimiter();
  bool _busy = false;
  bool _isRegister = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final (allowed, secondsRemaining) = _rateLimiter.canAttempt();
    if (!allowed) {
      setState(
        () => _errorMessage =
            'Too many failed attempts. Please wait $secondsRemaining seconds.',
      );
      return;
    }

    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;

    final emailError = AuthValidator.validateEmail(email);
    if (emailError != null) {
      setState(() => _errorMessage = emailError);
      return;
    }

    final passwordError = AuthValidator.validatePassword(
      password,
      isRegistration: _isRegister,
    );
    if (passwordError != null) {
      setState(() => _errorMessage = passwordError);
      return;
    }

    setState(() {
      _busy = true;
      _errorMessage = null;
    });

    try {
      final repo = ref.read(authRepositoryProvider);
      if (_isRegister) {
        await repo.registerWithEmail(email: email, password: password);
      } else {
        await repo.loginWithEmail(email: email, password: password);
      }
      _rateLimiter.recordSuccess();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _rateLimiter.recordFailure();
      if (mounted) {
        setState(() {
          _errorMessage = e
              .toString()
              .replaceAll('Exception: ', '')
              .replaceAll('AuthException: ', '');
          _busy = false;
        });
      }
    }
  }

  Future<void> _googleSignIn() async {
    setState(() {
      _busy = true;
      _errorMessage = null;
    });
    try {
      await ref.read(authRepositoryProvider).signInWithGoogle();
      _rateLimiter.recordSuccess();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e
              .toString()
              .replaceAll('Exception: ', '')
              .replaceAll('AuthException: ', '');
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return HxSheet(
      scrollable: false,
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 0,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: context.hx.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.cloud_sync_rounded,
                  color: context.hx.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isRegister
                          ? 'Create Herculex Account'
                          : 'Sign in to Herculex',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Sync your workouts and nutrition across devices',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: context.hx.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            maxLength: AuthValidator.maxEmailLength,
            decoration: InputDecoration(
              labelText: 'Email',
              counterText: '',
              prefixIcon: const Icon(Icons.email_outlined),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _passwordCtrl,
            obscureText: true,
            maxLength: AuthValidator.maxPasswordLength,
            decoration: InputDecoration(
              labelText: 'Password',
              counterText: '',
              prefixIcon: const Icon(Icons.lock_outline),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              _errorMessage!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 13),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _busy ? null : _submit,
            style: FilledButton.styleFrom(
              backgroundColor: context.hx.primary,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    _isRegister ? 'Create Account & Sync' : 'Sign In & Sync',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
          ),
          if (Env.hasGoogleSignIn) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _busy ? null : _googleSignIn,
              icon: const Icon(Icons.g_mobiledata_rounded, size: 24),
              label: const Text('Continue with Google'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          TextButton(
            onPressed: _busy
                ? null
                : () => setState(() {
                    _isRegister = !_isRegister;
                    _errorMessage = null;
                  }),
            child: Text(
              _isRegister
                  ? 'Already have an account? Sign In'
                  : "Don't have an account? Create one",
              style: TextStyle(color: context.hx.primary),
            ),
          ),
        ],
      ),
    );
  }
}
