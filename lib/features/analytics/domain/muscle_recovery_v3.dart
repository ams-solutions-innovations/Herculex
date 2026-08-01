import 'dart:math';

import 'package:health/health.dart';
import '../../../data/local/database.dart';
import '../../health/domain/external_workout_cns_mapper.dart';
import 'training_snapshot.dart';

/// Recovery status for one of the 19 tracked muscle groups (V2 §2).
class MuscleGroupRecovery {
  final String muscle;

  /// 0 = fully wrecked, 100 = fully recovered.
  final int recoveryScore;

  /// Working sets in the trailing 7 days (drives MRV warnings).
  final double weeklySets;

  const MuscleGroupRecovery({
    required this.muscle,
    required this.recoveryScore,
    required this.weeklySets,
  });

  String get status {
    if (recoveryScore >= 70) return 'RECOVERED';
    if (recoveryScore >= 30) return 'RECOVERING';
    return 'FATIGUED';
  }
}

class RecoveryWarning {
  final String muscle;
  final String message;
  const RecoveryWarning(this.muscle, this.message);
}

/// Recovery engine v3 (V2 §2): granular 19-group output computed from
/// [ResolvedSet]s, so bands/chains/bodyweight count via effective load and
/// fat grips raise forearm demand. Decay uses the exercise's recoveryImpact
/// (heavier systemic cost ⇒ slower recovery).
class MuscleRecoveryV3 {
  /// The 19 muscle groups mandated by the spec.
  static const groups = [
    'Chest', 'Back', 'Lats', 'Traps', 'Front Delts', 'Side Delts',
    'Rear Delts', 'Biceps', 'Triceps', 'Forearms', 'Abs', 'Obliques', 'Neck',
    'Quads', 'Hamstrings', 'Glutes', 'Calves', 'Adductors', 'Abductors',
  ];

  /// Maps source dataset muscle names onto the 19 display groups.
  static const alias = <String, String>{
    'Serratus': 'Chest',
    'Rhomboids': 'Back',
    'Erectors': 'Back',
    'Brachialis': 'Biceps',
    'Core': 'Abs',
    'Hip Flexors': 'Quads',
    'Tibialis': 'Calves',
    'Shoulders': 'Side Delts',
    'Arms': 'Biceps',
  };

  static const roleWeight = {
    'primary': 1.0,
    'secondary': 0.5,
    'stabilizer': 0.2,
  };

  static const _windowHours = 96;
  static const _perSetBase = 0.13;

  /// Default weekly MRV (maximum recoverable volume) in hard sets per muscle.
  /// Conservative literature-typical values; user-tunable later.
  static const defaultWeeklyMrv = <String, double>{
    'Chest': 22, 'Back': 25, 'Lats': 22, 'Traps': 20, 'Front Delts': 16,
    'Side Delts': 25, 'Rear Delts': 25, 'Biceps': 20, 'Triceps': 18,
    'Forearms': 20, 'Abs': 25, 'Obliques': 20, 'Neck': 15, 'Quads': 20,
    'Hamstrings': 16, 'Glutes': 16, 'Calves': 20, 'Adductors': 16,
    'Abductors': 16,
  };

  static List<MuscleGroupRecovery> compute({
    required TrainingSnapshot snapshot,
    List<HealthDataPoint> externalWorkouts = const [],
    required DateTime asOf,
  }) {
    final fatigue = {for (final g in groups) g: 0.0};
    final weeklySets = {for (final g in groups) g: 0.0};

    final musclesByExercise = <int, List<ExerciseMuscleData>>{};
    for (final m in snapshot.exerciseMuscles) {
      musclesByExercise.putIfAbsent(m.exerciseId, () => []).add(m);
    }

    for (final rs in snapshot.sets) {
      final completedAt = rs.set.completedAt;
      if (completedAt == null) continue;
      final hours = asOf.difference(completedAt).inHours;
      if (hours < 0 || hours > 24 * 7) continue;

      final rows = musclesByExercise[rs.exercise.id] ?? const [];
      final involvement = rows.isNotEmpty
          ? [
              for (final r in rows)
                (
                  alias[r.muscle] ?? r.muscle,
                  (roleWeight[r.role] ?? 0) * r.contribution,
                )
            ]
          : [(alias[rs.exercise.primaryMuscle] ?? rs.exercise.primaryMuscle, 1.0)];

      // Weekly set counts (per-muscle fractional credit by role weight).
      for (final (muscle, w) in involvement) {
        if (weeklySets.containsKey(muscle)) {
          weeklySets[muscle] = weeklySets[muscle]! + (w >= 1.0 ? 1.0 : w);
        }
      }

      if (hours > _windowHours) continue;

      final rpe =
          rs.set.rpeX10 != null ? rs.set.rpeX10! / 10.0 : 7.0;
      final rpeFactor = rpe >= 9
          ? 1.6
          : rpe >= 8
              ? 1.3
              : 1.0;
      // Higher systemic recovery cost decays more slowly.
      final halfLife = 18.0 + 6.0 * rs.exercise.recoveryImpact; // 24–48h
      final perSet = _perSetBase *
          (rs.exercise.recoveryImpact / 3.0) *
          rpeFactor *
          rs.setType.cnsFactor *
          exp(-hours * ln2 / halfLife);

      for (final (muscle, w) in involvement) {
        if (!fatigue.containsKey(muscle)) continue;
        // Fat grips & thick-bar work hammer the forearms harder (§8).
        final mult = muscle == 'Forearms' ? rs.forearmMultiplier : 1.0;
        fatigue[muscle] =
            (fatigue[muscle]! + perSet * w * mult).clamp(0.0, 1.0);
      }
    }

    for (final workout in externalWorkouts) {
      if (workout.value is! WorkoutHealthValue) continue;
      final wv = workout.value as WorkoutHealthValue;
      
      final hours = asOf.difference(workout.dateTo).inHours;
      if (hours < 0 || hours > _windowHours) continue;

      final impact = ExternalWorkoutCnsMapper.getImpactFor(wv.workoutActivityType);
      
      final durationMinutes = workout.dateTo.difference(workout.dateFrom).inMinutes;
      final equivalentSets = (durationMinutes / 60.0) * 15.0; // 15 sets per hour
      
      final halfLife = 18.0 + 6.0 * (impact.baseCnsScore * 10);
      
      for (final entry in impact.muscleInvolvement.entries) {
        final muscle = entry.key;
        final w = entry.value;
        if (!fatigue.containsKey(muscle)) continue;
        
        final perSet = _perSetBase * (impact.baseCnsScore) * exp(-hours * ln2 / halfLife);
        fatigue[muscle] = (fatigue[muscle]! + perSet * w * equivalentSets).clamp(0.0, 1.0);
        
        // Also add to weekly sets
        if (weeklySets.containsKey(muscle)) {
          weeklySets[muscle] = weeklySets[muscle]! + (w * equivalentSets);
        }
      }
    }

    return [
      for (final g in groups)
        MuscleGroupRecovery(
          muscle: g,
          recoveryScore: ((1 - fatigue[g]!) * 100).round(),
          weeklySets: weeklySets[g]!,
        ),
    ];
  }

  /// Contextual warnings (§2): under-recovered muscles and weekly MRV breaches.
  static List<RecoveryWarning> warnings(List<MuscleGroupRecovery> results) {
    return [
      for (final r in results)
        if (r.recoveryScore < 30)
          RecoveryWarning(
            r.muscle,
            'Your ${r.muscle.toLowerCase()} are likely not recovered from previous sessions.',
          ),
      for (final r in results)
        if (r.weeklySets > (defaultWeeklyMrv[r.muscle] ?? double.infinity))
          RecoveryWarning(
            r.muscle,
            'Volume warning: you\'ve exceeded weekly MRV for ${r.muscle.toLowerCase()} '
            '(${r.weeklySets.toStringAsFixed(0)} sets vs ~${defaultWeeklyMrv[r.muscle]!.toStringAsFixed(0)} recoverable).',
          ),
    ];
  }
}
