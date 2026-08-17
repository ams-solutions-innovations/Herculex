import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/colors.dart';
import '../../../theme/system_ui.dart';
import 'goals_providers.dart';
import 'nutrition_providers.dart';

class CalorieMealGoalsView extends ConsumerWidget {
  const CalorieMealGoalsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meal = ref.watch(mealGoalsProvider);
    final baseline = ref.watch(baselineTargetsProvider);
    final totalKcal = baseline?.kcal ?? 0;

    return Scaffold(
      backgroundColor: AppColors.surfaceContainerLowest,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        title: Text(
          'Calorie Goals by Meal',
          style: TextStyle(
            color: AppColors.onSurface,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios,
              size: 20, color: AppColors.onSurface),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        systemOverlayStyle: overlayStyleFor(context),
      ),
      body: ListView(
        children: [
          // ── Enable Meal Goals toggle ─────────────────────────────────────
          _ToggleRow(
            label: 'Enable Meal Goals',
            value: meal.enabled,
            onChanged: (v) =>
                ref.read(mealGoalsProvider.notifier).setEnabled(v),
          ),

          const SizedBox(height: 32),

          // ── Set Meal Goals section ───────────────────────────────────────
          const _SectionHeader('Set Meal Goals'),
          const _Divider(),

          // Calories / % segmented control
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: _ModeSegmentedControl(
              showAsCalories: meal.showAsCalories,
              onChanged: (v) =>
                  ref.read(mealGoalsProvider.notifier).setShowAsCalories(v),
            ),
          ),

          const _Divider(),

          // Total Daily Goal row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Total Daily Goal',
                    style: TextStyle(color: AppColors.onSurface, fontSize: 16),
                  ),
                ),
                Text(
                  meal.showAsCalories
                      ? _fmtKcal(totalKcal)
                      : '100%',
                  style: TextStyle(
                    color: AppColors.onSurface,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

          const _Divider(),

          // Meal rows
          _MealRow(
            label: 'Breakfast',
            pct: meal.breakfastPct,
            kcal: meal.mealCalories(totalKcal, meal.breakfastPct),
            showAsCalories: meal.showAsCalories,
            onTap: meal.enabled
                ? () => _editMealPct(
                      context,
                      ref,
                      meal: 'Breakfast',
                      current: meal.breakfastPct,
                      onSave: (v) => ref
                          .read(mealGoalsProvider.notifier)
                          .setBreakfastPct(v),
                    )
                : null,
          ),
          const _Divider(),

          _MealRow(
            label: 'Lunch',
            pct: meal.lunchPct,
            kcal: meal.mealCalories(totalKcal, meal.lunchPct),
            showAsCalories: meal.showAsCalories,
            onTap: meal.enabled
                ? () => _editMealPct(
                      context,
                      ref,
                      meal: 'Lunch',
                      current: meal.lunchPct,
                      onSave: (v) =>
                          ref.read(mealGoalsProvider.notifier).setLunchPct(v),
                    )
                : null,
          ),
          const _Divider(),

          _MealRow(
            label: 'Dinner',
            pct: meal.dinnerPct,
            kcal: meal.mealCalories(totalKcal, meal.dinnerPct),
            showAsCalories: meal.showAsCalories,
            onTap: meal.enabled
                ? () => _editMealPct(
                      context,
                      ref,
                      meal: 'Dinner',
                      current: meal.dinnerPct,
                      onSave: (v) => ref
                          .read(mealGoalsProvider.notifier)
                          .setDinnerPct(v),
                    )
                : null,
          ),
          const _Divider(),

          _MealRow(
            label: 'Snacks',
            pct: meal.snacksPct,
            kcal: meal.mealCalories(totalKcal, meal.snacksPct),
            showAsCalories: meal.showAsCalories,
            onTap: meal.enabled
                ? () => _editMealPct(
                      context,
                      ref,
                      meal: 'Snacks',
                      current: meal.snacksPct,
                      onSave: (v) => ref
                          .read(mealGoalsProvider.notifier)
                          .setSnacksPct(v),
                    )
                : null,
          ),

          const SizedBox(height: 100),
        ],
      ),
    );
  }

  Future<void> _editMealPct(
    BuildContext context,
    WidgetRef ref, {
    required String meal,
    required double current,
    required Future<void> Function(double) onSave,
  }) async {
    final ctrl = TextEditingController(
      text: current == current.truncateToDouble()
          ? current.toInt().toString()
          : current.toStringAsFixed(1),
    );
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _MealPctSheet(
        meal: meal,
        controller: ctrl,
        onSave: (v) async {
          final pct = double.tryParse(v);
          if (pct != null && pct >= 0 && pct <= 100) await onSave(pct);
        },
      ),
    );
  }

  static String _fmtKcal(int v) => v
      .toString()
      .replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
        (m) => '${m[1]},',
      );
}

// ── Widgets ───────────────────────────────────────────────────────────────────

class _ToggleRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: AppColors.onSurface, fontSize: 16),
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
          style: TextStyle(
            color: AppColors.onSurface,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

class _ModeSegmentedControl extends StatelessWidget {
  final bool showAsCalories;
  final ValueChanged<bool> onChanged;

  const _ModeSegmentedControl({
    required this.showAsCalories,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        height: 36,
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Segment(
              label: 'Calories',
              selected: showAsCalories,
              isFirst: true,
              onTap: () => onChanged(true),
            ),
            _Segment(
              label: '%',
              selected: !showAsCalories,
              isFirst: false,
              onTap: () => onChanged(false),
            ),
          ],
        ),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  final String label;
  final bool selected;
  final bool isFirst;
  final VoidCallback onTap;

  const _Segment({
    required this.label,
    required this.selected,
    required this.isFirst,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : AppColors.secondary,
            fontSize: 15,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

class _MealRow extends StatelessWidget {
  final String label;
  final double pct;
  final int kcal;
  final bool showAsCalories;
  final VoidCallback? onTap;

  const _MealRow({
    required this.label,
    required this.pct,
    required this.kcal,
    required this.showAsCalories,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final pctStr = pct == pct.truncateToDouble()
        ? '${pct.toInt()}%'
        : '${pct.toStringAsFixed(1)}%';

    final rightValue = showAsCalories ? '$kcal' : pctStr;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        child: Row(
          children: [
            Text(
              label,
              style: TextStyle(color: AppColors.onSurface, fontSize: 16),
            ),
            const SizedBox(width: 8),
            Text(
              pctStr,
              style: TextStyle(
                color: AppColors.secondary,
                fontSize: 16,
              ),
            ),
            const Spacer(),
            Text(
              rightValue,
              style: TextStyle(color: AppColors.primary, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 0,
      thickness: 0.5,
      color: AppColors.outlineVariant,
    );
  }
}

// ── Edit sheet ────────────────────────────────────────────────────────────────

class _MealPctSheet extends StatelessWidget {
  final String meal;
  final TextEditingController controller;
  final ValueChanged<String> onSave;

  const _MealPctSheet({
    required this.meal,
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
              '$meal Goal',
              style: TextStyle(
                color: AppColors.onSurface,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
              ],
              style: TextStyle(color: AppColors.onSurface, fontSize: 16),
              decoration: InputDecoration(
                hintText: '30',
                hintStyle: TextStyle(color: AppColors.secondary),
                suffixText: '%',
                suffixStyle: TextStyle(color: AppColors.secondary),
                filled: true,
                fillColor: AppColors.surfaceVariant,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      BorderSide(color: AppColors.primary, width: 1.5),
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