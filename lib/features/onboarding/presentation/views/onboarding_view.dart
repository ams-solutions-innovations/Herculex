import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/app/router/routes.dart';
import 'package:herculex/core/notifications/app_notice.dart';
import 'package:herculex/core/platform/platform_capabilities.dart';
import 'package:herculex/core/utils/auth_validator.dart';
import 'package:herculex/core/utils/units.dart';
import 'package:herculex/features/onboarding/presentation/widgets/onboarding_email_page.dart';
import 'package:herculex/features/onboarding/presentation/widgets/onboarding_intro_page.dart';
import 'package:herculex/features/onboarding/presentation/widgets/onboarding_scaffold.dart';
import 'package:herculex/features/onboarding/presentation/widgets/onboarding_steps.dart';
import 'package:herculex/features/onboarding/presentation/widgets/onboarding_summary_step.dart';
import 'package:herculex/features/onboarding/presentation/widgets/onboarding_welcome_page.dart';
import 'package:herculex/features/profile/domain/profile.dart';

/// Where the person is in the flow: sign in, the four-page intro, then the
/// numbered setup steps.
enum _Stage { welcome, email, intro, steps }

/// The numbered setup steps. Steps from the design that need their own
/// services (strength check, avatar, look, cycle, health, notifications) are
/// not part of this build yet; the progress bar counts only what is shown.
enum _Step { goal, details, activity, summary }

class OnboardingView extends ConsumerStatefulWidget {
  const OnboardingView({super.key});

  @override
  ConsumerState<OnboardingView> createState() => _OnboardingViewState();
}

class _OnboardingViewState extends ConsumerState<OnboardingView> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _ageCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();
  final _heightCtrl = TextEditingController();
  final _targetCtrl = TextEditingController();
  final _rateLimiter = AuthRateLimiter();

  _Stage _stage = _Stage.welcome;
  int _introIndex = 0;
  _Step _step = _Step.goal;
  bool _registerMode = true;
  bool _authBusy = false;
  bool _stageChosen = false;
  FitnessGoal? _goal;
  ActivityLevel? _activity;
  BiologicalSex? _sex;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _ageCtrl.dispose();
    _weightCtrl.dispose();
    _heightCtrl.dispose();
    _targetCtrl.dispose();
    super.dispose();
  }

  // ── Navigation ──────────────────────────────────────────────────────────

  bool get _signedIn => ref.read(authSessionProvider).asData?.value != null;

  /// Already signed in (returning to finish setup): nothing to ask on the
  /// welcome page, so the flow opens on the intro.
  void _resolveInitialStage(bool signedIn) {
    if (_stageChosen) return;
    if (signedIn && _stage == _Stage.welcome) {
      _stage = _Stage.intro;
      _stageChosen = true;
    }
  }

  void _enterIntro() => setState(() {
    _stage = _Stage.intro;
    _introIndex = 0;
    _stageChosen = true;
  });

  void _enterSteps() => setState(() {
    _stage = _Stage.steps;
    _step = _Step.goal;
    _stageChosen = true;
  });

  void _introNext() {
    if (_introIndex < introPillars.length - 1) {
      setState(() => _introIndex++);
    } else {
      _enterSteps();
    }
  }

  void _introBack() {
    if (_introIndex > 0) {
      setState(() => _introIndex--);
    } else if (!_signedIn) {
      setState(() => _stage = _Stage.welcome);
    }
  }

  void _stepNext() {
    if (_step == _Step.details) {
      final name = _nameCtrl.text.trim();
      if (name.isNotEmpty) {
        final error = AuthValidator.validateUsername(name);
        if (error != null) {
          _showError(error);
          return;
        }
      }
    }
    if (_step == _Step.summary) {
      _complete();
      return;
    }
    setState(() => _step = _Step.values[_step.index + 1]);
  }

  void _stepBack() {
    if (_step.index > 0) {
      setState(() => _step = _Step.values[_step.index - 1]);
    } else {
      setState(() {
        _stage = _Stage.intro;
        _introIndex = introPillars.length - 1;
      });
    }
  }

  bool get _canAdvance => switch (_step) {
    _Step.goal => _goal != null,
    _Step.activity => _activity != null,
    _ => true,
  };

  // ── Profile ─────────────────────────────────────────────────────────────

  double? _kg(TextEditingController c) {
    final v = double.tryParse(c.text.trim().replaceAll(',', '.'));
    if (v == null) return null;
    return ref.read(weightFormatProvider).toKg(v);
  }

  double? _cm(TextEditingController c) {
    final v = double.tryParse(c.text.trim().replaceAll(',', '.'));
    if (v == null) return null;
    return ref.read(unitsProvider) == MeasurementUnit.metric
        ? v
        : Units.inchToCm(v);
  }

  /// The profile the answers add up to, with the skip defaults applied
  /// (Auto-calibrator, Maintenance, Male for the BMR offset).
  Profile _draftProfile() {
    final name = _nameCtrl.text.trim();
    return Profile(
      name: name.isEmpty ? null : name,
      goal: _goal ?? FitnessGoal.maintenance,
      activityLevel: _activity ?? ActivityLevel.autocalibrator,
      ageYears: int.tryParse(_ageCtrl.text.trim()),
      weightKg: _kg(_weightCtrl),
      targetWeightKg: _kg(_targetCtrl),
      heightCm: _cm(_heightCtrl),
      sex: _sex ?? BiologicalSex.male,
      preferredUnit: ref.read(unitsProvider),
    );
  }

  Future<void> _complete({String? then}) async {
    await ref.read(localProfileRepositoryProvider).save(_draftProfile());
    if (!mounted) return;
    context.go(AppRoutes.app);
    if (then != null) context.push(then);
  }

  /// Re-expresses typed measurements in the other system so flipping the
  /// toggle does not leave "70" meaning pounds.
  Future<void> _setImperial(bool imperial) async {
    final units = ref.read(unitsProvider.notifier);
    final from = ref.read(unitsProvider);
    final to = imperial ? MeasurementUnit.imperial : MeasurementUnit.metric;
    if (from == to) return;

    String convert(String raw, double Function(double) f) {
      final v = double.tryParse(raw.trim().replaceAll(',', '.'));
      if (v == null) return raw;
      final out = f(v);
      return out == out.roundToDouble()
          ? out.round().toString()
          : out.toStringAsFixed(1);
    }

    final toImperial = imperial;
    _weightCtrl.text = convert(
      _weightCtrl.text,
      toImperial ? Units.kgToLb : Units.lbToKg,
    );
    _targetCtrl.text = convert(
      _targetCtrl.text,
      toImperial ? Units.kgToLb : Units.lbToKg,
    );
    _heightCtrl.text = convert(
      _heightCtrl.text,
      toImperial ? Units.cmToInch : Units.inchToCm,
    );
    await units.set(to);
  }

  // ── Auth ────────────────────────────────────────────────────────────────

  String _cleanError(Object error) =>
      '$error'.replaceAll('Exception: ', '').replaceAll('AuthException: ', '');

  Future<void> _runAuth(
    Future<void> Function() action,
    String successMessage,
  ) async {
    setState(() => _authBusy = true);
    try {
      await action();
      _rateLimiter.recordSuccess();
      if (!mounted) return;
      _showMessage(successMessage);
      _enterIntro();
    } catch (error) {
      _rateLimiter.recordFailure();
      _showError(_cleanError(error));
    } finally {
      if (mounted) setState(() => _authBusy = false);
    }
  }

  Future<void> _submitEmailAuth() async {
    final register = _registerMode;
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

    final repo = ref.read(authRepositoryProvider);
    await _runAuth(
      () => register
          ? repo.registerWithEmail(email: email, password: password)
          : repo.loginWithEmail(email: email, password: password),
      register ? 'Account created successfully.' : 'Signed in successfully.',
    );
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
      _showError(_cleanError(error));
    } finally {
      if (mounted) setState(() => _authBusy = false);
    }
  }

  void _showMessage(String message) => AppNotice.of(context).show(message);

  void _showError(String message) {
    AppNotice.showWith(
      ref,
      message.trim().isEmpty ? 'Check your connection and retry' : message,
      title: 'Could not save',
      kind: AppNoticeKind.error,
    );
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final signedIn = ref.watch(authSessionProvider).asData?.value != null;
    _resolveInitialStage(signedIn);

    return switch (_stage) {
      _Stage.welcome => OnboardingWelcomePage(
        busy: _authBusy,
        onApple: () => _runAuth(
          ref.read(authRepositoryProvider).signInWithApple,
          'Signed in with Apple.',
        ),
        onGoogle: () => _runAuth(
          ref.read(authRepositoryProvider).signInWithGoogle,
          'Signed in with Google.',
        ),
        onEmail: () => setState(() {
          _registerMode = true;
          _stage = _Stage.email;
        }),
        onSignIn: () => setState(() {
          _registerMode = false;
          _stage = _Stage.email;
        }),
        onContinueWithoutAccount:
            ref.read(platformCapabilitiesProvider).isWeb ||
                ref.read(accountRequiredProvider)
            ? null
            : _enterIntro,
      ),
      _Stage.email => OnboardingEmailPage(
        register: _registerMode,
        busy: _authBusy,
        emailCtrl: _emailCtrl,
        passwordCtrl: _passwordCtrl,
        onBack: () => setState(() => _stage = _Stage.welcome),
        onSubmit: _submitEmailAuth,
        onToggleMode: () => setState(() => _registerMode = !_registerMode),
        onForgotPassword: _sendPasswordReset,
        onApple: () => _runAuth(
          ref.read(authRepositoryProvider).signInWithApple,
          'Signed in with Apple.',
        ),
        onGoogle: () => _runAuth(
          ref.read(authRepositoryProvider).signInWithGoogle,
          'Signed in with Google.',
        ),
      ),
      _Stage.intro => OnboardingIntroPage(
        index: _introIndex,
        onNext: _introNext,
        onSkipIntro: _enterSteps,
        onBack: _introIndex == 0 && signedIn ? null : _introBack,
      ),
      _Stage.steps => _buildStep(),
    };
  }

  Widget _buildStep() {
    // Rebuild when the unit system flips so labels and hints follow.
    final imperial = ref.watch(unitsProvider) == MeasurementUnit.imperial;
    final isSummary = _step == _Step.summary;

    final body = switch (_step) {
      _Step.goal => OnboardingGoalStep(
        goal: _goal,
        onChanged: (g) => setState(() => _goal = g),
      ),
      _Step.details => OnboardingDetailsStep(
        nameCtrl: _nameCtrl,
        ageCtrl: _ageCtrl,
        weightCtrl: _weightCtrl,
        heightCtrl: _heightCtrl,
        targetCtrl: _targetCtrl,
        sex: _sex,
        onSexChanged: (s) => setState(() => _sex = s),
        imperial: imperial,
        onImperialChanged: _setImperial,
      ),
      _Step.activity => OnboardingActivityStep(
        activity: _activity,
        onChanged: (a) => setState(() => _activity = a),
      ),
      _Step.summary => OnboardingSummaryStep(
        profile: _draftProfile(),
        onPickProgram: _complete,
        onSetPhysique: () => _complete(then: AppRoutes.dreamPhysique),
      ),
    };

    return OnboardingScaffold(
      onBack: _stepBack,
      onSkip: isSummary ? null : _stepNext,
      progressStep: _step.index,
      progressTotal: _Step.values.length,
      topPadding: 28,
      ctaLabel: isSummary ? 'Start training' : 'Next',
      onCta: _canAdvance ? _stepNext : null,
      child: body,
    );
  }
}
