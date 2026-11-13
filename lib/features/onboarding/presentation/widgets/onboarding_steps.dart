import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:herculex/core/utils/auth_validator.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/onboarding/presentation/widgets/onboarding_controls.dart';
import 'package:herculex/features/profile/domain/profile.dart';

const _goalDescriptions = <FitnessGoal, String>{
  FitnessGoal.weightLoss: 'Calorie deficit, keep strength',
  FitnessGoal.muscleGain: 'Lean surplus, progressive overload',
  FitnessGoal.maintenance: 'Hold weight, build performance',
  FitnessGoal.improveHealth: 'Habits, sleep, steps, consistency',
};

const _activityDescriptions = <ActivityLevel, String>{
  ActivityLevel.autocalibrator:
      'Measures your real TDEE from weight and food logs, so you do not '
      'have to guess.',
};

/// Step 1: primary goal.
class OnboardingGoalStep extends StatelessWidget {
  const OnboardingGoalStep({
    super.key,
    required this.goal,
    required this.onChanged,
  });

  final FitnessGoal? goal;
  final ValueChanged<FitnessGoal> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const OnboardingHeading(
          title: 'What is your primary goal?',
          subtitle: 'Sets your calorie direction and how programs are built.',
        ),
        const SizedBox(height: 20),
        for (final g in FitnessGoal.values) ...[
          OnboardingOptionCard(
            title: g.label,
            description: _goalDescriptions[g],
            selected: goal == g,
            onTap: () => onChanged(g),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

/// Step 2: basic body measurements.
class OnboardingDetailsStep extends StatelessWidget {
  const OnboardingDetailsStep({
    super.key,
    required this.nameCtrl,
    required this.ageCtrl,
    required this.weightCtrl,
    required this.heightCtrl,
    required this.targetCtrl,
    required this.sex,
    required this.onSexChanged,
    required this.imperial,
    required this.onImperialChanged,
  });

  final TextEditingController nameCtrl;
  final TextEditingController ageCtrl;
  final TextEditingController weightCtrl;
  final TextEditingController heightCtrl;
  final TextEditingController targetCtrl;
  final BiologicalSex? sex;
  final ValueChanged<BiologicalSex> onSexChanged;

  /// Display-only toggle: stored values stay metric, see the view's
  /// conversion on save.
  final bool imperial;
  final ValueChanged<bool> onImperialChanged;

  static final _decimal = [
    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
  ];

  @override
  Widget build(BuildContext context) {
    final hx = context.hx;
    final text = Theme.of(context).textTheme;
    final weightUnit = imperial ? 'lb' : 'kg';
    final heightUnit = imperial ? 'in' : 'cm';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const OnboardingHeading(
          title: 'Tell us about yourself',
          subtitle: 'This helps us calculate your macros accurately.',
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: OnboardingSegmented<bool>(
            expand: false,
            options: const {false: 'Metric', true: 'Freedom'},
            value: imperial,
            onChanged: onImperialChanged,
          ),
        ),
        const SizedBox(height: 16),
        OnboardingField(
          label: 'Name',
          hint: 'e.g. Alex',
          optional: true,
          controller: nameCtrl,
          keyboardType: TextInputType.name,
          maxLength: AuthValidator.maxUsernameLength,
        ),
        const SizedBox(height: 16),
        Text(
          'Biological Sex',
          style: text.labelLarge?.copyWith(
            color: hx.onSurface,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: HxSpace.x2),
        OnboardingSegmented<BiologicalSex>(
          options: {for (final s in BiologicalSex.values) s: s.label},
          value: sex,
          onChanged: onSexChanged,
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: OnboardingField(
                label: 'Age',
                hint: '27',
                controller: ageCtrl,
                keyboardType: TextInputType.number,
                maxLength: 3,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OnboardingField(
                label: 'Weight',
                hint: imperial ? '150' : '70',
                unit: weightUnit,
                controller: weightCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                maxLength: 5,
                inputFormatters: _decimal,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OnboardingField(
                label: 'Height',
                hint: imperial ? '67' : '170',
                unit: heightUnit,
                controller: heightCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                maxLength: 5,
                inputFormatters: _decimal,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        OnboardingField(
          label: 'Target weight',
          optional: true,
          hint: imperial ? 'e.g. 135' : 'e.g. 60',
          unit: weightUnit,
          controller: targetCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          maxLength: 5,
          inputFormatters: _decimal,
        ),
      ],
    );
  }
}

/// Step 3: activity level. Auto-calibrator leads and is the skip default.
class OnboardingActivityStep extends StatelessWidget {
  const OnboardingActivityStep({
    super.key,
    required this.activity,
    required this.onChanged,
  });

  final ActivityLevel? activity;
  final ValueChanged<ActivityLevel> onChanged;

  @override
  Widget build(BuildContext context) {
    // The enum already lists autocalibrator first.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const OnboardingHeading(
          title: 'How active are you right now?',
          subtitle:
              'This is just a starting point. We will refine it automatically '
              'as you log.',
        ),
        const SizedBox(height: 20),
        for (final a in ActivityLevel.values) ...[
          OnboardingOptionCard(
            title: a.label,
            description: _activityDescriptions[a],
            badge: a == ActivityLevel.autocalibrator ? 'Recommended' : null,
            selected: activity == a,
            onTap: () => onChanged(a),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}
