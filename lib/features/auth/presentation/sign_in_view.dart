import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/core/utils/auth_validator.dart';
import 'package:herculex/design_system/components/components.dart';
import 'package:herculex/design_system/components/premium_button.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/auth/domain/auth_redirect.dart';

/// The web app's front door. Unlike the phone — which works offline without
/// an account and offers sign-in from Settings — every web session belongs to
/// a signed-in user, so the router sends anyone without a session here.
///
/// Successful sign-in needs no navigation of its own: the session reaches
/// `authSessionProvider`, the router's refresh listener fires, and the
/// redirect chain moves on to restoring data and then the app.
class SignInView extends ConsumerStatefulWidget {
  const SignInView({super.key});

  @override
  ConsumerState<SignInView> createState() => _SignInViewState();
}

class _SignInViewState extends ConsumerState<SignInView> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _rateLimiter = AuthRateLimiter();

  bool _isRegister = false;
  bool _busy = false;
  bool _obscure = true;
  String? _error;
  String? _notice;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  String _messageOf(Object e) => e
      .toString()
      .replaceAll('Exception: ', '')
      .replaceAll('AuthException: ', '');

  Future<void> _submit() async {
    final (allowed, secondsRemaining) = _rateLimiter.canAttempt();
    if (!allowed) {
      setState(
        () => _error =
            'Too many failed attempts. Please wait $secondsRemaining seconds.',
      );
      return;
    }

    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;
    final name = _nameCtrl.text.trim();
    final validation =
        AuthValidator.validateEmail(email) ??
        AuthValidator.validatePassword(password, isRegistration: _isRegister) ??
        (_isRegister ? AuthValidator.validateUsername(name) : null);
    if (validation != null) {
      setState(() => _error = validation);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    final repo = ref.read(authRepositoryProvider);
    try {
      if (_isRegister) {
        await repo.registerWithEmail(
          email: email,
          password: password,
          displayName: name.isEmpty ? null : name,
        );
      } else {
        await repo.loginWithEmail(email: email, password: password);
      }
      _rateLimiter.recordSuccess();
      TextInput.finishAutofillContext();
    } catch (e) {
      _rateLimiter.recordFailure();
      if (mounted) setState(() => _error = _messageOf(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _google() async {
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await ref.read(authRepositoryProvider).signInWithGoogle();
    } on AuthRedirectStarted catch (e) {
      // The browser is leaving for Google; keep the spinner up until it does.
      if (mounted) setState(() => _notice = e.toString());
      return;
    } catch (e) {
      if (mounted) setState(() => _error = _messageOf(e));
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _forgotPassword() async {
    final email = _emailCtrl.text.trim();
    final emailError = AuthValidator.validateEmail(email);
    if (emailError != null) {
      setState(() {
        _error = 'Enter your email above first, then tap "Forgot password".';
        _notice = null;
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).sendPasswordReset(email);
      if (mounted) {
        setState(
          () => _notice =
              'If an account exists for $email, a reset link is on its way.',
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = _messageOf(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hx = context.hx;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(HxSpace.x6),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Image.asset(
                      'assets/images/app_icon_foreground.png',
                      height: 72,
                      color: hx.primary,
                    ),
                    const SizedBox(height: HxSpace.x6),
                    Text(
                      _isRegister ? 'Create your account' : 'Welcome back',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineMedium,
                    ),
                    const SizedBox(height: HxSpace.x2),
                    Text(
                      'Sign in with the account you use on your phone — '
                      'your workouts, meals and programs sync both ways.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: HxSpace.x8),
                    HxCard(
                      padding: const EdgeInsets.all(HxSpace.x6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          HxTopTabs(
                            labels: const ['Sign in', 'Create account'],
                            index: _isRegister ? 1 : 0,
                            onChanged: _busy
                                ? (_) {}
                                : (i) => setState(() {
                                    _isRegister = i == 1;
                                    _error = null;
                                    _notice = null;
                                  }),
                          ),
                          const SizedBox(height: HxSpace.x5),
                          if (_isRegister) ...[
                            TextField(
                              controller: _nameCtrl,
                              enabled: !_busy,
                              maxLength: AuthValidator.maxUsernameLength,
                              textInputAction: TextInputAction.next,
                              autofillHints: const [AutofillHints.name],
                              decoration: const InputDecoration(
                                hintText: 'Name',
                                counterText: '',
                                prefixIcon: Icon(Icons.person_outline_rounded),
                              ),
                            ),
                            const SizedBox(height: HxSpace.x3),
                          ],
                          TextField(
                            controller: _emailCtrl,
                            enabled: !_busy,
                            keyboardType: TextInputType.emailAddress,
                            autocorrect: false,
                            maxLength: AuthValidator.maxEmailLength,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [AutofillHints.email],
                            decoration: const InputDecoration(
                              hintText: 'Email',
                              counterText: '',
                              prefixIcon: Icon(Icons.mail_outline_rounded),
                            ),
                          ),
                          const SizedBox(height: HxSpace.x3),
                          TextField(
                            controller: _passwordCtrl,
                            enabled: !_busy,
                            obscureText: _obscure,
                            maxLength: AuthValidator.maxPasswordLength,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _submit(),
                            autofillHints: [
                              _isRegister
                                  ? AutofillHints.newPassword
                                  : AutofillHints.password,
                            ],
                            decoration: InputDecoration(
                              hintText: 'Password',
                              counterText: '',
                              prefixIcon: const Icon(
                                Icons.lock_outline_rounded,
                              ),
                              suffixIcon: IconButton(
                                tooltip: _obscure
                                    ? 'Show password'
                                    : 'Hide password',
                                icon: Icon(
                                  _obscure
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                ),
                                onPressed: () =>
                                    setState(() => _obscure = !_obscure),
                              ),
                            ),
                          ),
                          if (_error != null || _notice != null) ...[
                            const SizedBox(height: HxSpace.x3),
                            Text(
                              _error ?? _notice!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: _error != null
                                    ? hx.danger
                                    : hx.primaryText,
                              ),
                            ),
                          ],
                          const SizedBox(height: HxSpace.x5),
                          _busy
                              ? const Center(
                                  child: Padding(
                                    padding: EdgeInsets.all(HxSpace.x3),
                                    child: CircularProgressIndicator(),
                                  ),
                                )
                              : PremiumButton(
                                  text: _isRegister
                                      ? 'Create account'
                                      : 'Sign in',
                                  expand: true,
                                  onTap: _submit,
                                ),
                          if (!_isRegister)
                            Align(
                              child: TextButton(
                                onPressed: _busy ? null : _forgotPassword,
                                child: const Text('Forgot password?'),
                              ),
                            ),
                          const SizedBox(height: HxSpace.x2),
                          Row(
                            children: [
                              Expanded(
                                child: Divider(
                                  color: hx.outlineVariant.withValues(
                                    alpha: 0.6,
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: HxSpace.x3,
                                ),
                                child: Text(
                                  'or',
                                  style: theme.textTheme.labelMedium,
                                ),
                              ),
                              Expanded(
                                child: Divider(
                                  color: hx.outlineVariant.withValues(
                                    alpha: 0.6,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: HxSpace.x3),
                          PremiumButton(
                            text: 'Continue with Google',
                            icon: Icons.g_mobiledata_rounded,
                            isPrimary: false,
                            expand: true,
                            onTap: _busy ? () {} : _google,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: HxSpace.x6),
                    Text(
                      'By continuing you agree to the Terms of Service and '
                      'Privacy Policy at herculex.app.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
