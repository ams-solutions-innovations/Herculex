import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../theme/colors.dart';
import '../../../shell/main_scaffold.dart';
import '../../domain/streaks.dart';
import '../dashboard_providers.dart';
import 'dashboard_shared.dart';
/// Consecutive days of food logging (§18).
class NutritionStreakCard extends ConsumerWidget {
  const NutritionStreakCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(nutritionStreakProvider);
    return _StreakPill(
      label: 'Nutrition Streak',
      icon: Icons.restaurant,
      unit: s.current == 1 ? 'day' : 'days',
      streak: s,
      color: AppColors.macroProtein,
      onTap: () => ref.read(mainTabIndexProvider.notifier).state = 1,
    );
  }
}

/// Consecutive training weeks (§18). Weeks, not days, so rest days don't
/// break the run.
class WorkoutStreakCard extends ConsumerWidget {
  const WorkoutStreakCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(workoutStreakProvider);
    return _StreakPill(
      label: 'Workout Streak',
      icon: Icons.fitness_center,
      unit: s.current == 1 ? 'week' : 'weeks',
      streak: s,
      color: AppColors.primary,
      onTap: () => ref.read(mainTabIndexProvider.notifier).state = 2,
    );
  }
}

class _StreakPill extends StatelessWidget {
  final String label;
  final IconData icon;
  final String unit;
  final Streak streak;
  final Color color;
  final VoidCallback? onTap;

  const _StreakPill({
    required this.label,
    required this.icon,
    required this.unit,
    required this.streak,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dim = streak.current == 0;
    return DashboardPill(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: dim ? 0.08 : 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon,
                size: 18, color: dim ? AppColors.secondary : color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                if (streak.best > 0)
                  Text('Best ${streak.best} $unit',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: AppColors.secondary, fontSize: 10)),
              ],
            ),
          ),
          if (streak.activeToday && streak.current > 0) ...[
            Icon(Icons.local_fire_department, size: 18, color: color),
            const SizedBox(width: 4),
          ],
          Text('${streak.current}',
              style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: dim ? AppColors.secondary : color)),
          const SizedBox(width: 4),
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(unit,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: AppColors.secondary)),
          ),
        ],
      ),
    );
  }
}
