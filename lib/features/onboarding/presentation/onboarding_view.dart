import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../auth/domain/auth_session.dart';
import '../../../theme/colors.dart';
import '../../../widgets/glass_container.dart';
import '../../../widgets/premium_button.dart';
import '../../profile/domain/profile.dart';

class OnboardingView extends ConsumerStatefulWidget {
  const OnboardingView({super.key});

  @override
  ConsumerState<OnboardingView> createState() => _OnboardingViewState();
}

class _OnboardingViewState extends ConsumerState<OnboardingView> {
  final _pageController = PageController();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _ageCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();
  final _heightCtrl = TextEditingController();

  int _index = 0;
  bool _isRegisterMode = true;
  bool _authBusy = false;
  FitnessGoal? _goal;
  ActivityLevel? _activity;
  BiologicalSex? _sex;

  @override
  void dispose() {
    _pageController.dispose();
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _ageCtrl.dispose();
    _weightCtrl.dispose();
    _heightCtrl.dispose();
    super.dispose();
  }

  bool _canAdvance(AuthSession? authSession) => switch (_index) {
    0 => _goal != null && authSession != null,
    1 => _activity != null,
    2 => true,
    _ => false,
  };

  Future<void> _next(AuthSession? authSession) async {
    if (_index < 2) {
      if (_index == 0 && authSession == null) {
        _showMessage('Create an account or sign in before continuing.');
        return;
      }
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      return;
    }
    await _complete();
  }

  Future<void> _complete() async {
    final authSession = ref.read(authSessionProvider).asData?.value;
    if (authSession == null) {
      _showMessage('Sign in is required before finishing onboarding.');
      if (_index != 0) {
        _pageController.animateToPage(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
      return;
    }

    final name = _nameCtrl.text.trim();
    final profile = Profile(
      name: name.isEmpty ? null : name,
      goal: _goal ?? FitnessGoal.maintenance,
      activityLevel: _activity ?? ActivityLevel.lightlyActive,
      ageYears: int.tryParse(_ageCtrl.text.trim()),
      weightKg: double.tryParse(_weightCtrl.text.trim()),
      heightCm: double.tryParse(_heightCtrl.text.trim()),
      sex:
          _sex ??
          BiologicalSex.male, // Default to male if omitted during transition
    );
    await ref.read(localProfileRepositoryProvider).save(profile);
    if (!mounted) return;
    context.go('/app');
  }

  Future<void> _submitEmailAuth({required bool register}) async {
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;
    if (email.isEmpty || password.isEmpty) {
      _showMessage('Enter both email and password.');
      return;
    }

    setState(() => _authBusy = true);
    try {
      final authRepository = ref.read(authRepositoryProvider);
      if (register) {
        await authRepository.registerWithEmail(
          email: email,
          password: password,
          displayName: _nameCtrl.text.trim().isEmpty ? null : _nameCtrl.text.trim(),
        );
      } else {
        await authRepository.loginWithEmail(email: email, password: password);
      }
      _showMessage(register ? 'Account created successfully.' : 'Signed in successfully.');
    } catch (error) {
      _showMessage('$error');
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
      _showMessage('Signed in with Google.');
    } catch (error) {
      _showMessage('$error');
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
      _showMessage('Signed in with Apple.');
    } catch (error) {
      _showMessage('$error');
    } finally {
      if (mounted) {
        setState(() => _authBusy = false);
      }
    }
  }

  Future<void> _sendPasswordReset() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      _showMessage('Enter your email first.');
      return;
    }

    setState(() => _authBusy = true);
    try {
      await ref.read(authRepositoryProvider).sendPasswordReset(email);
      _showMessage('Password reset email sent.');
    } catch (error) {
      _showMessage('$error');
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
      _showMessage('$error');
    } finally {
      if (mounted) {
        setState(() => _authBusy = false);
      }
    }
  }

  void _showMessage(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authSession = ref.watch(authSessionProvider).asData?.value;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: _index > 0
            ? IconButton(
                icon: Icon(
                  Icons.arrow_back,
                  color: theme.colorScheme.onSurface,
                ),
                onPressed: () => _pageController.previousPage(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                ),
              )
            : const SizedBox.shrink(),
        actions: [
          TextButton(
            onPressed: _complete,
            child: Text('Skip', style: TextStyle(color: AppColors.secondary)),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              Row(
                children: List.generate(3, (i) {
                  return Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      height: 4,
                      decoration: BoxDecoration(
                        color: _index >= i
                            ? AppColors.primary
                            : AppColors.surfaceVariant,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 32),
              Expanded(
                child: PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  onPageChanged: (i) => setState(() => _index = i),
                  children: [
                    _buildGoals(theme, authSession),
                    _buildActivity(theme),
                    _buildDetails(theme),
                  ],
                ),
              ),
              PremiumButton(
                text: _index == 2 ? 'Complete' : 'Next',
                onTap: _canAdvance(authSession) ? () => _next(authSession) : () {},
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGoals(ThemeData theme, AuthSession? authSession) {
    return SingleChildScrollView(
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildAuthCard(theme, authSession),
        const SizedBox(height: 24),
        Text(
          "What is your primary goal?",
          style: theme.textTheme.displayMedium,
        ),
        const SizedBox(height: 32),
        ...FitnessGoal.values.map((g) {
          final selected = _goal == g;
          return Padding(
            padding: const EdgeInsets.only(bottom: 16.0),
            child: GestureDetector(
              onTap: () => setState(() => _goal = g),
              child: GlassContainer(
                padding: const EdgeInsets.all(20),
                border: selected
                    ? Border.all(color: AppColors.primary, width: 2)
                    : null,
                child: Row(
                  children: [
                    Icon(
                      selected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: selected ? AppColors.primary : AppColors.outline,
                    ),
                    const SizedBox(width: 16),
                    Text(g.label, style: theme.textTheme.bodyLarge),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    ));
  }

  Widget _buildActivity(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "What is your activity level?",
          style: theme.textTheme.displayMedium,
        ),
        const SizedBox(height: 32),
        ...ActivityLevel.values.map((a) {
          final selected = _activity == a;
          return Padding(
            padding: const EdgeInsets.only(bottom: 16.0),
            child: GestureDetector(
              onTap: () => setState(() => _activity = a),
              child: GlassContainer(
                padding: const EdgeInsets.all(20),
                border: selected
                    ? Border.all(color: AppColors.primary, width: 2)
                    : null,
                child: Row(
                  children: [
                    Icon(
                      selected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: selected ? AppColors.primary : AppColors.outline,
                    ),
                    const SizedBox(width: 16),
                    Text(a.label, style: theme.textTheme.bodyLarge),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildDetails(ThemeData theme) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Tell us about yourself", style: theme.textTheme.displayMedium),
          const SizedBox(height: 8),
          Text(
            "This helps us calculate your macros accurately.",
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 32),
          _textField(
            "Name (optional)",
            "e.g. Alex",
            _nameCtrl,
            keyboardType: TextInputType.name,
          ),
          const SizedBox(height: 16),
          _numField("Age", "e.g. 25", _ageCtrl),
          const SizedBox(height: 16),
          _buildSexSelector(theme),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _numField("Weight (kg)", "e.g. 65", _weightCtrl)),
              const SizedBox(width: 16),
              Expanded(
                child: _numField("Height (cm)", "e.g. 170", _heightCtrl),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _numField(
    String label,
    String hint,
    TextEditingController controller,
  ) => _textField(label, hint, controller, keyboardType: TextInputType.number);

  Widget _buildSexSelector(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Biological Sex",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        const SizedBox(height: 8),
        Row(
          children: BiologicalSex.values.map((sex) {
            final selected = _sex == sex;
            return Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _sex = sex),
                child: Container(
                  margin: EdgeInsets.only(
                    right: sex == BiologicalSex.values.last ? 0 : 12,
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: selected
                        ? AppColors.primary.withValues(alpha: 0.1)
                        : AppColors.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: selected
                          ? AppColors.primary
                          : AppColors.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    sex.label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: selected ? AppColors.primary : AppColors.onSurface,
                      fontWeight: selected
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildAuthCard(ThemeData theme, AuthSession? authSession) {
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
          _textField(
            'Email',
            'you@example.com',
            _emailCtrl,
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 16),
          _textField(
            'Password',
            'At least 8 characters',
            _passwordCtrl,
            keyboardType: TextInputType.visiblePassword,
            obscureText: true,
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
                        : () => setState(() => _isRegisterMode = !_isRegisterMode),
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

  Widget _textField(
    String label,
    String hint,
    TextEditingController controller, {
    TextInputType keyboardType = TextInputType.text,
    bool obscureText = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          obscureText: obscureText,
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: AppColors.surfaceContainerLowest,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.outlineVariant),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: AppColors.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
          ),
          keyboardType: keyboardType,
        ),
      ],
    );
  }
}
