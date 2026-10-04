import 'package:herculex/features/workouts/domain/set_type.dart';
import 'package:herculex/features/workouts/domain/warmup_resolver.dart';

/// Projects realistic session length by itemizing every component that
/// contributes to time-under-tension for a session, rather than applying a
/// flat overhead buffer (Phase 18 D-05/D-06).
abstract final class WorkoutDurationEstimator {
  static const double _secondsPerRep = 3.5;

  /// Itemizes: (a) working-set time (reps + rest, unilateral work doubling
  /// the rep-performance component only), (b) warmup time from
  /// [warmupSteps], and (c) rest-pause/myo-reps mini-set burst time for set
  /// types that declare `miniSets` in their `metaKeys`.
  static Duration estimateExercise({
    required int workingSets,
    required int repsMin,
    required int repsMax,
    required int restSeconds,
    required SetType setType,
    List<WarmupStep> warmupSteps = const [],
    bool isUnilateral = false,
  }) {
    final avgReps = (repsMin + repsMax) / 2;

    // (a) working-set time.
    final repPerformanceSeconds =
        avgReps * _secondsPerRep * (isUnilateral ? 2 : 1);
    final workingSetSeconds =
        workingSets * (repPerformanceSeconds + restSeconds);

    // (b) warmup time — each step's reps plus a 30s inter-step rest.
    final warmupSeconds = warmupSteps.fold<double>(
      0,
      (sum, step) => sum + step.reps * _secondsPerRep + 30,
    );

    // (c) mini-set burst time for rest-pause/myo-reps style techniques.
    final miniSetSeconds = setType.metaKeys.contains('miniSets')
        ? 2 * (avgReps * 0.4 * _secondsPerRep + 15)
        : 0;

    final totalSeconds = workingSetSeconds + warmupSeconds + miniSetSeconds;
    return Duration(seconds: totalSeconds.round());
  }

  /// Returns [capSeconds] verbatim as a [Duration] for fixed/capped-duration
  /// metcon segments (AMRAP, EMOM, For Time), bypassing the per-rep formula
  /// entirely — that formula is meaningless for "as many rounds as possible
  /// in 10 minutes."
  ///
  /// This is a conservative *upper bound*, not a predicted actual completion
  /// time (RESEARCH.md Pitfall 3): an advanced athlete who finishes a For
  /// Time segment well under the cap will still show as taking the full cap
  /// in this estimate. That is the safe direction to be wrong in for a
  /// time-budget check — it never under-promises how long a session might
  /// take.
  static Duration estimateCappedSegment({required int capSeconds}) =>
      Duration(seconds: capSeconds);

  /// Sums per-exercise durations plus one inter-exercise transition per
  /// exercise.
  static Duration estimateSession(
    Iterable<Duration> exerciseDurations, {
    int transitionSecondsPerExercise = 90,
  }) {
    final total = exerciseDurations.fold(Duration.zero, (sum, d) => sum + d);
    return total +
        Duration(
          seconds: exerciseDurations.length * transitionSecondsPerExercise,
        );
  }
}
