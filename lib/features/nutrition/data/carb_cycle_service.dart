import 'dart:convert';

import 'package:herculex/features/analytics/domain/training_snapshot.dart';
import 'package:herculex/features/nutrition/domain/carb_cycling.dart';

/// Builds carb-cycle plans from training data (§19). Bridges the
/// [TrainingSnapshot] (effective-load resolved sets) and the pure
/// [CarbCycling] engine: aggregates each weekday's CNS load and compound
/// density, then generates High/Medium/Low levels.
class CarbCycleService {
  /// Generates a Mon→Sun plan for the calendar week containing [weekStart],
  /// using completed sets from [snapshot] within that week.
  static List<CarbLevel> planForWeek({
    required TrainingSnapshot snapshot,
    required DateTime weekStart,
  }) {
    final monday = _weekStart(weekStart);
    // Per-weekday accumulators.
    final cns = List.filled(7, 0.0);
    final compoundSets = List.filled(7, 0);
    final totalSets = List.filled(7, 0);
    final trained = List.filled(7, false);

    for (final rs in snapshot.sets) {
      final completedAt = rs.set.completedAt;
      if (completedAt == null) continue;
      final dayIdx = DateTime(
        completedAt.year,
        completedAt.month,
        completedAt.day,
      ).difference(monday).inDays;
      if (dayIdx < 0 || dayIdx > 6) continue;

      trained[dayIdx] = true;
      totalSets[dayIdx]++;
      // CNS contribution mirrors CnsTrends' per-set weighting.
      final intensity = rs.cnsScore / 10.0;
      final rpe = rs.set.rpeX10 != null ? rs.set.rpeX10! / 10.0 : 7.0;
      final rpeFactor = rpe >= 9 ? 1.5 : (rpe >= 8 ? 1.3 : 1.0);
      cns[dayIdx] += intensity * rpeFactor * rs.setType.cnsFactor;
      // Heavy compound = high CNS score on a compound-mechanics exercise.
      if (rs.exercise.mechanics == 'compound' && rs.exercise.cnsScore >= 6) {
        compoundSets[dayIdx]++;
      }
    }

    final week = [
      for (var i = 0; i < 7; i++)
        DayTrainingSignal(
          weekdayIndex: i,
          cnsLoad: cns[i],
          compoundDensity: totalSets[i] == 0
              ? 0
              : compoundSets[i] / totalSets[i],
          isTrainingDay: trained[i],
        ),
    ];
    return CarbCycling.generate(week);
  }

  static String encodeLevels(List<CarbLevel> levels) =>
      jsonEncode([for (final l in levels) l.id]);

  static List<CarbLevel> decodeLevels(String json) => [
    for (final id in jsonDecode(json) as List) CarbLevel.fromId(id as String),
  ];

  static DateTime _weekStart(DateTime d) {
    final local = DateTime(d.year, d.month, d.day);
    return local.subtract(Duration(days: local.weekday - DateTime.monday));
  }
}
