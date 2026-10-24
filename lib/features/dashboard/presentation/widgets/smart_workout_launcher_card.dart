import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:herculex/app/router/routes.dart';
import 'package:herculex/design_system/theme/colors.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/dashboard/application/dashboard_providers.dart';
import 'package:herculex/features/dashboard/presentation/widgets/dashboard_shared.dart';
import 'package:herculex/features/gyms/presentation/gym_picker_sheet.dart';
import 'package:herculex/features/programs/presentation/sheets/start_workout_adaptation.dart';

/// Smart workout launcher (§18): reads the day's scheduled workout and offers
/// to start it pre-populated. "Start Leg Day?" → Yes starts a real session.
class SmartWorkoutLauncherCard extends ConsumerWidget {
  const SmartWorkoutLauncherCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final today = ref.watch(todaysScheduledWorkoutProvider);

    return dashboardCard(
      accent: context.hx.domainTraining,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          dashboardTitle(context, "Today's Plan"),
          const SizedBox(height: 12),
          today.when(
            data: (workout) {
              if (workout == null) {
                return Text(
                  'No workout scheduled today.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppColors.secondary,
                  ),
                );
              }
              if (workout.isDone) {
                return Row(
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
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                      // See what today holds before committing to it.
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
                          // Theme padding (24) left ~100 dp for the day name.
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: HxSpace.x4,
                            ),
                          ),
                          onPressed: () async {
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
                                );
                            ref.invalidate(todaysScheduledWorkoutProvider);
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('Error: $e'),
          ),
        ],
      ),
    );
  }
}
