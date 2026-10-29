import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/app/router/routes.dart';
import 'package:herculex/core/notifications/app_notice.dart';
import 'package:herculex/core/platform/platform_capabilities.dart';
import 'package:herculex/core/utils/auth_validator.dart';
import 'package:herculex/design_system/components/glass_container.dart';
import 'package:herculex/design_system/components/premium_button.dart';
import 'package:herculex/design_system/theme/colors.dart';
import 'package:herculex/features/auth/domain/auth_session.dart';
import 'package:herculex/features/profile/domain/profile.dart';

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
  final _rateLimiter = AuthRateLimiter();

  int _index = 0;
  bool _isRegisterMode = true;
  bool _authBusy = false;
  FitnessGoal? _goal;
  ActivityLevel? _activity;
  BiologicalSex? _sex;

  static const _goalMeta = <FitnessGoal, (IconData, String)>{
    FitnessGoal.weightLoss: (
      Icons.trending_down_rounded,
      'Cut body fat while preserving lean muscle',
    ),
    FitnessGoal.muscleGain: (
      Icons.fitness_center_rounded,
      'Maximize hypertrophy, strength and training volume',
    ),
    FitnessGoal.maintenance: (
      Icons.balance_rounded,
      'Maintain weight, optimize energy and body composition',
    ),
    FitnessGoal.improveHealth: (
      Icons.favorite_rounded,
      'Build cardiovascular endurance and long-term vitality',
    ),
  };

  static const _activityMeta = <ActivityLevel, (IconData, String)>{
    ActivityLevel.sedentary: (
      Icons.chair_outlined,
      'Desk job, little to no daily physical exercise',
    ),
    ActivityLevel.lightlyActive: (
      Icons.directions_walk_rounded,
      'Light daily movement, training 1–3 days per week',
    ),
    ActivityLevel.active: (
      Icons.directions_run_rounded,
      'Moderate training or sports 3–5 days per week',
    ),
    ActivityLevel.veryActive: (
      Icons.bolt_rounded,
      'Heavy physical training or demanding job 6–7 days',
    ),
    ActivityLevel.autocalibrator: (
      Icons.auto_awesome_rounded,
      'Learns dynamically from your real food logs and scale readings',
    ),
  };

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
    0 => _goal != null,
    1 => _activity != null,
    2 => true,
    _ => false,
  };

  void _prev() {
    if (_index > 0) {
      if (_pageController.hasClients) {
        _pageController.previousPage(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      } else {
        setState(() => _index--);
      }
    }
  }

  Future<void> _next(AuthSession? authSession) async {
    if (_index < 2) {
      if (_pageController.hasClients) {
        _pageController.nextPage(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      } else {
        setState(() => _index++);
      }
      return;
    }
    await _complete();
  }

  Future<void> _complete() async {
    final name = _nameCtrl.text.trim();
    final profile = Profile(
      name: name.isEmpty ? null : name,
      goal: _goal ?? FitnessGoal.maintenance,
      activityLevel: _activity ?? ActivityLevel.lightlyActive,
      ageYears: int.tryParse(_ageCtrl.text.trim()),
      weightKg: double.tryParse(_weightCtrl.text.trim()),
      heightCm: double.tryParse(_heightCtrl.text.trim()),
      sex: _sex ?? BiologicalSex.male,
    );
    await ref.read(localProfileRepositoryProvider).save(profile);
    if (!mounted) return;
    context.go(AppRoutes.app);
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
      final name = _nameCtrl.text.trim();
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
          displayName: _nameCtrl.text.trim().isEmpty
              ? null
              : _nameCtrl.text.trim(),
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
    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = width >= 640;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: isDesktop
          ? null
          : AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              leading: _index > 0
                  ? IconButton(
                      icon: Icon(
                        Icons.arrow_back,
                        color: theme.colorScheme.onSurface,
                      ),
                      onPressed: _prev,
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
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: isDesktop ? 24.0 : 20.0,
              vertical: isDesktop ? 36.0 : 16.0,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: GlassContainer(
                padding: EdgeInsets.all(isDesktop ? 36.0 : 20.0),
                borderRadius: 24,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Top header: Brand + Step Badge + Skip
                    Row(
                      children: [
                        Image.asset(
                          'assets/images/app_icon_foreground.png',
                          height: 28,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Herculex',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceContainerLowest,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: AppColors.outlineVariant.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Text(
                            'Step ${_index + 1} of 3',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: AppColors.secondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: _complete,
                          child: Text(
                            'Skip',
                            style: TextStyle(
                              color: AppColors.secondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Progress line
                    Row(
                      children: List.generate(3, (i) {
                        return Expanded(
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            height: 4,
                            decoration: BoxDecoration(
                              color: _index >= i
                                  ? AppColors.primary
                                  : AppColors.surfaceVariant.withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 32),

                    // Step content
                    switch (_index) {
                      0 => _buildGoals(theme, authSession, isDesktop: isDesktop),
                      1 => _buildActivity(theme, isDesktop: isDesktop),
                      _ => _buildDetails(theme, isDesktop: isDesktop),
                    },

                    const SizedBox(height: 32),

                    // Actions row
                    Row(
                      children: [
                        if (_index > 0) ...[
                          OutlinedButton.icon(
                            onPressed: _prev,
                            icon: const Icon(Icons.arrow_back, size: 18),
                            label: const Text('Back'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: theme.colorScheme.onSurface,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 15,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              side: BorderSide(
                                color: AppColors.outlineVariant.withValues(alpha: 0.6),
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                        ],
                        Expanded(
                          child: PremiumButton(
                            expand: true,
                            text: _index == 2 ? 'Complete setup' : 'Next',
                            onTap: _canAdvance(authSession)
                                ? () => _next(authSession)
                                : () {},
                          ),
                        ),
                      ],
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

  Widget _buildGoals(
    ThemeData theme,
    AuthSession? authSession, {
    required bool isDesktop,
  }) {
    final isWeb = ref.read(platformCapabilitiesProvider).isWeb;
    final goals = FitnessGoal.values;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Only show phone auth card on native when not signed in
        if (!isWeb && !ref.read(accountRequiredProvider)) ...[
          _buildAuthCard(theme, authSession),
          const SizedBox(height: 24),
        ],
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "What is your primary goal?",
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    "We'll adapt your training programs and nutrition targets to match.",
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (isWeb)
              TextButton(
                onPressed: () => context.go(AppRoutes.signIn),
                child: const Text('Sign in'),
              ),
          ],
        ),
        const SizedBox(height: 24),
        if (isDesktop && goals.length >= 4) ...[
          Row(
            children: [
              Expanded(child: _buildGoalCard(theme, goals[0])),
              const SizedBox(width: 14),
              Expanded(child: _buildGoalCard(theme, goals[1])),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _buildGoalCard(theme, goals[2])),
              const SizedBox(width: 14),
              Expanded(child: _buildGoalCard(theme, goals[3])),
            ],
          ),
          for (var i = 4; i < goals.length; i++) ...[
            const SizedBox(height: 14),
            _buildGoalCard(theme, goals[i]),
          ],
        ] else ...[
          for (final g in goals) ...[
            _buildGoalCard(theme, g),
            const SizedBox(height: 12),
          ],
        ],
      ],
    );
  }

  Widget _buildGoalCard(ThemeData theme, FitnessGoal g) {
    final selected = _goal == g;
    final (icon, subtitle) =
        _goalMeta[g] ?? (Icons.fitness_center_rounded, '');

    return GestureDetector(
      onTap: () => setState(() => _goal = g),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.12)
              : AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? AppColors.primary
                : AppColors.outlineVariant.withValues(alpha: 0.5),
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: selected
                    ? AppColors.primary.withValues(alpha: 0.2)
                    : Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                size: 22,
                color: selected ? AppColors.primary : AppColors.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          g.label,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: selected ? AppColors.primary : null,
                          ),
                        ),
                      ),
                      Icon(
                        selected
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked,
                        size: 20,
                        color: selected
                            ? AppColors.primary
                            : AppColors.outline.withValues(alpha: 0.5),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.onSurfaceVariant,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActivity(ThemeData theme, {required bool isDesktop}) {
    final activities = ActivityLevel.values;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "How active are you right now?",
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          "This is a baseline. We'll refine it automatically as you log workouts and daily expenditure.",
          style: theme.textTheme.bodyMedium?.copyWith(
            color: AppColors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        for (final a in activities) ...[
          _buildActivityCard(theme, a),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _buildActivityCard(ThemeData theme, ActivityLevel a) {
    final selected = _activity == a;
    final (icon, subtitle) =
        _activityMeta[a] ?? (Icons.directions_run_rounded, '');

    return GestureDetector(
      onTap: () => setState(() => _activity = a),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.12)
              : AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? AppColors.primary
                : AppColors.outlineVariant.withValues(alpha: 0.5),
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: selected
                    ? AppColors.primary.withValues(alpha: 0.2)
                    : Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                size: 22,
                color: selected ? AppColors.primary : AppColors.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    a.label,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: selected ? AppColors.primary : null,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              selected
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked,
              size: 20,
              color: selected
                  ? AppColors.primary
                  : AppColors.outline.withValues(alpha: 0.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetails(ThemeData theme, {required bool isDesktop}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Tell us about yourself",
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          "This helps us calculate your calorie targets and macros accurately.",
          style: theme.textTheme.bodyMedium?.copyWith(
            color: AppColors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        _textField(
          "Name (optional)",
          "e.g. Alex",
          _nameCtrl,
          keyboardType: TextInputType.name,
          maxLength: AuthValidator.maxUsernameLength,
        ),
        const SizedBox(height: 16),
        if (isDesktop) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _numField("Age", "e.g. 25", _ageCtrl)),
              const SizedBox(width: 16),
              Expanded(child: _buildSexSelector(theme)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _numField("Weight (kg)", "e.g. 75", _weightCtrl),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _numField("Height (cm)", "e.g. 180", _heightCtrl),
              ),
            ],
          ),
        ] else ...[
          _numField("Age", "e.g. 25", _ageCtrl),
          const SizedBox(height: 16),
          _buildSexSelector(theme),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _numField("Weight (kg)", "e.g. 75", _weightCtrl)),
              const SizedBox(width: 16),
              Expanded(child: _numField("Height (cm)", "e.g. 180", _heightCtrl)),
            ],
          ),
        ],
      ],
    );
  }

  Widget _numField(
    String label,
    String hint,
    TextEditingController controller,
  ) => _textField(
    label,
    hint,
    controller,
    keyboardType: TextInputType.number,
    maxLength: 5,
  );

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
                    right: sex == BiologicalSex.values.last ? 0 : 8,
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: selected
                        ? AppColors.primary.withValues(alpha: 0.12)
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
              expand: true,
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
            maxLength: AuthValidator.maxEmailLength,
          ),
          const SizedBox(height: 16),
          _textField(
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
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: _authBusy
                    ? null
                    : () => setState(() => _isRegisterMode = !_isRegisterMode),
                child: Text(
                  _isRegisterMode
                      ? 'Already have an account? Sign in'
                      : 'Need an account? Register',
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
    int? maxLength,
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
          maxLength: maxLength,
          decoration: InputDecoration(
            hintText: hint,
            counterText: '',
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
