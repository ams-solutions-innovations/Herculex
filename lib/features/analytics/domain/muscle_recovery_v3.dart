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

/// One set or external workout's still-live decay term for a muscle: its
/// fatigue contribution *at the snapshot's `asOf`* and the half-life it
/// decays on. `compute()` sums these (then clamps once) to get today's
/// score; `recoveryEtaHours` projects each term forward — `value *
/// exp(-h*ln2/halfLifeHours)` — to find when the sum crosses the recovered
/// threshold. Defining the decay math once here is what keeps the two in
/// sync.
typedef FatigueContribution = ({double value, double halfLifeHours});

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

  /// Score at/above which a muscle counts as recovered — matches
  /// [MuscleGroupRecovery.status]'s RECOVERED cut, so the Recovery page's
  /// "hours until recovered" countdown always agrees with the badge.
  static const recoveredScoreThreshold = 70;

  /// Default weekly MRV (maximum recoverable volume) in hard sets per muscle.
  /// Conservative literature-typical values; user-tunable later.
  static const defaultWeeklyMrv = <String, double>{
    'Chest': 22, 'Back': 25, 'Lats': 22, 'Traps': 20, 'Front Delts': 16,
    'Side Delts': 25, 'Rear Delts': 25, 'Biceps': 20, 'Triceps': 18,
    'Forearms': 20, 'Abs': 25, 'Obliques': 20, 'Neck': 15, 'Quads': 20,
    'Hamstrings': 16, 'Glutes': 16, 'Calves': 20, 'Adductors': 16,
    'Abductors': 16,
  };

  /// Default search horizon for [recoveryEtaHours] — see that method's doc
  /// comment for the derivation. Exposed so callers can detect "still
  /// elevated past the horizon" without duplicating the literal.
  static const maxEtaHorizonHours = 240.0;

  /// Resolves an exercise's per-muscle involvement, falling back to the
  /// coarse `primaryMuscle` tag when no granular [ExerciseMuscleData] rows
  /// exist. Shared by every engine that needs "which muscles, how much" for
  /// one [ResolvedSet].
  static List<(String, double)> involvementFor(
    ResolvedSet rs,
    Map<int, List<ExerciseMuscleData>> musclesByExercise,
  ) {
    final rows = musclesByExercise[rs.exercise.id] ?? const [];
    return rows.isNotEmpty
        ? [
            for (final r in rows)
              (
                alias[r.muscle] ?? r.muscle,
                (roleWeight[r.role] ?? 0) *
                    r.contribution *
                    (r.muscle == 'Hip Flexors' ? 0.25 : 1.0),
              )
          ]
        : [
            (
              alias[rs.exercise.primaryMuscle] ?? rs.exercise.primaryMuscle,
              rs.exercise.primaryMuscle == 'Hip Flexors' ? 0.25 : 1.0,
            )
          ];
  }

  /// Per-muscle list of still-live fatigue terms at [asOf] — the shared
  /// internals behind both [compute] (sums and clamps once per muscle) and
  /// [recoveryEtaHours] (projects each term forward). Two accumulation
  /// passes: gym sets within [_windowHours] of [asOf], then external
  /// HealthKit/Health Connect workouts on the same window.
  static Map<String, List<FatigueContribution>> _computeContributions({
    required TrainingSnapshot snapshot,
    required List<HealthDataPoint> externalWorkouts,
    required DateTime asOf,
    int daysOfHealthHistory = 0,
  }) {
    final contributions = {for (final g in groups) g: <FatigueContribution>[]};

    final musclesByExercise = <int, List<ExerciseMuscleData>>{};
    for (final m in snapshot.exerciseMuscles) {
      musclesByExercise.putIfAbsent(m.exerciseId, () => []).add(m);
    }

    for (final rs in snapshot.sets) {
      final completedAt = rs.set.completedAt;
      if (completedAt == null) continue;
      final hours = asOf.difference(completedAt).inHours;
      if (hours < 0 || hours > _windowHours) continue;

      final involvement = involvementFor(rs, musclesByExercise);

      // Only apply fatigue multiplier if RPE was explicitly logged by the user
      final rpe = rs.set.rpeX10 != null ? rs.set.rpeX10! / 10.0 : null;
      final rpeFactor = rpe != null
          ? (rpe >= 9 ? 1.6 : (rpe >= 8 ? 1.3 : 1.0))
          : 1.0;

      // Higher systemic recovery cost decays more slowly.
      final halfLife = 18.0 + 6.0 * rs.exercise.recoveryImpact; // 24–48h
      final perSet = _perSetBase *
          (rs.exercise.recoveryImpact / 3.0) *
          rpeFactor *
          rs.setType.cnsFactor *
          exp(-hours * ln2 / halfLife);

      for (final (muscle, w) in involvement) {
        if (!contributions.containsKey(muscle)) continue;
        // Fat grips & thick-bar work hammer the forearms harder (§8).
        final mult = muscle == 'Forearms' ? rs.forearmMultiplier : 1.0;
        contributions[muscle]!.add((value: perSet * w * mult, halfLifeHours: halfLife));
      }
    }

    for (final workout in externalWorkouts) {
      if (workout.value is! WorkoutHealthValue) continue;
      final wv = workout.value as WorkoutHealthValue;

      final hours = asOf.difference(workout.dateTo).inHours;
      if (hours < 0 || hours > _windowHours) continue;

      // Require at least 30 days of health data before counting ordinary walking
      // as muscle fatigue, allowing a user baseline to establish first.
      if (wv.workoutActivityType == HealthWorkoutActivityType.WALKING &&
          daysOfHealthHistory < 30) {
        continue;
      }

      final impact = ExternalWorkoutCnsMapper.getImpactFor(wv.workoutActivityType);
      final durationMinutes = workout.dateTo.difference(workout.dateFrom).inMinutes;

      final isWalking = wv.workoutActivityType == HealthWorkoutActivityType.WALKING;
      final equivalentSets = (durationMinutes / 60.0) * (isWalking ? 3.0 : 6.0);

      final halfLife = 18.0 + 6.0 * (impact.baseCnsScore * 10);

      for (final entry in impact.muscleInvolvement.entries) {
        final muscle = entry.key;
        final w = entry.value;
        if (!contributions.containsKey(muscle)) continue;

        final perSet = _perSetBase * (impact.baseCnsScore) * exp(-hours * ln2 / halfLife);
        contributions[muscle]!.add((value: perSet * w * equivalentSets, halfLifeHours: halfLife));
      }
    }

    return contributions;
  }

  /// Weekly (trailing 7-day) set counts per muscle, fractional credit by role
  /// weight — independent of the 96h fatigue-decay window above, used only
  /// for MRV comparisons. Kept as its own pass since it has its own window
  /// and doesn't feed the decay math.
  static Map<String, double> _computeWeeklySets({
    required TrainingSnapshot snapshot,
    required List<HealthDataPoint> externalWorkouts,
    required DateTime asOf,
    int daysOfHealthHistory = 0,
  }) {
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

      final involvement = involvementFor(rs, musclesByExercise);
      for (final (muscle, w) in involvement) {
        if (weeklySets.containsKey(muscle)) {
          weeklySets[muscle] = weeklySets[muscle]! + (w >= 1.0 ? 1.0 : w);
        }
      }
    }

    for (final workout in externalWorkouts) {
      if (workout.value is! WorkoutHealthValue) continue;
      final wv = workout.value as WorkoutHealthValue;

      final hours = asOf.difference(workout.dateTo).inHours;
      if (hours < 0 || hours > _windowHours) continue;

      if (wv.workoutActivityType == HealthWorkoutActivityType.WALKING &&
          daysOfHealthHistory < 30) {
        continue;
      }

      final impact = ExternalWorkoutCnsMapper.getImpactFor(wv.workoutActivityType);
      final durationMinutes = workout.dateTo.difference(workout.dateFrom).inMinutes;
      final isWalking = wv.workoutActivityType == HealthWorkoutActivityType.WALKING;
      final equivalentSets = (durationMinutes / 60.0) * (isWalking ? 3.0 : 6.0);

      for (final entry in impact.muscleInvolvement.entries) {
        if (weeklySets.containsKey(entry.key)) {
          weeklySets[entry.key] = weeklySets[entry.key]! + (entry.value * equivalentSets);
        }
      }
    }

    return weeklySets;
  }

  static double _fatigueSum(List<FatigueContribution> contributions) =>
      contributions.fold(0.0, (s, c) => s + c.value).clamp(0.0, 1.0);

  static List<MuscleGroupRecovery> compute({
    required TrainingSnapshot snapshot,
    List<HealthDataPoint> externalWorkouts = const [],
    required DateTime asOf,
    int daysOfHealthHistory = 0,
  }) {
    final contributions = _computeContributions(
      snapshot: snapshot,
      externalWorkouts: externalWorkouts,
      asOf: asOf,
      daysOfHealthHistory: daysOfHealthHistory,
    );
    final weeklySets = _computeWeeklySets(
      snapshot: snapshot,
      externalWorkouts: externalWorkouts,
      asOf: asOf,
      daysOfHealthHistory: daysOfHealthHistory,
    );

    final results = [
      for (final g in groups)
        MuscleGroupRecovery(
          muscle: g,
          recoveryScore: ((1 - _fatigueSum(contributions[g]!)) * 100).round(),
          weeklySets: weeklySets[g]!,
        ),
    ];
    results.sort((a, b) {
      final scoreCmp = a.recoveryScore.compareTo(b.recoveryScore);
      if (scoreCmp != 0) return scoreCmp;
      return groups.indexOf(a.muscle).compareTo(groups.indexOf(b.muscle));
    });
    return results;
  }

  /// Hours until each muscle's fatigue decays to [recoveredScoreThreshold]
  /// (default 70 — "RECOVERED"). Null means already there at [asOf].
  ///
  /// Each contribution decays independently — `value * exp(-h*ln2/halfLife)`
  /// — so the total is a sum of non-increasing terms and therefore itself
  /// non-increasing in `h`, which is what makes a binary search for the
  /// crossing point valid. [maxHorizonHours] (default 240h/10 days) bounds
  /// the search: the slowest half-life the model produces is ~72h (heaviest
  /// external-workout impact), and decaying from full fatigue to the
  /// threshold at that half-life takes ~125h, so 240h leaves comfortable
  /// margin for a pathological stacked-fatigue case. Muscles still above the
  /// threshold at the horizon report exactly [maxHorizonHours] — render that
  /// as e.g. "10d+" rather than false precision.
  static Map<String, double?> recoveryEtaHours({
    required TrainingSnapshot snapshot,
    List<HealthDataPoint> externalWorkouts = const [],
    required DateTime asOf,
    double maxHorizonHours = maxEtaHorizonHours,
    int daysOfHealthHistory = 0,
  }) {
    final contributions = _computeContributions(
      snapshot: snapshot,
      externalWorkouts: externalWorkouts,
      asOf: asOf,
      daysOfHealthHistory: daysOfHealthHistory,
    );
    final targetMaxFatigue = 1.0 - recoveredScoreThreshold / 100.0;

    return {
      for (final g in groups)
        g: _etaFor(contributions[g]!, targetMaxFatigue, maxHorizonHours),
    };
  }

  static double? _etaFor(
    List<FatigueContribution> contributions,
    double targetMaxFatigue,
    double maxHorizonHours,
  ) {
    if (contributions.isEmpty) return null;

    double fatigueAt(double h) => contributions
        .fold(0.0, (s, c) => s + c.value * exp(-h * ln2 / c.halfLifeHours))
        .clamp(0.0, 1.0);

    if (fatigueAt(0) <= targetMaxFatigue) return null;
    if (fatigueAt(maxHorizonHours) > targetMaxFatigue) return maxHorizonHours;

    var lo = 0.0;
    var hi = maxHorizonHours;
    for (var i = 0; i < 30; i++) {
      final mid = (lo + hi) / 2;
      if (fatigueAt(mid) > targetMaxFatigue) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return hi;
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
