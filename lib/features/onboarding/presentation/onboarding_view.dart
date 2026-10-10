import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/app/router/routes.dart';
import 'package:herculex/core/notifications/app_notice.dart';
import 'package:herculex/core/utils/auth_validator.dart';
import 'package:herculex/design_system/components/components.dart';
import 'package:herculex/design_system/components/glass_container.dart';
import 'package:herculex/design_system/components/premium_button.dart';
import 'package:herculex/design_system/theme/colors.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/gamification/domain/level_progress.dart';
import 'package:herculex/features/gamification/domain/lift_best_extractor.dart';
import 'package:herculex/features/gamification/domain/strength_standards.dart';
import 'package:herculex/features/gamification/domain/strength_survey.dart';
import 'package:herculex/features/gamification/domain/strength_tier_evaluator.dart';
import 'package:herculex/features/gamification/presentation/level_band_style.dart';
import 'package:herculex/features/profile/domain/profile.dart';

part 'onboarding_view/auth_card.part.dart';
part 'onboarding_view/fields.part.dart';
part 'onboarding_view/strength_step.part.dart';

class OnboardingView extends ConsumerStatefulWidget {
  const OnboardingView({super.key});

  @override
  ConsumerState<OnboardingView> createState() => _OnboardingViewState();
}

class _OnboardingViewState extends ConsumerState<OnboardingView> {
  static const _stepCount = 4;

  final _pageController = PageController();
  final _nameCtrl = TextEditingController();
  final _ageCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();
  final _heightCtrl = TextEditingController();

  int _index = 0;
  FitnessGoal? _goal;
  ActivityLevel? _activity;
  BiologicalSex? _sex;
  StrengthSurvey? _survey;

  @override
  void dispose() {
    _pageController.dispose();
    _nameCtrl.dispose();
    _ageCtrl.dispose();
    _weightCtrl.dispose();
    _heightCtrl.dispose();
    super.dispose();
  }

  bool get _canAdvance => switch (_index) {
    0 => _goal != null,
    1 => _activity != null,
    2 || 3 => true,
    _ => false,
  };

  Future<void> _next() async {
    if (_index < _stepCount - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      return;
    }
    await _complete();
  }

  Future<void> _complete() async {
    final name = _nameCtrl.text.trim();
    final survey = _survey;
    final profile = Profile(
      name: name.isEmpty ? null : name,
      goal: _goal ?? FitnessGoal.maintenance,
      activityLevel: _activity ?? ActivityLevel.lightlyActive,
      ageYears: int.tryParse(_ageCtrl.text.trim()),
      weightKg: double.tryParse(_weightCtrl.text.trim()),
      heightCm: double.tryParse(_heightCtrl.text.trim()),
      sex: _sex ?? BiologicalSex.male,
      strengthSurvey: survey == null || survey.isEmpty ? null : survey,
    );
    await ref.read(localProfileRepositoryProvider).save(profile);
    if (!mounted) return;
    context.go(AppRoutes.app);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
                children: List.generate(_stepCount, (i) {
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
                    _buildGoals(theme),
                    _buildActivity(theme),
                    _buildDetails(theme),
                    _StrengthStep(
                      bodyweightKg: double.tryParse(_weightCtrl.text.trim()),
                      sex: _sex,
                      onChanged: (survey) => _survey = survey,
                    ),
                  ],
                ),
              ),
              PremiumButton(
                text: _index == _stepCount - 1 ? 'Complete' : 'Next',
                onTap: _canAdvance ? _next : () {},
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGoals(ThemeData theme) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AuthCard(nameController: _nameCtrl),
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
      ),
    );
  }

  Widget _buildActivity(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "How active are you right now?",
          style: theme.textTheme.displayMedium,
        ),
        const SizedBox(height: HxSpace.x2),
        Text(
          "This is just a starting point. We'll refine it automatically as you log.",
          style: theme.textTheme.bodyMedium?.copyWith(
            color: context.hx.onSurfaceVariant,
          ),
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
          _labeledField(
            "Name (optional)",
            "e.g. Alex",
            _nameCtrl,
            keyboardType: TextInputType.name,
            maxLength: AuthValidator.maxUsernameLength,
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
  ) => _labeledField(
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
}
