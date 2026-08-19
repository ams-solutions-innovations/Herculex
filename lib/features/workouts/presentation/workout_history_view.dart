import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:drift/drift.dart' as drift;

import '../../../data/local/database.dart';
import '../../../theme/colors.dart';
import '../../../app/providers.dart';
import '../../../core/units.dart';
import '../domain/logging_metric.dart';
import '../domain/set_metric_format.dart';
import 'duration_picker_dialog.dart';
import 'workouts_providers.dart';

class WorkoutHistoryView extends ConsumerWidget {
  final int sessionId;
  const WorkoutHistoryView({super.key, required this.sessionId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final exercises = ref.watch(sessionExercisesProvider(sessionId));
    final catalog = ref.watch(exerciseCatalogProvider(const ExerciseCatalogFilter()));
    final sessionAsync = ref.watch(workoutSessionProvider(sessionId));

    return Scaffold(
      appBar: AppBar(
        title: Text(_titleFor(sessionAsync.asData?.value)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: 'Edit Workout',
            onPressed: () async {
              final session = sessionAsync.asData?.value;
              final originalEndedAt = session?.endedAt;
              if (originalEndedAt != null) {
                ref.read(editingSessionOriginalEndedAtProvider.notifier).update(
                  (state) => {...state, sessionId: originalEndedAt},
                );
              }
              // Resume workout by clearing endedAt
              final stmt = ref.read(appDatabaseProvider).update(ref.read(appDatabaseProvider).workoutSessions)
                ..where((t) => t.id.equals(sessionId));
              await stmt.write(const WorkoutSessionsCompanion(endedAt: drift.Value(null)));
              if (context.mounted) {
                Navigator.of(context).pop();
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
            tooltip: 'Delete Workout',
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Delete workout?'),
                  content: const Text(
                      'This permanently deletes this workout and all logged sets.'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text(
                        'Delete',
                        style: TextStyle(color: Colors.redAccent),
                      ),
                    ),
                  ],
                ),
              );
              if (confirmed == true && context.mounted) {
                await ref.read(workoutsRepositoryProvider).deleteSession(sessionId);
                if (context.mounted) {
                  Navigator.of(context).pop();
                }
              }
            },
          ),
        ],
      ),
      body: exercises.when(
        data: (rows) {
          if (rows.isEmpty) {
            return Center(
              child: Text('No exercises logged', style: theme.textTheme.bodyMedium),
            );
          }
          final session = sessionAsync.asData?.value;
          final duration = session?.endedAt != null
              ? session!.endedAt!.difference(session.startedAt)
              : null;
          final durationStr = duration == null
              ? ''
              : duration.inHours > 0
                  ? '${duration.inHours}h ${duration.inMinutes.remainder(60)}m'
                  : '${duration.inMinutes}m';

          return Column(
            children: [
              if (session != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        DateFormat('EEE, MMM d • HH:mm').format(session.startedAt),
                        style: theme.textTheme.bodySmall?.copyWith(color: AppColors.secondary),
                      ),
                      InkWell(
                        onTap: () async {
                          final currentDur = session.endedAt?.difference(session.startedAt) ??
                              const Duration(minutes: 45);
                          final newMins = await DurationPickerDialog.show(
                            context,
                            initialMinutes: currentDur.inMinutes > 0 ? currentDur.inMinutes : 45,
                          );
                          if (newMins != null && newMins > 0) {
                            final newEndedAt = session.startedAt.add(Duration(minutes: newMins));
                            await ref
                                .read(workoutsRepositoryProvider)
                                .endSession(session.id, endedAt: newEndedAt);
                          }
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.timer_outlined, size: 14, color: AppColors.primary),
                              const SizedBox(width: 4),
                              Text(
                                durationStr.isNotEmpty ? durationStr : 'Set duration',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(Icons.edit_outlined, size: 12, color: AppColors.primary),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  itemCount: rows.length,
                  itemBuilder: (_, i) {
                    final we = rows[i];
                    final exercise = catalog.asData?.value.firstWhere(
                      (e) => e.id == we.exerciseId,
                      orElse: () => _placeholder(we.exerciseId),
                    );
                    return _ExerciseBlock(
                      workoutExercise: we,
                      exerciseName: exercise?.name ?? '',
                      metric: LoggingMetric.fromId(exercise?.loggingMetric),
                    );
                  },
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }

  /// The session's own name, falling back to its date when unnamed.
  String _titleFor(WorkoutSessionData? session) {
    if (session == null) return 'Workout';
    final name = session.name?.trim() ?? '';
    if (name.isNotEmpty) return name;
    return DateFormat('EEE, MMM d').format(session.startedAt);
  }

  ExerciseCatalogData _placeholder(int id) => ExerciseCatalogData(
        id: id,
        name: 'Unknown',
        primaryMuscle: '',
        equipment: '',
        mechanics: '',
        force: '',
        plane: '',
        defaultRestSeconds: 120,
        isCustom: false,
        category: 'strength',
        modality: 'barbell',
        cnsScore: 3,
        recoveryImpact: 3,
        loggingMetric: 'weight_reps',
        supportsWeightedBodyweight: false,
        isReviewed: false,
      );
}

class _ExerciseBlock extends ConsumerWidget {
  final WorkoutExerciseData workoutExercise;
  final String exerciseName;

  /// What this exercise is measured in — a logged plank reads as `2:00` here,
  /// not as `0 kg × 0` (EXR-05).
  final LoggingMetric metric;

  const _ExerciseBlock({
    required this.workoutExercise,
    required this.exerciseName,
    required this.metric,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final sets = ref.watch(setsForWorkoutExerciseProvider(workoutExercise.id));

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(exerciseName, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          sets.when(
            data: (rows) => Column(
              children: [
                for (var i = 0; i < rows.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 28,
                          child: Text(
                            rows[i].isWarmup ? 'W' : '${i + 1}',
                            style: theme.textTheme.titleSmall,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(SetMetricFormat.summariseSet(
                          rows[i],
                          metric: metric,
                          weight: ref.watch(weightFormatProvider),
                          distance: ref.watch(distanceFormatProvider),
                        )),
                        if (rows[i].rpeX10 != null) ...[
                          const SizedBox(width: 12),
                          Text(
                            '@${(rows[i].rpeX10! / 10).toStringAsFixed(1)}',
                            style: theme.textTheme.bodySmall?.copyWith(color: AppColors.primary),
                          ),
                        ],
                        if (rows[i].completedAt != null) ...[
                          const Spacer(),
                          Text(
                            DateFormat('HH:mm').format(rows[i].completedAt!),
                            style: theme.textTheme.bodySmall?.copyWith(color: AppColors.secondary),
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}
