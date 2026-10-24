import 'package:herculex/features/analytics/domain/cns_trends.dart';
import 'package:herculex/features/analytics/domain/muscle_recovery_v3.dart';
import 'package:herculex/features/analytics/domain/training_snapshot.dart';

/// The three numbers Insights leads with: how much you trained this week,
/// how that compares with last week, and how recovered you are.
class InsightsWeekSummary {
  const InsightsWeekSummary({
    required this.sessions,
    required this.tonnageKg,
    required this.lastWeekTonnageKg,
    required this.readiness,
    required this.leastRecoveredMuscle,
    required this.leastRecoveredScore,
    required this.advice,
  });

  final int sessions;
  final double tonnageKg;
  final double lastWeekTonnageKg;

  /// 0..1, from the CNS gauge.
  final double readiness;
  final String? leastRecoveredMuscle;
  final int? leastRecoveredScore;

  /// One plain sentence, always present.
  final String advice;

  /// Signed change vs last week, or null with nothing to compare against.
  double? get tonnageChange =>
      lastWeekTonnageKg <= 0 ? null : tonnageKg / lastWeekTonnageKg - 1;

  static InsightsWeekSummary compute({
    required TrainingSnapshot snapshot,
    required CnsTrendsResult cns,
    required List<MuscleGroupRecovery> recovery,
    required DateTime now,
  }) {
    final today = DateTime(now.year, now.month, now.day);
    final weekStart = today.subtract(Duration(days: today.weekday - 1));
    final lastWeekStart = weekStart.subtract(const Duration(days: 7));

    final sessionIds = <int>{};
    var tonnage = 0.0;
    var lastTonnage = 0.0;
    for (final set in snapshot.sets) {
      final started = set.session.startedAt;
      if (!started.isBefore(weekStart)) {
        sessionIds.add(set.session.id);
        tonnage += set.tonnageKg;
      } else if (!started.isBefore(lastWeekStart)) {
        lastTonnage += set.tonnageKg;
      }
    }

    final trained = recovery.where((r) => r.weeklySets > 0).toList()
      ..sort((a, b) => a.recoveryScore.compareTo(b.recoveryScore));
    final weakest = trained.firstOrNull;

    final advice =
        cns.recommendation ??
        (weakest != null && weakest.recoveryScore < 50
            ? '${weakest.muscle} is still recovering — train other muscle groups today.'
            : sessionIds.isEmpty
            ? 'No training logged this week yet. Log your next workout to start tracking your progress.'
            : 'You are recovering well. Keep following your plan.');

    return InsightsWeekSummary(
      sessions: sessionIds.length,
      tonnageKg: tonnage,
      lastWeekTonnageKg: lastTonnage,
      readiness: cns.readiness,
      leastRecoveredMuscle: weakest?.muscle,
      leastRecoveredScore: weakest?.recoveryScore,
      advice: advice,
    );
  }
}
