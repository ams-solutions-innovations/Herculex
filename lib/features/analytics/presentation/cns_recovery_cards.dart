import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../theme/colors.dart';
import 'analytics_providers.dart';
import 'widgets/muscle_recovery_row.dart';

/// CNS dashboard card (V2 §3): 28-day daily-load bar chart, readiness gauge,
/// and deload recommendation banner.
class CnsTrendCard extends ConsumerWidget {
  const CnsTrendCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final trends = ref.watch(cnsTrendsProvider);

    return InkWell(
      onTap: () => context.push('/cns'),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: AppColors.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'CNS Load',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Details',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      Icons.chevron_right,
                      size: 16,
                      color: AppColors.primary,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Daily nervous-system load over the last 28 days.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.secondary,
              ),
            ),
            const SizedBox(height: 16),
            trends.when(
              data: (t) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _statusBadge(t.status),
                      const SizedBox(width: 12),
                      Text(
                        'Readiness ${(t.readiness * 100).round()}%',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 120,
                    child: BarChart(
                      BarChartData(
                        gridData: const FlGridData(show: false),
                        titlesData: const FlTitlesData(show: false),
                        borderData: FlBorderData(show: false),
                        barTouchData: BarTouchData(enabled: false),
                        barGroups: [
                          for (final (i, d) in t.daily.indexed)
                            BarChartGroupData(
                              x: i,
                              barRods: [
                                BarChartRodData(
                                  toY: d.load > 0 ? d.load : 0.02,
                                  width: 5,
                                  color: d.load > 0
                                      ? AppColors.primary
                                      : AppColors.outlineVariant.withValues(
                                          alpha: 0.3,
                                        ),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (t.recommendation != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: (t.deloadSuggested ? Colors.red : Colors.amber)
                            .withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            t.deloadSuggested
                                ? Icons.battery_alert
                                : Icons.warning_amber,
                            size: 18,
                            color: t.deloadSuggested
                                ? Colors.red
                                : Colors.amber,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              t.recommendation!,
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text('Error: $e'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusBadge(String status) {
    final color = switch (status) {
      'FRESH' => Colors.green,
      'MODERATE' => Colors.amber,
      _ => Colors.red,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        status,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }
}

/// Granular recovery card (V2 §2): 19 muscle-group scores as bars plus
/// under-recovery / weekly-MRV warnings.
class RecoveryDetailCard extends ConsumerWidget {
  const RecoveryDetailCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final recovery = ref.watch(recoveryV3Provider);
    final warnings = ref.watch(recoveryWarningsProvider);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Muscle Recovery',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '19 muscle groups, effective-load weighted (bands, chains, bodyweight, fat grips).',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.secondary,
            ),
          ),
          const SizedBox(height: 12),
          warnings.maybeWhen(
            data: (list) => list.isEmpty
                ? const SizedBox.shrink()
                : Column(
                    children: [
                      for (final w in list)
                        Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.warning_amber,
                                size: 16,
                                color: Colors.red,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  w.message,
                                  style: theme.textTheme.bodySmall,
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 6),
                    ],
                  ),
            orElse: () => const SizedBox.shrink(),
          ),
          recovery.when(
            data: (list) => Column(
              children: [
                for (final r in list)
                  MuscleRecoveryRow(
                    muscle: r.muscle,
                    recoveryScore: r.recoveryScore,
                  ),
              ],
            ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('Error: $e'),
          ),
        ],
      ),
    );
  }
}
