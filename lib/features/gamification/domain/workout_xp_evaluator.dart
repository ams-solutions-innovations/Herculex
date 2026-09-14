import 'package:herculex/features/analytics/domain/training_snapshot.dart';
import 'package:herculex/features/gamification/domain/level_progress.dart';

/// Transparent XP rules for a logged workout. These are rewards for training
/// activity only; they do not classify body composition or health.
class WorkoutXpEvaluator {
  const WorkoutXpEvaluator();

  XpAward evaluate({
    required List<ResolvedSet> sessionSets,
    required double? bodyweightKg,
    required List<XpLedgerEntry> previousEntries,
    required DateTime completedAt,
  }) {
    final reasons = <String>['Workout completed +40 XP'];
    var xp = 40;

    final workSetBonus = (sessionSets.length * 2).clamp(0, 20);
    if (workSetBonus > 0) {
      xp += workSetBonus;
      reasons.add('$workSetBonus XP for completed working sets');
    }

    // This is deliberately a modest, capped logged-load signal. It is not a
    // strength standard: equipment, exercise range, and technique differ.
    if (bodyweightKg != null && bodyweightKg > 20 && sessionSets.isNotEmpty) {
      final highestRatio = sessionSets
          .map((set) => set.effectiveKg / bodyweightKg)
          .fold<double>(0, (max, value) => value > max ? value : max);
      final strengthBonus = highestRatio >= 1.5
          ? 15
          : highestRatio >= 1.0
          ? 10
          : 0;
      if (strengthBonus > 0) {
        xp += strengthBonus;
        reasons.add('$strengthBonus XP for a logged relative-load milestone');
      }
    }

    final lastWorkout = previousEntries
        .where((entry) => entry.id.startsWith('workout:'))
        .fold<DateTime?>(
          null,
          (latest, entry) => latest == null || entry.awardedAt.isAfter(latest)
              ? entry.awardedAt
              : latest,
        );
    if (lastWorkout != null) {
      final gap = completedAt.difference(lastWorkout).inHours;
      if (gap >= 20 && gap <= 96) {
        xp += 10;
        reasons.add('10 XP for returning consistently');
      }
    }

    return XpAward(xp: xp, reasons: reasons);
  }
}
