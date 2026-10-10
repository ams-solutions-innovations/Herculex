import 'package:herculex/features/analytics/domain/training_snapshot.dart';
import 'package:herculex/features/analytics/domain/weekly_muscle_volume.dart';
import 'package:herculex/features/friends/domain/friend_snapshot.dart';
import 'package:herculex/features/gamification/domain/lift_best_extractor.dart';
import 'package:herculex/features/gamification/domain/strength_percentiles.dart';
import 'package:herculex/features/gamification/domain/strength_standards.dart';
import 'package:herculex/features/gamification/domain/strength_tier_evaluator.dart';
import 'package:herculex/features/workouts/domain/one_rep_max.dart';

/// Reduces the local training history to the [FriendSnapshot] a user
/// publishes. Pure: every input is passed in, including "now".
class FriendSnapshotBuilder {
  const FriendSnapshotBuilder();

  /// How far back a record still counts as "recent".
  static const recentPrWindow = Duration(days: 14);

  /// A PR must beat the previous best by more than this, so rounding noise
  /// in the e1RM formula is not news.
  static const _prMarginKg = 0.5;

  FriendSnapshot build({
    required TrainingSnapshot training,
    required StrengthAssessment strength,
    required String levelTitle,
    required int completedWorkouts,
    required DateTime asOf,
    double? goalStartKg,
    double? currentBodyweightKg,
    double? goalTargetKg,
  }) {
    final percentiles = {
      for (final p in StrengthPercentiles.evaluate(strength)) p.lift: p,
    };
    final e1rm = _benchmarkE1rm(training);
    final lifts = <FriendLift>[
      for (final MapEntry(key: lift, value: best) in strength.bests.entries)
        if (best.logged case final value?)
          FriendLift(
            lift: lift,
            value: value,
            e1rmKg: e1rm[lift],
            lifterTopPct: percentiles[lift]?.lifterTopPct,
          ),
    ]..sort((a, b) => a.lift.index.compareTo(b.lift.index));

    return FriendSnapshot(
      levelTitle: levelTitle,
      completedWorkouts: completedWorkouts,
      weekTonnageKg: WeeklyMuscleVolume.compute(
        snapshot: training,
        asOf: asOf,
      ).totalTonnageKg,
      lifts: lifts,
      recentPrs: _recentPrs(training, asOf),
      buddySessions: _buddySessions(training, asOf),
      goal:
          goalStartKg != null &&
              currentBodyweightKg != null &&
              goalTargetKg != null
          ? FriendGoal(
              startKg: goalStartKg,
              currentKg: currentBodyweightKg,
              targetKg: goalTargetKg,
            )
          : null,
    );
  }

  /// Best unassisted e1RM in kg per barbell benchmark lift.
  Map<StrengthLift, double> _benchmarkE1rm(TrainingSnapshot training) {
    final out = <StrengthLift, double>{};
    for (final rs in training.sets) {
      final sample = LiftSetSample.fromResolved(rs);
      if (sample == null || sample.assisted) continue;
      if (sample.lift.measure != StrengthMeasure.bodyweightRatio) continue;
      final kg = OneRepMax.estimate(weightKg: sample.loadKg, reps: sample.reps);
      if (kg == null) continue;
      if (kg > (out[sample.lift] ?? 0)) out[sample.lift] = kg;
    }
    return out;
  }

  /// Exercises whose best e1RM inside the window beats everything before it.
  /// A first-ever attempt is not a PR — there was nothing to beat.
  List<FriendPr> _recentPrs(TrainingSnapshot training, DateTime asOf) {
    final windowStart = asOf.subtract(recentPrWindow);
    final before = <int, double>{};
    final inside = <int, (double, DateTime, String)>{};
    for (final rs in training.sets) {
      if (!rs.metric.isRepBased || !rs.metric.isLoaded) continue;
      final at = rs.set.completedAt ?? rs.session.startedAt;
      if (at.isAfter(asOf)) continue;
      final kg = OneRepMax.estimate(
        weightKg: rs.effectiveKg,
        reps: rs.countedReps,
      );
      if (kg == null || kg <= 0) continue;
      final id = rs.exercise.id;
      if (at.isBefore(windowStart)) {
        if (kg > (before[id] ?? 0)) before[id] = kg;
      } else if (kg > (inside[id]?.$1 ?? 0)) {
        inside[id] = (kg, at, rs.exercise.name);
      }
    }
    final prs = <FriendPr>[
      for (final MapEntry(key: id, value: (kg, at, name)) in inside.entries)
        if (before[id] case final prev? when kg > prev + _prMarginKg)
          FriendPr(exercise: name, e1rmKg: kg, at: at),
    ]..sort((a, b) => b.at.compareTo(a.at));
    return prs.take(FriendSnapshot.maxPrs).toList();
  }

  List<FriendBuddySession> _buddySessions(
    TrainingSnapshot training,
    DateTime asOf,
  ) {
    final bySession = <String, _BuddyAccumulator>{};
    for (final rs in training.sets) {
      final id = rs.session.buddySessionId;
      if (id == null || rs.session.startedAt.isAfter(asOf)) continue;
      final acc = bySession.putIfAbsent(
        id,
        () => _BuddyAccumulator(rs.session.startedAt),
      );
      acc.tonnageKg += rs.tonnageKg;
      acc.sets++;
      if (rs.metric.isRepBased &&
          rs.countedReps > 0 &&
          rs.effectiveKg > (acc.topKg ?? 0)) {
        acc
          ..topKg = rs.effectiveKg
          ..topReps = rs.countedReps
          ..topExercise = rs.exercise.name;
      }
    }
    final sessions = [
      for (final MapEntry(key: id, value: a) in bySession.entries)
        FriendBuddySession(
          buddySessionId: id,
          at: a.at,
          tonnageKg: a.tonnageKg,
          sets: a.sets,
          topExercise: a.topExercise,
          topKg: a.topKg,
          topReps: a.topReps,
        ),
    ]..sort((a, b) => b.at.compareTo(a.at));
    return sessions.take(FriendSnapshot.maxBuddySessions).toList();
  }
}

class _BuddyAccumulator {
  _BuddyAccumulator(this.at);

  final DateTime at;
  double tonnageKg = 0;
  int sets = 0;
  String? topExercise;
  double? topKg;
  int? topReps;
}
