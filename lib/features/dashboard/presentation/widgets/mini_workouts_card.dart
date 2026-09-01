import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:herculex/design_system/theme/haptics.dart';
import 'package:herculex/design_system/tokens/tokens.dart';
import 'package:herculex/features/dashboard/presentation/widgets/dashboard_shared.dart';
import 'package:herculex/features/workouts/data/micro_workouts_repository.dart';
import 'package:herculex/features/workouts/presentation/exercise_artwork.dart';
import 'package:herculex/features/workouts/presentation/exercise_picker_sheet.dart';
import 'package:herculex/features/workouts/presentation/widgets/mini_workout_sparkles.dart';
import 'package:herculex/features/workouts/presentation/workouts_providers.dart';

/// Mini Workouts checklist widget (§20). Renders an interactive task list of
/// micro-workouts for today with segmented progress dots, spring celebration
/// animations, and direct access to full habit management.
class MiniWorkoutsCard extends ConsumerWidget {
  const MiniWorkoutsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hx = context.hx;
    final todayAsync = ref.watch(microWorkoutsTodayProvider);
    final repo = ref.watch(microWorkoutsRepositoryProvider);

    return dashboardCard(
      accent: hx.domainTraining,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── 1. Card Header ──
          todayAsync.maybeWhen(
            data: (list) {
              int done = 0;
              int target = 0;
              for (final item in list) {
                done += item.completedToday;
                target += item.microWorkout.timesPerDay;
              }
              final isAllDone = target > 0 && done >= target;

              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: InkWell(
                      onTap: () => context.push('/micro-workouts'),
                      borderRadius: BorderRadius.circular(8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.checklist_rounded,
                            color: hx.domainTraining,
                            size: 20,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: dashboardTitle(context, 'Mini Workouts'),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: hx.onSurfaceVariant.withValues(alpha: 0.7),
                            size: 16,
                          ),
                        ],
                      ),
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (target > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2.5,
                          ),
                          decoration: BoxDecoration(
                            color: isAllDone
                                ? const Color(
                                    0xFF10B981,
                                  ).withValues(alpha: 0.18)
                                : hx.domainTraining.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isAllDone
                                  ? const Color(
                                      0xFF10B981,
                                    ).withValues(alpha: 0.5)
                                  : hx.domainTraining.withValues(alpha: 0.35),
                              width: 1,
                            ),
                          ),
                          child: Text(
                            '$done/$target Done',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              color: isAllDone
                                  ? const Color(0xFF10B981)
                                  : hx.domainTraining,
                            ),
                          ),
                        ),
                      const SizedBox(width: 4),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 28,
                          minHeight: 28,
                        ),
                        icon: const Icon(Icons.add_rounded, size: 18),
                        tooltip: 'Add Mini Workout',
                        onPressed: () => _createMiniWorkout(context, ref),
                      ),
                    ],
                  ),
                ],
              );
            },
            orElse: () => Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.checklist_rounded,
                      color: hx.domainTraining,
                      size: 20,
                    ),
                    const SizedBox(width: 6),
                    dashboardTitle(context, 'Mini Workouts'),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.add_rounded, size: 18),
                  onPressed: () => _createMiniWorkout(context, ref),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // ── 2. Card Content / List ──
          todayAsync.when(
            data: (list) {
              if (list.isEmpty) {
                return _buildEmptyState(context, ref, hx);
              }

              final allDone = list.every((item) => item.doneForToday);
              final totalDoneReps = list.fold<int>(
                0,
                (sum, item) => sum + item.repsCompletedToday,
              );
              final totalDoneSets = list.fold<int>(
                0,
                (sum, item) => sum + item.completedToday,
              );

              return Flexible(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (allDone) ...[
                        MiniWorkoutAllDoneBanner(
                          totalReps: totalDoneReps,
                          totalSets: totalDoneSets,
                        ),
                        const SizedBox(height: 8),
                      ],
                      for (final item in list)
                        _buildRoutineRow(context, item, repo, hx),
                    ],
                  ),
                ),
              );
            },
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
            error: (e, _) => Text(
              'Error: $e',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoutineRow(
    BuildContext context,
    MicroWorkoutStatus item,
    MicroWorkoutsRepository repo,
    HxColors hx,
  ) {
    final isDone = item.doneForToday;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: isDone
            ? const Color(0xFF10B981).withValues(alpha: 0.12)
            : hx.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDone
              ? const Color(0xFF10B981).withValues(alpha: 0.35)
              : hx.outlineVariant.withValues(alpha: 0.3),
          width: isDone ? 1.4 : 1.0,
        ),
      ),
      child: Row(
        children: [
          // Exercise artwork or glyph
          if (item.exercise != null)
            GestureDetector(
              onTap: () => context.push('/micro-workouts'),
              child: ExerciseArtwork(
                exercise: item.exercise!,
                size: 32,
                radius: 8,
              ),
            )
          else
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: hx.domainTraining.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Icon(
                  Icons.fitness_center_rounded,
                  color: hx.domainTraining,
                  size: 16,
                ),
              ),
            ),

          const SizedBox(width: 8),

          // Title & Segmented Dots
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => context.push('/micro-workouts'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.microWorkout.name,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: hx.onSurface,
                      decoration: isDone ? TextDecoration.lineThrough : null,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 1),
                  Text(
                    '${item.microWorkout.targetReps} reps/round • ${item.completedToday}/${item.microWorkout.timesPerDay}',
                    style: TextStyle(fontSize: 10, color: hx.onSurfaceVariant),
                  ),
                  const SizedBox(height: 4),
                  MiniWorkoutSegmentedProgress(
                    completed: item.completedToday,
                    total: item.microWorkout.timesPerDay,
                    dotSize: 7,
                    spacing: 4,
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(width: 6),

          // Completion Check Button with particles & bounce
          MiniWorkoutCheckButton(
            isDone: isDone,
            completedCount: item.completedToday,
            targetCount: item.microWorkout.timesPerDay,
            size: 30,
            onPressed: () {
              repo.logCompletion(item.microWorkout);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, WidgetRef ref, HxColors hx) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
      decoration: BoxDecoration(
        color: hx.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: hx.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.checklist_rtl_rounded, color: hx.domainTraining, size: 24),
          const SizedBox(height: 4),
          Text(
            'No mini workouts for today',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: hx.onSurface,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Add daily micro-habits to accumulate volume effortlessly.',
            style: TextStyle(fontSize: 11, color: hx.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _createMiniWorkout(context, ref),
            icon: const Icon(Icons.add_rounded, size: 15),
            label: const Text('Set Up Mini Habit'),
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            ),
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
              decoration: const InputDecoration(
                labelText: 'Target reps per round',
              ),
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
    await ref
        .read(microWorkoutsRepositoryProvider)
        .create(
          name: '$reps ${exercise.exercise.name}',
          exerciseId: exercise.exercise.id,
          targetReps: reps,
          timesPerDay: times,
        );
    Haptics.success();
  }
}
