import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/colors.dart';
import 'exercise_picker_sheet.dart';
import 'workouts_providers.dart';

/// Micro workouts (V2 §20): daily mini-task checklist. Each check-off writes a
/// real one-set workout session, so volume/recovery/analytics include it.
class MicroWorkoutsView extends ConsumerWidget {
  const MicroWorkoutsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final today = ref.watch(microWorkoutsTodayProvider);
    final repo = ref.watch(microWorkoutsRepositoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Micro Workouts')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: today.when(
                data: (list) => list.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text(
                            'No micro workouts yet.\ne.g. "50 pushups, 3× per day" — completions count toward volume and recovery.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(color: AppColors.secondary),
                          ),
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          for (final s in list)
                            Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              decoration: BoxDecoration(
                                color: s.doneForToday
                                    ? AppColors.primaryContainer
                                        .withValues(alpha: 0.25)
                                    : AppColors.surfaceContainerLowest,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                    color: AppColors.outlineVariant
                                        .withValues(alpha: 0.3)),
                              ),
                              child: ListTile(
                                leading: Icon(
                                  s.doneForToday
                                      ? Icons.check_circle
                                      : Icons.radio_button_unchecked,
                                  color: s.doneForToday
                                      ? AppColors.primary
                                      : AppColors.outline,
                                ),
                                title: Text(s.microWorkout.name,
                                    style: theme.textTheme.titleSmall
                                        ?.copyWith(
                                            fontWeight: FontWeight.w600)),
                                subtitle: Text(
                                    '${s.microWorkout.targetReps} reps • '
                                    '${s.completedToday}/${s.microWorkout.timesPerDay} today'),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (!s.doneForToday)
                                      FilledButton.tonal(
                                        onPressed: () =>
                                            repo.logCompletion(s.microWorkout),
                                        child: const Text('Done'),
                                      ),
                                    PopupMenuButton<String>(
                                      onSelected: (a) {
                                        if (a == 'delete') {
                                          repo.delete(s.microWorkout.id);
                                        }
                                      },
                                      itemBuilder: (_) => const [
                                        PopupMenuItem(
                                            value: 'delete',
                                            child: Text('Delete')),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error: $e')),
              ),
            ),
            // Bottom-anchored primary action (§22).
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => _create(context, ref),
                    icon: const Icon(Icons.add),
                    label: const Text('New Micro Workout'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final results = await ExercisePickerSheet.show(context);
    if (results == null || results.isEmpty || !context.mounted) return;
    final exercise = results.first;

    final repsCtrl = TextEditingController(text: '20');
    final timesCtrl = TextEditingController(text: '3');
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(exercise.exercise.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: repsCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Reps per round'),
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
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(dialogCtx, true),
              child: const Text('Create')),
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
