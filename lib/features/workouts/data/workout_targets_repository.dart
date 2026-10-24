import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:herculex/core/utils/clock.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/workouts/data/calisthenics_progression_repository.dart';
import 'package:herculex/features/workouts/data/workouts_repository.dart';
import 'package:herculex/features/workouts/domain/calisthenics_progression.dart';
import 'package:herculex/features/workouts/domain/equipment_variants.dart';
import 'package:herculex/features/workouts/domain/logging_metric.dart';
import 'package:herculex/features/workouts/domain/progression_engine.dart';
import 'package:herculex/features/workouts/domain/workout_target_resolver.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Per-exercise hardware preferences; no database/schema change is needed.
class AssistanceSettings {
  const AssistanceSettings({this.stepKg = 2.5, this.transitionKg = 6});
  final double stepKg, transitionKg;
  static AssistanceSettings read(SharedPreferences prefs, int exerciseId) =>
      AssistanceSettings(
        stepKg: prefs.getDouble('assistance_step_$exerciseId') ?? 2.5,
        transitionKg: prefs.getDouble('assistance_transition_$exerciseId') ?? 6,
      );
  Future<void> save(SharedPreferences prefs, int exerciseId) async {
    await prefs.setDouble('assistance_step_$exerciseId', stepKg);
    await prefs.setDouble('assistance_transition_$exerciseId', transitionKg);
  }
}

extension SetValuePresence on SetEntryData {
  bool get hasEnteredWeight {
    if (weightKg != 0) return true;
    try {
      return (jsonDecode(setTypeMetaJson ?? '{}')
              as Map)['weightExplicitlyEntered'] ==
          true;
    } catch (_) {
      return false;
    }
  }
}

WorkoutTargetSet targetSetFromRow(SetEntryData row, {String assistance = ''}) {
  var automatic = false;
  double? relative;
  try {
    final meta = jsonDecode(row.setTypeMetaJson ?? '{}') as Map;
    automatic = meta['automaticWarmup'] == true;
    relative = (meta['relativeToTopSetMin'] as num?)?.toDouble();
  } catch (_) {
    /* Old/user-authored metadata is not an automatic ramp. */
  }
  return WorkoutTargetSet(
    id: row.id,
    weightKg: row.weightKg,
    reps: row.reps,
    rpeX10: row.rpeX10,
    bodyweightKg: row.bodyweightKg,
    completed: row.isCompleted,
    warmup: row.isWarmup,
    type: row.setType,
    repsMin: row.plannedRepsMin,
    repsMax: row.plannedRepsMax,
    plannedWeightKg: row.plannedWeightKg,
    targetRpeX10: row.plannedRpeX10,
    percentOf1Rm: row.plannedPercentOf1Rm,
    assistance: assistance,
    automaticWarmup: automatic,
    relativeToTopSet: relative,
  );
}

class WorkoutTargetsRepository {
  WorkoutTargetsRepository(this._db, this._clock, this._prefs);
  final AppDatabase _db;
  final Clock _clock;
  final SharedPreferences _prefs;

  Stream<Map<int, WorkoutTarget>> watch(
    int workoutExerciseId,
    ProgressionGoal goal, {
    bool nextMode = true,
  }) => _db
      .customSelect(
        'SELECT 1',
        readsFrom: {
          _db.setEntries,
          _db.workoutExercises,
          _db.workoutSessions,
          _db.exerciseProgressions,
          _db.setBands,
          _db.exerciseCatalog,
        },
      )
      .watch()
      .asyncMap((_) async {
        final we = await (_db.select(
          _db.workoutExercises,
        )..where((t) => t.id.equals(workoutExerciseId))).getSingleOrNull();
        if (we == null) return <int, WorkoutTarget>{};
        final exercise = await (_db.select(
          _db.exerciseCatalog,
        )..where((t) => t.id.equals(we.exerciseId))).getSingle();
        final sets = await WorkoutsRepository(
          _db,
          _clock,
        ).watchSetsForWorkoutExercise(we.id).first;
        return resolve(
          exercise: exercise,
          workoutExercise: we,
          sets: sets,
          goal: goal,
          nextMode: nextMode,
        );
      });

  Future<Map<int, WorkoutTarget>> resolve({
    required ExerciseCatalogData exercise,
    required WorkoutExerciseData workoutExercise,
    required List<SetEntryData> sets,
    ProgressionGoal goal = ProgressionGoal.muscleGain,
    bool nextMode = true,
  }) async {
    final variant = isMachineAssistedPullup(exercise.slug)
        ? 'machine_selectorized'
        : workoutExercise.equipmentVariant ?? exercise.modality;
    final prior = await WorkoutsRepository(
      _db,
      _clock,
    ).lastPerformanceSnapshotFor(exercise.id, equipmentVariant: variant);
    final history = prior?.sets ?? <SetEntryData>[];
    final allIds = [...sets, ...history].map((s) => s.id).toList();
    final bands = allIds.isEmpty
        ? <SetBandData>[]
        : await (_db.select(
                _db.setBands,
              )..where((t) => t.setEntryId.isIn(allIds) & t.deletedAt.isNull()))
              .get();
    String signature(int id) {
      final parts =
          bands
              .where((b) => b.setEntryId == id)
              .map((b) => '${b.bandId}:${b.count}:${b.mode}')
              .toList()
            ..sort();
      return parts.join('|');
    }

    final override = await (_db.select(
      _db.exerciseProgressions,
    )..where((t) => t.exerciseId.equals(exercise.id))).getSingleOrNull();
    final enabled = override != null && override.enabled;
    final metric = effectiveLoggingMetric(
      exercise: exercise,
      equipmentVariant: variant,
    );
    final assisted = isMachineAssistedPullup(exercise.slug);
    final path = exercise.isCustom ? null : calisthenicsPathFor(exercise.slug);
    final level = calisthenicsLevelFor(exercise.slug, variant);
    final config = AssistanceSettings.read(_prefs, exercise.id);
    final settings = WorkoutTargetSettings(
      goal: enabled
          ? ProgressionGoal.values.firstWhere(
              (g) => g.name == override.goal,
              orElse: () => goal,
            )
          : goal,
      model: enabled ? override.progressionModel : 'linear',
      weeklyPct: enabled ? override.weeklyIncreasePct : null,
      targetSets: enabled
          ? override.targetSets
          : level == null
          ? null
          : 3,
      repsMin: enabled ? override.targetRepsMin : level?.min,
      repsMax: enabled ? override.targetRepsMax : level?.max,
      stepKg: assisted ? config.stepKg : null,
      assisted: assisted,
      repOnly: !metric.has(SetField.weight),
      method: workoutExercise.plannedTrainingMethod,
      nextMode: nextMode,
      repBased: metric.isRepBased,
    );
    final resolved = WorkoutTargetResolver.resolve(
      sets: sets
          .map((s) => targetSetFromRow(s, assistance: signature(s.id)))
          .toList(),
      history: history
          .map((s) => targetSetFromRow(s, assistance: signature(s.id)))
          .toList(),
      equipment: variant,
      settings: settings,
    );
    final result = {
      for (var i = 0; i < sets.length; i++) sets[i].id: resolved[i],
    };
    // Skill paths own numeric progression on bodyweight variations, too.
    if (path != null && !assisted && nextMode) {
      final rec = (await CalisthenicsProgressionRepository(
        _db,
        _clock,
      ).recommendations())[path.id];
      if (rec != null &&
          level != null &&
          rec.current.key == level.key &&
          !level.seconds) {
        final ordinals = <String, int>{};
        for (final set in sets.where(
          (s) => !s.isWarmup && s.setType == 'standard',
        )) {
          final assistance = signature(set.id);
          final ordinal = ordinals[assistance] ?? 0;
          ordinals[assistance] = ordinal + 1;
          if (set.plannedRepsMin != null ||
              result[set.id]?.source == WorkoutTargetSource.adaptation)
            continue;
          if (level.variant == 'band' && signature(set.id) != rec.assistance) {
            result[set.id] = WorkoutTarget(
              reps: level.min,
              source: WorkoutTargetSource.prescription,
              reason:
                  'Log this assistance band to establish a comparable baseline',
            );
            continue;
          }
          var reps = rec.currentValue;
          // A skill threshold must not erase a stronger comparable set. Reset
          // reps only when the actual target load increases.
          final comparable = history
              .where(
                (s) =>
                    !s.isWarmup &&
                    s.setType == 'standard' &&
                    signature(s.id) == assistance,
              )
              .toList();
          final previous = comparable.isEmpty
              ? null
              : comparable[ordinal < comparable.length
                    ? ordinal
                    : comparable.length - 1];
          final load = variant == 'weighted' ? rec.load : 0.0;
          if (previous != null &&
              load == previous.weightKg &&
              previous.reps > reps) {
            reps = previous.reps;
          }
          result[set.id] = WorkoutTarget(
            weightKg: variant == 'weighted' ? rec.load : null,
            reps: reps,
            source: WorkoutTargetSource.progression,
            reason: rec.reason,
          );
        }
      }
    }
    return result;
  }
}
