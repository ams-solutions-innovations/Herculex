import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:herculex/app/router/routes.dart';
import 'package:herculex/core/utils/clock.dart';
import 'package:herculex/design_system/theme/colors.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/dashboard/application/dashboard_providers.dart';
import 'package:herculex/features/dashboard/presentation/widgets/dashboard_shared.dart';
import 'package:herculex/features/gyms/presentation/gym_picker_sheet.dart';
import 'package:herculex/features/programs/presentation/sheets/start_workout_adaptation.dart';
import 'package:intl/intl.dart';

/// Smart workout launcher (§18): reads the day's scheduled workout or the
/// nearest upcoming workout, and offers to start it pre-populated.
/// Shows when the next workout is planned (e.g. "Today", "Tuesday, Oct 27").
class SmartWorkoutLauncherCard extends ConsumerWidget {
  const SmartWorkoutLauncherCard({super.key});

  static String _formatDateBadge(String dateIso, DateTime today) {
    final todayIso =
        '${today.year.toString().padLeft(4, '0')}-'
        '${today.month.toString().padLeft(2, '0')}-'
        '${today.day.toString().padLeft(2, '0')}';
    if (dateIso == todayIso) {
      return 'Today';
    }
    final scheduledDate = DateTime.tryParse(dateIso);
    if (scheduledDate == null) return dateIso;

    final todayMidnight = DateTime(today.year, today.month, today.day);
    final schedMidnight = DateTime(
      scheduledDate.year,
      scheduledDate.month,
      scheduledDate.day,
    );
    final diffDays = schedMidnight.difference(todayMidnight).inDays;

    if (diffDays == 1) {
      return 'Tomorrow, ${DateFormat('MMM d').format(scheduledDate)}';
    } else if (diffDays > 1 && diffDays < 7) {
      return '${DateFormat('EEEE').format(scheduledDate)}, ${DateFormat('MMM d').format(scheduledDate)}';
    } else {
      return DateFormat('EEE, MMM d').format(scheduledDate);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final today = ref.watch(localDayProvider);
    final nextWorkout = ref.watch(nextScheduledWorkoutProvider);

    return nextWorkout.when(
      data: (workout) {
        if (workout == null) {
          return dashboardCard(
            accent: context.hx.domainTraining,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                dashboardTitle(context, "Next Workout"),
                const SizedBox(height: 12),
                Text(
                  'No upcoming workouts scheduled.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppColors.secondary,
                  ),
                ),
              ],
            ),
          );
        }

        final todayIso =
            '${today.year.toString().padLeft(4, '0')}-'
            '${today.month.toString().padLeft(2, '0')}-'
            '${today.day.toString().padLeft(2, '0')}';
        final isToday = workout.schedule.dateIso == todayIso;
        final dateBadgeText = _formatDateBadge(workout.schedule.dateIso, today);
        final titleText = isToday ? "Today's Plan" : "Next Workout";

        return dashboardCard(
          accent: context.hx.domainTraining,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  dashboardTitle(context, titleText),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: isToday
                          ? context.hx.domainTraining.withValues(alpha: 0.15)
                          : AppColors.surfaceContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      dateBadgeText,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: isToday
                            ? context.hx.domainTraining
                            : AppColors.secondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (workout.isDone)
                Row(
                  children: [
                    const Icon(
                      Icons.check_circle,
                      color: Colors.green,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${workout.title} complete',
                      style: theme.textTheme.titleSmall,
                    ),
                  ],
                )
              else ...[
                Text(
                  workout.title,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '${workout.exerciseCount} exercises planned',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.secondary,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.visibility_outlined, size: 18),
                      label: const Text('View'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: HxSpace.x4,
                        ),
                      ),
                      onPressed: () => context.push(
                        AppPaths.plannedWorkoutPreview(workout.schedule.id),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        icon: const Icon(Icons.play_arrow),
                        label: Text(
                          workout.isInProgress
                              ? 'Resume workout'
                              : 'Start ${workout.title}?',
                          overflow: TextOverflow.ellipsis,
                        ),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: HxSpace.x4,
                          ),
                        ),
                        onPressed: () async {
                          if (!isToday) {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Start workout early?'),
                                content: Text(
                                  'This workout is scheduled for $dateBadgeText. Do you want to start it today?',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: const Text('Cancel'),
                                  ),
                                  FilledButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: const Text('Start now'),
                                  ),
                                ],
                              ),
                            );
                            if (confirm != true) return;
                            if (!context.mounted) return;
                          }

                          final gym = await GymPickerSheet.resolve(
                            context,
                            ref,
                          );
                          if (gym.cancelled) {
                            return;
                          }
                          if (!context.mounted) {
                            return;
                          }
                          if (!workout.isStarted) {
                            await offerStartWorkoutAdaptation(
                              context,
                              ref,
                              scheduleId: workout.schedule.id,
                            );
                          }
                          if (!context.mounted) {
                            return;
                          }
                          await ref
                              .read(scheduledWorkoutServiceProvider)
                              .startScheduledWorkout(
                                workout,
                                gymId: gym.gymId,
                                allowEarly: !isToday,
                              );
                          ref.invalidate(nextScheduledWorkoutProvider);
                          ref.invalidate(todaysScheduledWorkoutProvider);
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
      loading: () => dashboardCard(
        accent: context.hx.domainTraining,
        child: const Center(
          child: Padding(
            padding: EdgeInsets.all(16.0),
            child: CircularProgressIndicator(),
          ),
        ),
      ),
      error: (e, _) => dashboardCard(
        accent: context.hx.domainTraining,
        child: Text('Error: $e'),
      ),
    );
  }
}
