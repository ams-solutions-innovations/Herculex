import 'package:health/health.dart';

import '../../analytics/domain/cns_trends.dart';
import '../../analytics/domain/muscle_recovery_v3.dart';
import '../../analytics/domain/muscle_volume_trend.dart';
import '../../analytics/domain/training_snapshot.dart';
import 'deload_urgency.dart';

/// One muscle's reactive (not prescriptive — see `ProgramWeek.isDeload` for
/// planned periodization deloads) deload signal, scored from three
/// corroborating pieces of evidence.
class MuscleDeloadSignal {
  final String muscle;
  final DeloadUrgency urgency;

  /// Weekly sets exceeded [MuscleRecoveryV3.defaultWeeklyMrv] in at least 3
  /// of the trailing 4 weeks.
  final bool chronicMrvBreach;

  /// Recovery score sat below 30 on at least 8 of the trailing 14 days.
  final bool sustainedLowRecovery;

  /// Whether today's whole-body [CnsTrendsResult.deloadSuggested] agrees.
  final bool corroboratedByCns;

  const MuscleDeloadSignal({
    required this.muscle,
    required this.urgency,
    required this.chronicMrvBreach,
    required this.sustainedLowRecovery,
    required this.corroboratedByCns,
  });
}

/// Per-muscle deload advisor: [CnsTrends.deloadSuggested] is whole-body only,
/// so this looks for the same "training beyond what's recoverable" pattern
/// one muscle at a time — chronic volume above MRV, or recovery that never
/// climbs back out of the fatigued band — and uses the whole-body CNS signal
/// only as corroboration, not as the primary trigger.
abstract final class MuscleDeloadAdvisor {
  static const _mrvBreachWeeksLookback = 4;
  static const _mrvBreachWeeksRequired = 3;
  static const _lowRecoveryDaysLookback = 14;
  static const _lowRecoveryDaysRequired = 8;
  static const _lowRecoveryScoreCeiling = 30;

  static List<MuscleDeloadSignal> compute({
    required TrainingSnapshot snapshot,
    required List<HealthDataPoint> externalWorkouts,
    required DateTime asOf,
    required CnsTrendsResult cnsTrends,
  }) {
    final trends = MuscleVolumeTrends.compute(
      snapshot: snapshot,
      asOf: asOf,
      weekCount: 8,
    );

    // Recovery score history isn't persisted anywhere — MuscleRecoveryV3 is a
    // cheap pure function over the already-loaded snapshot, so "the last 14
    // days" is just 14 replays of it at different `asOf` values, once (not
    // once per muscle).
    final dailyRecovery = [
      for (var i = 0; i < _lowRecoveryDaysLookback; i++)
        MuscleRecoveryV3.compute(
          snapshot: snapshot,
          externalWorkouts: externalWorkouts,
          asOf: asOf.subtract(Duration(days: i)),
        ),
    ];

    return [
      for (final muscle in MuscleRecoveryV3.groups)
        _signalFor(muscle, trends[muscle]!, dailyRecovery, cnsTrends),
    ];
  }

  static MuscleDeloadSignal _signalFor(
    String muscle,
    MuscleVolumeTrend trend,
    List<List<MuscleGroupRecovery>> dailyRecovery,
    CnsTrendsResult cnsTrends,
  ) {
    final mrv = MuscleRecoveryV3.defaultWeeklyMrv[muscle] ?? double.infinity;
    final lastWeeks = trend.weeks.length >= _mrvBreachWeeksLookback
        ? trend.weeks.sublist(trend.weeks.length - _mrvBreachWeeksLookback)
        : trend.weeks;
    final chronicMrvBreach =
        lastWeeks.where((w) => w.sets > mrv).length >= _mrvBreachWeeksRequired;

    final lowDays = dailyRecovery.where((day) {
      final score = day.firstWhere((r) => r.muscle == muscle).recoveryScore;
      return score < _lowRecoveryScoreCeiling;
    }).length;
    final sustainedLowRecovery = lowDays >= _lowRecoveryDaysRequired;

    var score = 0;
    if (chronicMrvBreach) score += 2;
    if (sustainedLowRecovery) score += 2;
    if (cnsTrends.deloadSuggested) score += 1;

    final urgency = score >= 4
        ? DeloadUrgency.recommended
        : score >= 2
        ? DeloadUrgency.watch
        : DeloadUrgency.none;

    return MuscleDeloadSignal(
      muscle: muscle,
      urgency: urgency,
      chronicMrvBreach: chronicMrvBreach,
      sustainedLowRecovery: sustainedLowRecovery,
      corroboratedByCns: cnsTrends.deloadSuggested,
    );
  }
}
