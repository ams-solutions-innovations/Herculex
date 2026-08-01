import 'package:flutter/material.dart';

import '../../../theme/colors.dart';
import '../domain/daily_totals.dart';
import '../domain/macro_targets.dart';

class MacroRings extends StatelessWidget {
  final DailyTotals totals;
  final MacroTargets? targets;

  const MacroRings({super.key, required this.totals, required this.targets});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = targets;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _Ring(
          label: 'KCAL',
          current: totals.kcal.round(),
          target: t?.kcal,
          color: AppColors.macroKcal,
          theme: theme,
        ),
        _Ring(
          label: 'PROTEIN',
          current: totals.proteinG.round(),
          target: t?.proteinG,
          color: AppColors.macroProtein,
          theme: theme,
          unit: 'g',
        ),
        _Ring(
          label: 'CARBS',
          current: totals.carbsG.round(),
          target: t?.carbsG,
          color: AppColors.macroCarbs,
          theme: theme,
          unit: 'g',
        ),
        _Ring(
          label: 'FATS',
          current: totals.fatG.round(),
          target: t?.fatG,
          color: AppColors.macroFat,
          theme: theme,
          unit: 'g',
        ),
      ],
    );
  }
}

class _Ring extends StatelessWidget {
  final String label;
  final int current;
  final int? target;
  final Color color;
  final ThemeData theme;
  final String unit;

  const _Ring({
    required this.label,
    required this.current,
    required this.target,
    required this.color,
    required this.theme,
    this.unit = '',
  });

  @override
  Widget build(BuildContext context) {
    final pct = target == null || target == 0 ? null : (current / target!).clamp(0.0, 1.0);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 64,
              height: 64,
              // Always pass a concrete value: a null value makes the indicator
              // indeterminate (spins endlessly, looking like a perpetual sync).
              child: CircularProgressIndicator(
                value: pct ?? 0.0,
                strokeWidth: 5,
                backgroundColor: AppColors.surfaceVariant,
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$current$unit',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                if (target != null)
                  Text(
                    '/$target',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.secondary,
                      fontSize: 9,
                    ),
                  ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: AppColors.secondary,
            letterSpacing: 1.0,
            fontSize: 9,
          ),
        ),
      ],
    );
  }
}
