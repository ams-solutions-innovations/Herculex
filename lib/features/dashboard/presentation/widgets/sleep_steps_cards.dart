import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:herculex/app/router/routes.dart';
import 'package:herculex/design_system/theme/colors.dart';
import 'package:herculex/design_system/theme/haptics.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/dashboard/presentation/widgets/dashboard_shared.dart';
import 'package:herculex/features/sleep/application/sleep_providers.dart';
import 'package:herculex/features/steps/application/steps_providers.dart';
import 'package:intl/intl.dart';

class SleepDashboardCard extends ConsumerWidget {
  const SleepDashboardCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final hx = context.hx;
    final sleep = ref.watch(todaySleepProvider);
    final score = ref.watch(todaySleepScoreProvider);
    final target = ref.watch(sleepTargetHoursProvider);
    final record = sleep.valueOrNull;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 220;
        return dashboardCard(
          accent: hx.domainRecovery,
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 14 : 20,
            vertical: compact ? 12 : 16,
          ),
          onTap: () {
            Haptics.selection();
            context.push(AppRoutes.sleep);
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      compact ? 'SLEEP' : 'Sleep & Recovery',
                      style: compact
                          ? theme.textTheme.labelSmall?.copyWith(
                              color: AppColors.secondary,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.8,
                            )
                          : theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(
                    Icons.bedtime_outlined,
                    size: compact ? 16 : 20,
                    color: hx.domainRecovery,
                  ),
                ],
              ),
              SizedBox(height: compact ? 8 : 12),
              Text(
                record == null
                    ? '—'
                    : '${NumberFormat('0.0').format(record.totalHours)} h',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: hx.domainRecovery,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 3),
              Text(
                record == null
                    ? 'Sync or log last night’s sleep'
                    : 'Goal ${NumberFormat('0.#').format(target)} h'
                          '${score == null ? '' : ' · ${score.score}% recovery'}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.secondary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        );
      },
    );
  }
}

class StepsDashboardCard extends ConsumerWidget {
  const StepsDashboardCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final hx = context.hx;
    final steps = ref.watch(todayStepsProvider);
    final defaultGoal = ref.watch(stepGoalProvider);
    final record = steps.valueOrNull;
    final goal = record?.goal ?? defaultGoal;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 220;
        return dashboardCard(
          accent: hx.domainTraining,
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 14 : 20,
            vertical: compact ? 12 : 16,
          ),
          onTap: () {
            Haptics.selection();
            context.push(AppRoutes.steps);
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      compact ? 'STEPS TODAY' : 'Daily Steps',
                      style: compact
                          ? theme.textTheme.labelSmall?.copyWith(
                              color: AppColors.secondary,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.8,
                            )
                          : theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(
                    Icons.directions_walk,
                    size: compact ? 16 : 20,
                    color: hx.domainTraining,
                  ),
                ],
              ),
              SizedBox(height: compact ? 8 : 12),
              Text(
                record == null
                    ? '—'
                    : NumberFormat.decimalPattern().format(record.stepCount),
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: hx.domainTraining,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 3),
              Text(
                record == null
                    ? 'Sync or log today’s steps'
                    : 'of ${NumberFormat.decimalPattern().format(goal)} steps',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.secondary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  minHeight: 5,
                  value: record == null || goal <= 0
                      ? 0
                      : (record.stepCount / goal).clamp(0.0, 1.0),
                  backgroundColor: hx.surfaceVariant,
                  color: hx.domainTraining,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
