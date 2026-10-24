import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/workouts/application/calisthenics_providers.dart';
import 'package:herculex/features/workouts/application/workouts_providers.dart';
import 'package:herculex/features/workouts/domain/calisthenics_progression.dart';

class CalisthenicsProgressionCard extends ConsumerWidget {
  const CalisthenicsProgressionCard({
    super.key,
    required this.exercise,
    required this.workoutExercise,
  });
  final ExerciseCatalogData exercise;
  final WorkoutExerciseData workoutExercise;

  static String? subtitleFor({
    required ExerciseCatalogData exercise,
    required WorkoutExerciseData workoutExercise,
  }) {
    final path = exercise.isCustom ? null : calisthenicsPathFor(exercise.slug);
    if (path == null) return null;
    if (path.parallelSlugs.contains(exercise.slug)) {
      return 'Technique branch';
    }
    final level = calisthenicsLevelFor(
      exercise.slug,
      workoutExercise.equipmentVariant,
    );
    if (level == null) return null;
    return '${level.label} · ${level.prescription}';
  }

  static void showDetailsSheet(
    BuildContext context, {
    required ExerciseCatalogData exercise,
    required WorkoutExerciseData workoutExercise,
  }) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Consumer(
            builder: (context, ref, _) {
              final path =
                  exercise.isCustom ? null : calisthenicsPathFor(exercise.slug);
              if (path == null) return const SizedBox.shrink();
              if (path.parallelSlugs.contains(exercise.slug)) {
                return const Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Technique branch · kipping reps do not unlock strict strength levels.',
                    ),
                  ],
                );
              }
              final level = calisthenicsLevelFor(
                exercise.slug,
                workoutExercise.equipmentVariant,
              );
              if (level == null) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${path.label} progression',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ],
                );
              }
              final recommendation = ref
                  .watch(calisthenicsRecommendationsProvider)
                  .valueOrNull?[path.id];
              final matches = recommendation?.current.key == level.key;
              final rows =
                  ref
                      .watch(setsForWorkoutExerciseProvider(workoutExercise.id))
                      .valueOrNull ??
                  <SetEntryData>[];

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${level.label} · ${level.prescription}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  if (matches) ...[
                    const SizedBox(height: 8),
                    Text(recommendation!.reason),
                  ],
                  if (matches &&
                      level.seconds &&
                      !recommendation!.ready &&
                      workoutExercise.plannedTrainingMethod == null) ...[
                    const SizedBox(height: 12),
                    Text('Next: 3 × ${recommendation.value} s'),
                    if (rows.any((s) => !s.isCompleted && !s.isWarmup))
                      TextButton(
                        onPressed: () async {
                          for (final set in rows.where(
                            (s) =>
                                !s.isCompleted &&
                                !s.isWarmup &&
                                s.setType == 'standard',
                          )) {
                            await ref
                                .read(workoutsRepositoryProvider)
                                .updateSet(
                                  setId: set.id,
                                  durationSeconds: recommendation.value,
                                );
                          }
                          if (context.mounted) Navigator.pop(context);
                        },
                        child: const Text('Use'),
                      ),
                  ],
                  if (rows.any(
                    (s) =>
                        (s.setTypeMetaJson ?? '').contains('promotionOriginal'),
                  )) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'Automatically progressed to strict pull-ups from completed training history.',
                    ),
                    TextButton(
                      onPressed: rows.any((s) => s.isCompleted)
                          ? null
                          : () async {
                              await ref
                                  .read(workoutsRepositoryProvider)
                                  .undoAutomaticProgression(workoutExercise.id);
                              if (context.mounted) Navigator.pop(context);
                            },
                      child: const Text('Restore assisted prescription'),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = exercise.isCustom ? null : calisthenicsPathFor(exercise.slug);
    if (path == null) return const SizedBox.shrink();
    if (!path.parallelSlugs.contains(exercise.slug) &&
        calisthenicsLevelFor(exercise.slug, workoutExercise.equipmentVariant) ==
            null) {
      return const SizedBox.shrink();
    }
    return _ProgressionInfoButton(
      onPressed: () => showDetailsSheet(
        context,
        exercise: exercise,
        workoutExercise: workoutExercise,
      ),
    );
  }
}

class _ProgressionInfoButton extends StatelessWidget {
  const _ProgressionInfoButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Align(
      alignment: Alignment.centerRight,
      child: IconButton(
        tooltip: 'Calisthenics progression',
        onPressed: onPressed,
        icon: const Icon(Icons.info_outline),
        iconSize: 20,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 32, height: 32),
      ),
    ),
  );
}
