part of '../onboarding_view.dart';

/// Sign-in / register card on the first onboarding step. The name field
/// lives on the details step, so it is shared in through [nameController].
class _AuthCard extends ConsumerStatefulWidget {
  const _AuthCard({required this.nameController});

  final TextEditingController nameController;

  @override
  ConsumerState<_AuthCard> createState() => _AuthCardState();
}

class _AuthCardState extends ConsumerState<_AuthCard> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _rateLimiter = AuthRateLimiter();

  bool _isRegisterMode = true;
  bool _authBusy = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submitEmailAuth({required bool register}) async {
    final (allowed, secondsRemaining) = _rateLimiter.canAttempt();
    if (!allowed) {
      _showError(
        'Too many failed attempts. Please wait $secondsRemaining seconds.',
      );
      return;
    }

    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;

    final emailError = AuthValidator.validateEmail(email);
    if (emailError != null) {
      _showError(emailError);
      return;
    }

    final passwordError = AuthValidator.validatePassword(
      password,
      isRegistration: register,
    );
    if (passwordError != null) {
      _showError(passwordError);
      return;
    }

    if (register) {
      final name = widget.nameController.text.trim();
      if (name.isNotEmpty) {
        final nameError = AuthValidator.validateUsername(name);
        if (nameError != null) {
          _showError(nameError);
          return;
        }
      }
    }

    setState(() => _authBusy = true);
    try {
      final authRepository = ref.read(authRepositoryProvider);
      if (register) {
        await authRepository.registerWithEmail(
          email: email,
          password: password,
          displayName: widget.nameController.text.trim().isEmpty
              ? null
              : widget.nameController.text.trim(),
        );
      } else {
        await authRepository.loginWithEmail(email: email, password: password);
      }
      _rateLimiter.recordSuccess();
      _showMessage(
        register ? 'Account created successfully.' : 'Signed in successfully.',
      );
    } catch (error) {
      _rateLimiter.recordFailure();
      _showError(
        '$error'
            .replaceAll('Exception: ', '')
            .replaceAll('AuthException: ', ''),
      );
    } finally {
      if (mounted) {
        setState(() => _authBusy = false);
      }
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _authBusy = true);
    try {
      await ref.read(authRepositoryProvider).signInWithGoogle();
      _rateLimiter.recordSuccess();
      _showMessage('Signed in with Google.');
    } catch (error) {
      _showError(
        '$error'
            .replaceAll('Exception: ', '')
            .replaceAll('AuthException: ', ''),
      );
    } finally {
      if (mounted) {
        setState(() => _authBusy = false);
      }
    }
  }

  Future<void> _signInWithApple() async {
    setState(() => _authBusy = true);
    try {
      await ref.read(authRepositoryProvider).signInWithApple();
      _rateLimiter.recordSuccess();
      _showMessage('Signed in with Apple.');
    } catch (error) {
      _showError(
        '$error'
            .replaceAll('Exception: ', '')
            .replaceAll('AuthException: ', ''),
      );
    } finally {
      if (mounted) {
        setState(() => _authBusy = false);
      }
    }
  }

  Future<void> _sendPasswordReset() async {
    final (allowed, secondsRemaining) = _rateLimiter.canAttempt();
    if (!allowed) {
      _showError('Too many attempts. Please wait $secondsRemaining seconds.');
      return;
    }

    final email = _emailCtrl.text.trim();
    final emailError = AuthValidator.validateEmail(email);
    if (emailError != null) {
      _showError(emailError);
      return;
    }

    setState(() => _authBusy = true);
    try {
      await ref.read(authRepositoryProvider).sendPasswordReset(email);
      _showMessage('Password reset email sent.');
    } catch (error) {
      _showError(
        '$error'
            .replaceAll('Exception: ', '')
            .replaceAll('AuthException: ', ''),
      );
    } finally {
      if (mounted) {
        setState(() => _authBusy = false);
      }
    }
  }

  Future<void> _signOut() async {
    setState(() => _authBusy = true);
    try {
      await ref.read(authRepositoryProvider).signOut();
      _showMessage('Signed out.');
    } catch (error) {
      _showError('$error');
    } finally {
      if (mounted) {
        setState(() => _authBusy = false);
      }
    }
  }

  void _showMessage(String message) {
    final notices = AppNotice.of(context);
    notices.show(message);
  }

  void _showError(String message) {
    AppNotice.showWith(
      ref,
      message.trim().isEmpty ? 'Check your connection and retry' : message,
      title: 'Could not save',
      kind: AppNoticeKind.error,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authSession = ref.watch(authSessionProvider).asData?.value;
    if (authSession != null) {
      return GlassContainer(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Account Connected', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              authSession.email ?? authSession.displayName ?? authSession.uid,
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 4),
            Text(
              'Provider: ${authSession.provider.name}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            PremiumButton(
              text: _authBusy ? 'Please wait...' : 'Sign Out',
              isPrimary: false,
              onTap: _authBusy ? () {} : _signOut,
            ),
          ],
        ),
      );
    }

    return GlassContainer(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _isRegisterMode ? 'Create your account' : 'Sign in to Herculex',
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'Use email/password, Google, or Apple before continuing.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          _labeledField(
            'Email',
            'you@example.com',
            _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            maxLength: AuthValidator.maxEmailLength,
          ),
          const SizedBox(height: 16),
          _labeledField(
            'Password',
            'At least 8 characters',
            _passwordCtrl,
            keyboardType: TextInputType.visiblePassword,
            obscureText: true,
            maxLength: AuthValidator.maxPasswordLength,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: PremiumButton(
                  text: _authBusy
                      ? 'Please wait...'
                      : (_isRegisterMode ? 'Register' : 'Sign In'),
                  onTap: _authBusy
                      ? () {}
                      : () => _submitEmailAuth(register: _isRegisterMode),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: PremiumButton(
                  text: 'Google',
                  isPrimary: false,
                  onTap: _authBusy ? () {} : _signInWithGoogle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: PremiumButton(
                  text: 'Apple',
                  isPrimary: false,
                  onTap: _authBusy ? () {} : _signInWithApple,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: _authBusy
                        ? null
                        : () => setState(
                            () => _isRegisterMode = !_isRegisterMode,
                          ),
                    child: Text(
                      _isRegisterMode
                          ? 'Already have an account? Sign in'
                          : 'Need an account? Register',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
              TextButton(
                onPressed: _authBusy ? null : _sendPasswordReset,
                child: const Text('Reset Password'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
