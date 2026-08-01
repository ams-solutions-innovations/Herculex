import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/providers.dart';
import '../../../theme/colors.dart';
import '../../profile/domain/profile.dart';
import 'goals_providers.dart';

class GoalsView extends ConsumerWidget {
  const GoalsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider).asData?.value;
    final startingWeight = ref.watch(startingWeightProvider);
    final goalWeight = ref.watch(goalWeightProvider);
    final weeklyGoal = ref.watch(weeklyGoalProvider);
    final fitnessGoals = ref.watch(fitnessGoalsProvider);
    final showNetCarbs = ref.watch(showNetCarbsByMealProvider);

    final currentWeightStr = profile?.weightKg != null
        ? '${_fmtNum(profile!.weightKg!)} kg'
        : '--';
    final goalWeightStr = goalWeight != null
        ? '${_fmtNum(goalWeight)} kg'
        : '--';
    final startWeightStr = startingWeight != null
        ? '${_fmtNum(startingWeight.kg)} kg on ${_fmtDateIso(startingWeight.dateIso)}'
        : '--';
    final weeklyGoalStr = _weeklyGoalLabel(weeklyGoal);
    final activityStr = profile?.activityLevel.label ?? '--';

    return Scaffold(
      backgroundColor: AppColors.surfaceContainerLowest,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        title: const Text(
          'Goals',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 20, color: Colors.white),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),
      body: ListView(
        children: [
          // ── Weight & activity rows ────────────────────────────────────────
          _GoalValueRow(
            label: 'Starting Weight',
            value: startWeightStr,
            onTap: () => _editStartingWeight(context, ref, startingWeight),
          ),
          const _GoalDivider(),
          _GoalValueRow(
            label: 'Current Weight',
            value: currentWeightStr,
            onTap: () => _editCurrentWeight(context, ref, profile),
          ),
          const _GoalDivider(),
          _GoalValueRow(
            label: 'Goal Weight',
            value: goalWeightStr,
            onTap: () => _editGoalWeight(context, ref, goalWeight),
          ),
          const _GoalDivider(),
          _GoalValueRow(
            label: 'Weekly Goal',
            value: weeklyGoalStr,
            onTap: () => _editWeeklyGoal(context, ref, weeklyGoal),
          ),
          const _GoalDivider(),
          _GoalValueRow(
            label: 'Activity Level',
            value: activityStr,
            onTap: () => _editActivityLevel(context, ref, profile),
          ),

          const SizedBox(height: 32),

          // ── Nutrition Goals ───────────────────────────────────────────────
          const _SectionHeader('Nutrition Goals'),
          const _GoalDivider(),
          _GoalNavRow(
            label: 'Calorie, Net Carbs, Protein and Fat Goals',
            subtitle: 'Customize your default or daily goals.',
            onTap: () => context.push('/calorie-macro-goals'),
          ),
          const _GoalDivider(),
          _GoalNavRow(
            label: 'Calorie Goals by Meal',
            subtitle: 'Stay on track with a calorie goal for each meal.',
            onTap: () => context.push('/calorie-meal-goals'),
          ),
          const _GoalDivider(),
          _GoalToggleRow(
            label: 'Show Net Carbs, Protein and Fat By Meal',
            subtitle: 'View net carbs, protein and fat by gram or percent.',
            value: showNetCarbs,
            onChanged: (_) =>
                ref.read(showNetCarbsByMealProvider.notifier).toggle(),
          ),
          const _GoalDivider(),
          _GoalNavRow(
            label: 'Additional Nutrient Goals',
            subtitle: 'Choose which vitamins and minerals appear in the diary.',
            onTap: () => context.push('/nutrition-nutrients'),
          ),
          const _GoalDivider(),
          _GoalNavRow(
            label: 'Edit meal slots',
            subtitle:
                'Add, rename and reorder breakfast, lunch and custom meals.',
            onTap: () => context.push('/nutrition-meal-slots'),
          ),

          const SizedBox(height: 32),

          // ── Fitness Goals ─────────────────────────────────────────────────
          const _SectionHeader('Fitness Goals'),
          const _GoalDivider(),
          _GoalValueRow(
            label: 'Workouts / Week',
            value: '${fitnessGoals.workoutsPerWeek}',
            onTap: () => _editIntGoal(
              context,
              title: 'Workouts per Week',
              current: fitnessGoals.workoutsPerWeek,
              onSave: (v) =>
                  ref.read(fitnessGoalsProvider.notifier).setWorkouts(v),
            ),
          ),
          const _GoalDivider(),
          _GoalValueRow(
            label: 'Minutes / Workout',
            value: '${fitnessGoals.minutesPerWorkout}',
            onTap: () => _editIntGoal(
              context,
              title: 'Minutes per Workout',
              current: fitnessGoals.minutesPerWorkout,
              onSave: (v) =>
                  ref.read(fitnessGoalsProvider.notifier).setMinutes(v),
            ),
          ),
          const _GoalDivider(),

          const SizedBox(height: 100),
        ],
      ),
    );
  }

  // ── Edit weight / activity sheets ─────────────────────────────────────────

  Future<void> _editStartingWeight(
    BuildContext context,
    WidgetRef ref,
    StartingWeightData? current,
  ) async {
    final ctrl = TextEditingController(
      text: current?.kg != null ? _fmtNum(current!.kg) : '',
    );
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SimpleWeightSheet(
        title: 'Starting Weight',
        controller: ctrl,
        hint: 'e.g. 90.5',
        onSave: (v) {
          final kg = double.tryParse(v);
          if (kg != null) {
            ref.read(startingWeightProvider.notifier).set(kg, DateTime.now());
          }
        },
      ),
    );
  }

  Future<void> _editCurrentWeight(
    BuildContext context,
    WidgetRef ref,
    Profile? profile,
  ) async {
    final ctrl = TextEditingController(
      text: profile?.weightKg != null ? _fmtNum(profile!.weightKg!) : '',
    );
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SimpleWeightSheet(
        title: 'Current Weight',
        controller: ctrl,
        hint: 'e.g. 80.0',
        onSave: (v) async {
          final kg = double.tryParse(v);
          if (kg != null && profile != null) {
            await ref
                .read(localProfileRepositoryProvider)
                .save(profile.copyWith(weightKg: kg));
          }
        },
      ),
    );
  }

  Future<void> _editGoalWeight(
    BuildContext context,
    WidgetRef ref,
    double? current,
  ) async {
    final ctrl = TextEditingController(
      text: current != null ? _fmtNum(current) : '',
    );
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SimpleWeightSheet(
        title: 'Goal Weight',
        controller: ctrl,
        hint: 'e.g. 75.0',
        onSave: (v) {
          final kg = double.tryParse(v);
          if (kg != null) ref.read(goalWeightProvider.notifier).set(kg);
        },
      ),
    );
  }

  Future<void> _editWeeklyGoal(
    BuildContext context,
    WidgetRef ref,
    double current,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _WeeklyGoalSheet(
        current: current,
        onSave: (v) => ref.read(weeklyGoalProvider.notifier).set(v),
      ),
    );
  }

  Future<void> _editActivityLevel(
    BuildContext context,
    WidgetRef ref,
    Profile? profile,
  ) async {
    if (profile == null) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _ActivityLevelSheet(
        current: profile.activityLevel,
        onSave: (level) async {
          await ref
              .read(localProfileRepositoryProvider)
              .save(profile.copyWith(activityLevel: level));
        },
      ),
    );
  }

  Future<void> _editIntGoal(
    BuildContext context, {
    required String title,
    required int current,
    required Future<void> Function(int) onSave,
  }) async {
    final ctrl = TextEditingController(text: current > 0 ? '$current' : '');
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _IntGoalSheet(
        title: title,
        controller: ctrl,
        onSave: (v) async {
          final n = int.tryParse(v);
          if (n != null) await onSave(n);
        },
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  static String _fmtNum(double v) =>
      v == v.truncateToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  static String _fmtDateIso(String iso) {
    try {
      final d = DateTime.parse(iso);
      return DateFormat('MMM d, yyyy').format(d);
    } catch (_) {
      return iso;
    }
  }

  static String _weeklyGoalLabel(double kgPerWeek) {
    if (kgPerWeek == 0) return 'Maintain weight';
    final abs = kgPerWeek.abs();
    final verb = kgPerWeek > 0 ? 'Lose' : 'Gain';
    final n = abs == abs.truncateToDouble()
        ? abs.toInt().toString()
        : abs.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '');
    return '$verb $n kg per week';
  }
}

// ── Row widgets ───────────────────────────────────────────────────────────────

class _GoalValueRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;

  const _GoalValueRow({
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              value,
              style: TextStyle(color: AppColors.primary, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}

class _GoalNavRow extends StatelessWidget {
  final String label;
  final String? subtitle;
  final VoidCallback onTap;

  const _GoalNavRow({required this.label, this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 3),
              Text(
                subtitle!,
                style: TextStyle(color: AppColors.secondary, fontSize: 13),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _GoalToggleRow extends StatelessWidget {
  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _GoalToggleRow({
    required this.label,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    style: TextStyle(color: AppColors.secondary, fontSize: 13),
                  ),
                ],
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeTrackColor: AppColors.primary,
            activeThumbColor: Colors.white,
            trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Center(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

class _GoalDivider extends StatelessWidget {
  const _GoalDivider();

  @override
  Widget build(BuildContext context) {
    return Divider(height: 0, thickness: 0.5, color: AppColors.outlineVariant);
  }
}

// ── Bottom sheets ─────────────────────────────────────────────────────────────

class _SimpleWeightSheet extends StatelessWidget {
  final String title;
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onSave;

  const _SimpleWeightSheet({
    required this.title,
    required this.controller,
    required this.hint,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainer,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
              ],
              style: const TextStyle(color: Colors.white, fontSize: 16),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(color: AppColors.secondary),
                suffixText: 'kg',
                suffixStyle: TextStyle(color: AppColors.secondary),
                filled: true,
                fillColor: AppColors.surfaceVariant,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppColors.primary, width: 1.5),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: () {
                  onSave(controller.text.trim());
                  Navigator.of(context).pop();
                },
                child: const Text(
                  'Save',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IntGoalSheet extends StatelessWidget {
  final String title;
  final TextEditingController controller;
  final ValueChanged<String> onSave;

  const _IntGoalSheet({
    required this.title,
    required this.controller,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainer,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(color: Colors.white, fontSize: 16),
              decoration: InputDecoration(
                hintText: '0',
                hintStyle: TextStyle(color: AppColors.secondary),
                filled: true,
                fillColor: AppColors.surfaceVariant,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppColors.primary, width: 1.5),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: () {
                  onSave(controller.text.trim());
                  Navigator.of(context).pop();
                },
                child: const Text(
                  'Save',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WeeklyGoalSheet extends StatelessWidget {
  final double current;
  final ValueChanged<double> onSave;

  const _WeeklyGoalSheet({required this.current, required this.onSave});

  static const _options = <(double, String)>[
    (-0.5, 'Gain 0.5 kg per week'),
    (-0.25, 'Gain 0.25 kg per week'),
    (0.0, 'Maintain weight'),
    (0.25, 'Lose 0.25 kg per week'),
    (0.5, 'Lose 0.5 kg per week'),
    (0.75, 'Lose 0.75 kg per week'),
    (1.0, 'Lose 1 kg per week'),
    (1.25, 'Lose 1.25 kg per week'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Weekly Goal',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          for (final (value, label) in _options)
            InkWell(
              onTap: () {
                onSave(value);
                Navigator.of(context).pop();
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        style: TextStyle(
                          color: value == current
                              ? AppColors.primary
                              : Colors.white,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    if (value == current)
                      Icon(Icons.check, color: AppColors.primary, size: 20),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ActivityLevelSheet extends StatelessWidget {
  final ActivityLevel current;
  final ValueChanged<ActivityLevel> onSave;

  const _ActivityLevelSheet({required this.current, required this.onSave});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Activity Level',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          for (final level in ActivityLevel.values)
            InkWell(
              onTap: () {
                onSave(level);
                Navigator.of(context).pop();
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        level.label,
                        style: TextStyle(
                          color: level == current
                              ? AppColors.primary
                              : Colors.white,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    if (level == current)
                      Icon(Icons.check, color: AppColors.primary, size: 20),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
