import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../theme/colors.dart';
import '../../../../theme/haptics.dart';
import '../../../workouts/presentation/exercise_picker_sheet.dart';
import '../../../workouts/presentation/workouts_providers.dart';
import 'dashboard_shared.dart';
/// Mini Workouts checklist widget (§20). Renders an interactive task list of
/// micro-workouts for today. Each checkbox logs completions towards volume/recovery.
class MiniWorkoutsCard extends ConsumerWidget {
  const MiniWorkoutsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final todayAsync = ref.watch(microWorkoutsTodayProvider);
    final repo = ref.watch(microWorkoutsRepositoryProvider);

    return dashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.check_box_outlined, color: AppColors.primary, size: 22),
                  const SizedBox(width: 8),
                  dashboardTitle(context, "Mini Workouts"),
                ],
              ),
              TextButton.icon(
                onPressed: () => _createMiniWorkout(context, ref),
                icon: const Icon(Icons.add, size: 18),
                label: const Text("Add"),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          todayAsync.when(
            data: (list) {
              if (list.isEmpty) {
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'No mini workouts set up for today.',
                        style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.secondary),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: () => _createMiniWorkout(context, ref),
                        icon: const Icon(Icons.fitness_center, size: 18),
                        label: const Text('Set Up Mini Workout'),
                      ),
                    ],
                  ),
                );
              }

              return Column(
                children: [
                  for (final item in list)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: item.doneForToday
                            ? AppColors.primaryContainer.withValues(alpha: 0.25)
                            : AppColors.surfaceContainer,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: AppColors.outlineVariant.withValues(alpha: 0.3),
                        ),
                      ),
                      child: ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        leading: IconButton(
                          icon: Icon(
                            item.doneForToday
                                ? Icons.check_box_rounded
                                : Icons.check_box_outline_blank_rounded,
                            color: item.doneForToday ? AppColors.primary : AppColors.outline,
                            size: 24,
                          ),
                          onPressed: () {
                            Haptics.light();
                            repo.logCompletion(item.microWorkout);
                          },
                        ),
                        title: Text(
                          item.microWorkout.name,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            decoration: item.doneForToday ? TextDecoration.lineThrough : null,
                          ),
                        ),
                        subtitle: Text(
                          '${item.completedToday}/${item.microWorkout.timesPerDay} completed (${item.microWorkout.targetReps} reps/round)',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.secondary,
                          ),
                        ),
                        trailing: item.doneForToday
                            ? Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.green.withValues(alpha: 0.2),
                                  borderRadius: const BorderRadius.all(Radius.circular(12)),
                                ),
                                child: const Text('Done', style: TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.bold)),
                              )
                            : FilledButton.tonal(
                                onPressed: () {
                                  Haptics.light();
                                  repo.logCompletion(item.microWorkout);
                                },
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                                  visualDensity: VisualDensity.compact,
                                ),
                                child: const Text('+1 Done'),
                              ),
                      ),
                    ),
                ],
              );
            },
            loading: () => const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator())),
            error: (e, _) => Text('Error: $e', style: TextStyle(color: theme.colorScheme.error)),
          ),
        ],
      ),
    );
  }

  Future<void> _createMiniWorkout(BuildContext context, WidgetRef ref) async {
    final results = await ExercisePickerSheet.show(context);
    if (results == null || results.isEmpty || !context.mounted) return;
    final exercise = results.first;

    final repsCtrl = TextEditingController(text: '20');
    final timesCtrl = TextEditingController(text: '3');
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text('Add Mini Workout: ${exercise.exercise.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: repsCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Target reps per round'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: timesCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Times per day'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final reps = int.tryParse(repsCtrl.text) ?? 20;
    final times = (int.tryParse(timesCtrl.text) ?? 1).clamp(1, 24);
    await ref.read(microWorkoutsRepositoryProvider).create(
          name: '$reps ${exercise.exercise.name}',
          exerciseId: exercise.exercise.id,
          targetReps: reps,
          timesPerDay: times,
        );
  }
}
