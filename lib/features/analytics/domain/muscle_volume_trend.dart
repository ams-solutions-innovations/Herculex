import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/analytics/domain/muscle_recovery_v3.dart';
import 'package:herculex/features/analytics/domain/training_snapshot.dart';
import 'package:herculex/features/analytics/domain/weekly_muscle_volume.dart'
    show WeeklyMuscleVolume;

/// One week's role-weighted working-set count for a muscle. Same fractional
/// credit convention as [WeeklyMuscleVolume] — a secondary-role set counts
/// for less than a full set.
class WeeklyMuscleSets {
  final DateTime weekStart; // Monday 00:00
  final double sets;
  const WeeklyMuscleSets({required this.weekStart, required this.sets});
}

/// One muscle's trailing weekly-volume history — the "last month or two"
/// view the deload and joint-stress advisors are built on, which
/// [WeeklyMuscleVolume] (current week only) doesn't cover.
class MuscleVolumeTrend {
  final String muscle;

  /// Oldest→newest, always exactly [MuscleVolumeTrends.compute]'s
  /// `weekCount` entries, zero-filled for weeks with no training.
  final List<WeeklyMuscleSets> weeks;

  final double averageWeeklySets;

  /// OLS slope of sets against week index — positive means ramping,
  /// negative means tapering. Null only when fewer than 2 weeks were
  /// requested (a slope needs at least two points).
  final double? trendSlopePerWeek;

  const MuscleVolumeTrend({
    required this.muscle,
    required this.weeks,
    required this.averageWeeklySets,
    required this.trendSlopePerWeek,
  });
}

/// Generalizes [WeeklyMuscleVolume] into a trailing multi-week series per
/// muscle, reusing [MuscleRecoveryV3.groups]/[MuscleRecoveryV3.involvementFor]
/// so the breakdown agrees with the recovery and weekly-volume cards.
abstract final class MuscleVolumeTrends {
  static Map<String, MuscleVolumeTrend> compute({
    required TrainingSnapshot snapshot,
    required DateTime asOf,
    int weekCount = 8,
  }) {
    final currentWeekStart = WeeklyMuscleVolume.weekStartOf(asOf);
    final weekStarts = [
      for (var i = weekCount - 1; i >= 0; i--)
        currentWeekStart.subtract(Duration(days: 7 * i)),
    ];
    final firstWeekStart = weekStarts.first;

    final musclesByExercise = <int, List<ExerciseMuscleData>>{};
    for (final m in snapshot.exerciseMuscles) {
      musclesByExercise.putIfAbsent(m.exerciseId, () => []).add(m);
    }

    final setsByMuscle = {
      for (final g in MuscleRecoveryV3.groups)
        g: List<double>.filled(weekCount, 0.0),
    };

    for (final rs in snapshot.sets) {
      final completedAt = rs.set.completedAt ?? rs.session.startedAt;
      if (completedAt.isBefore(firstWeekStart) || completedAt.isAfter(asOf)) {
        continue;
      }

      final weekIndex = completedAt.difference(firstWeekStart).inDays ~/ 7;
      if (weekIndex < 0 || weekIndex >= weekCount) continue;

      final involvement = MuscleRecoveryV3.involvementFor(
        rs,
        musclesByExercise,
      );
      for (final (muscle, w) in involvement) {
        final bucket = setsByMuscle[muscle];
        if (bucket == null) continue;
        bucket[weekIndex] += (w >= 1.0 ? 1.0 : w);
      }
    }

    return {
      for (final g in MuscleRecoveryV3.groups)
        g: _trendFor(g, weekStarts, setsByMuscle[g]!),
    };
  }

  static MuscleVolumeTrend _trendFor(
    String muscle,
    List<DateTime> weekStarts,
    List<double> setCounts,
  ) {
    final weeks = [
      for (var i = 0; i < weekStarts.length; i++)
        WeeklyMuscleSets(weekStart: weekStarts[i], sets: setCounts[i]),
    ];
    final average = setCounts.isEmpty
        ? 0.0
        : setCounts.reduce((a, b) => a + b) / setCounts.length;

    return MuscleVolumeTrend(
      muscle: muscle,
      weeks: weeks,
      averageWeeklySets: average,
      trendSlopePerWeek: _olsSlope(setCounts),
    );
  }

  /// Ordinary-least-squares slope of [y] against its index (0..n-1).
  static double? _olsSlope(List<double> y) {
    final n = y.length;
    if (n < 2) return null;

    var sumX = 0.0, sumY = 0.0, sumXY = 0.0, sumXX = 0.0;
    for (var i = 0; i < n; i++) {
      sumX += i;
      sumY += y[i];
      sumXY += i * y[i];
      sumXX += i * i;
    }
    final denominator = n * sumXX - sumX * sumX;
    if (denominator == 0) return null;
    return (n * sumXY - sumX * sumY) / denominator;
  }
}
