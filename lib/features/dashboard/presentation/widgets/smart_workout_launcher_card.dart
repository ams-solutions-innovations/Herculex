import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../theme/colors.dart';
import '../../../gyms/presentation/gym_picker_sheet.dart';
import '../dashboard_providers.dart';
import 'dashboard_shared.dart';
/// Smart workout launcher (§18): reads the day's scheduled workout and offers
/// to start it pre-populated. "Start Leg Day?" → Yes starts a real session.
class SmartWorkoutLauncherCard extends ConsumerWidget {
  const SmartWorkoutLauncherCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final today = ref.watch(todaysScheduledWorkoutProvider);

    return dashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          dashboardTitle(context, "Today's Plan"),
          const SizedBox(height: 12),
          today.when(
            data: (workout) {
              if (workout == null) {
                return Text('No workout scheduled today.',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: AppColors.secondary));
              }
              if (workout.isDone) {
                return Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.green, size: 20),
                    const SizedBox(width: 8),
                    Text('${workout.programDay.name} complete',
                        style: theme.textTheme.titleSmall),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(workout.programDay.name,
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  Text('${workout.exerciseCount} exercises planned',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: AppColors.secondary)),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      icon: const Icon(Icons.play_arrow),
                      label: Text('Start ${workout.programDay.name}?'),
                      onPressed: () async {
                        final gym =
                            await GymPickerSheet.resolve(context, ref);
                        if (gym.cancelled) return;
                        await ref
                            .read(scheduledWorkoutServiceProvider)
                            .startScheduledWorkout(workout, gymId: gym.gymId);
                        ref.invalidate(todaysScheduledWorkoutProvider);
                      },
                    ),
                  ),
                ],
              );
            },
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('Error: $e'),
          ),
        ],
      ),
    );
  }
}
