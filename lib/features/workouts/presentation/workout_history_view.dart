import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:drift/drift.dart' as drift;

import '../../../data/local/database.dart';
import '../../../theme/colors.dart';
import '../../../app/providers.dart';
import '../../../core/units.dart';
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
              // Resume workout by clearing endedAt
              final stmt = ref.read(appDatabaseProvider).update(ref.read(appDatabaseProvider).workoutSessions)
                ..where((t) => t.id.equals(sessionId));
              await stmt.write(const WorkoutSessionsCompanion(endedAt: drift.Value(null)));
              if (context.mounted) {
                Navigator.of(context).pop();
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
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            itemCount: rows.length,
            itemBuilder: (_, i) {
              final we = rows[i];
              final exercise = catalog.asData?.value.firstWhere(
                (e) => e.id == we.exerciseId,
                orElse: () => _placeholder(we.exerciseId),
              );
              return _ExerciseBlock(workoutExercise: we, exerciseName: exercise?.name ?? '');
            },
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

  const _ExerciseBlock({required this.workoutExercise, required this.exerciseName});

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
                        Text('${ref.watch(weightFormatProvider).format(rows[i].weightKg)} × ${rows[i].reps}'),
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
