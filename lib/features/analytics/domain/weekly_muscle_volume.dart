import '../../../data/local/database.dart';
import 'muscle_recovery_v3.dart';
import 'training_snapshot.dart';

/// Tonnage and hard-set count credited to a single muscle group over the
/// current training week.
class MuscleVolume {
  final String muscle;

  /// Tonnage in kg, credited fractionally by muscle role.
  final double tonnageKg;

  /// Working sets, credited fractionally by muscle role.
  final double sets;

  const MuscleVolume({
    required this.muscle,
    required this.tonnageKg,
    required this.sets,
  });
}

/// Total weekly training volume with a per-muscle-group breakdown, backing the
/// "Total Volume This Week" dashboard widget.
class WeeklyMuscleVolume {
  /// Monday 00:00 of the week this covers.
  final DateTime weekStart;

  /// Session tonnage summed once per set (not per muscle), so it matches the
  /// headline number rather than the sum of [byMuscle].
  final double totalTonnageKg;

  final int totalSets;

  /// Non-zero groups, heaviest first.
  final List<MuscleVolume> byMuscle;

  const WeeklyMuscleVolume({
    required this.weekStart,
    required this.totalTonnageKg,
    required this.totalSets,
    required this.byMuscle,
  });

  static WeeklyMuscleVolume empty(DateTime weekStart) => WeeklyMuscleVolume(
        weekStart: weekStart,
        totalTonnageKg: 0,
        totalSets: 0,
        byMuscle: const [],
      );

  /// Monday 00:00 of the week containing [d].
  static DateTime weekStartOf(DateTime d) {
    final monday = d.subtract(Duration(days: d.weekday - 1));
    return DateTime(monday.year, monday.month, monday.day);
  }

  /// Aggregates every completed working set since Monday. Muscle attribution
  /// reuses the recovery engine's role weights and aliases so the breakdown
  /// agrees with the recovery card.
  static WeeklyMuscleVolume compute({
    required TrainingSnapshot snapshot,
    required DateTime asOf,
  }) {
    final start = weekStartOf(asOf);

    final musclesByExercise = <int, List<ExerciseMuscleData>>{};
    for (final m in snapshot.exerciseMuscles) {
      musclesByExercise.putIfAbsent(m.exerciseId, () => []).add(m);
    }

    final tonnage = {for (final g in MuscleRecoveryV3.groups) g: 0.0};
    final sets = {for (final g in MuscleRecoveryV3.groups) g: 0.0};
    var totalTonnage = 0.0;
    var totalSets = 0;

    for (final rs in snapshot.sets) {
      final completedAt = rs.set.completedAt ?? rs.session.startedAt;
      if (completedAt.isBefore(start) || completedAt.isAfter(asOf)) continue;

      totalTonnage += rs.tonnageKg;
      totalSets++;

      final rows = musclesByExercise[rs.exercise.id] ?? const [];
      final involvement = rows.isNotEmpty
          ? [
              for (final r in rows)
                (
                  MuscleRecoveryV3.alias[r.muscle] ?? r.muscle,
                  (MuscleRecoveryV3.roleWeight[r.role] ?? 0) * r.contribution,
                )
            ]
          : [
              (
                MuscleRecoveryV3.alias[rs.exercise.primaryMuscle] ??
                    rs.exercise.primaryMuscle,
                1.0
              )
            ];

      for (final (muscle, w) in involvement) {
        if (!tonnage.containsKey(muscle)) continue;
        tonnage[muscle] = tonnage[muscle]! + rs.tonnageKg * w;
        sets[muscle] = sets[muscle]! + (w >= 1.0 ? 1.0 : w);
      }
    }

    final byMuscle = <MuscleVolume>[
      for (final g in MuscleRecoveryV3.groups)
        if (tonnage[g]! > 0 || sets[g]! > 0)
          MuscleVolume(muscle: g, tonnageKg: tonnage[g]!, sets: sets[g]!),
    ]..sort((a, b) => b.tonnageKg.compareTo(a.tonnageKg));

    return WeeklyMuscleVolume(
      weekStart: start,
      totalTonnageKg: totalTonnage,
      totalSets: totalSets,
      byMuscle: byMuscle,
    );
  }
}
