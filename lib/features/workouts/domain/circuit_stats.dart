import 'package:herculex/data/local/database.dart';

class CircuitPerformanceStats {
  final int totalPlannedRounds;
  final int completedRounds;
  final int? averageRestBetweenRoundsSeconds;
  final bool isEntireCircuitCompleted;

  const CircuitPerformanceStats({
    required this.totalPlannedRounds,
    required this.completedRounds,
    this.averageRestBetweenRoundsSeconds,
    this.isEntireCircuitCompleted = false,
  });

  String get formattedAvgRest {
    if (averageRestBetweenRoundsSeconds == null ||
        averageRestBetweenRoundsSeconds! <= 0) {
      return '—';
    }
    final m = averageRestBetweenRoundsSeconds! ~/ 60;
    final s = averageRestBetweenRoundsSeconds! % 60;
    if (m > 0) {
      return s > 0 ? '${m}m ${s}s' : '${m}m';
    }
    return '${s}s';
  }

  static const empty = CircuitPerformanceStats(
    totalPlannedRounds: 0,
    completedRounds: 0,
  );
}

/// Calculates the performance statistics for a circuit / giant superset group.
///
/// [exercises]: The list of [WorkoutExerciseData] sharing the circuit's [supersetGroup].
/// [setsByExerciseId]: Map of exercise id to its [SetEntryData] rows.
CircuitPerformanceStats calculateCircuitStats({
  required List<WorkoutExerciseData> exercises,
  required Map<int, List<SetEntryData>> setsByExerciseId,
}) {
  if (exercises.isEmpty) return CircuitPerformanceStats.empty;

  // Total planned rounds is the maximum number of sets across exercises
  int maxSets = 0;
  for (final ex in exercises) {
    final sets = setsByExerciseId[ex.id] ?? [];
    if (sets.length > maxSets) {
      maxSets = sets.length;
    }
  }

  if (maxSets == 0) return CircuitPerformanceStats.empty;

  int completedRounds = 0;
  final List<DateTime> roundStartTimestamps = [];
  final List<DateTime> roundEndTimestamps = [];

  for (int roundIdx = 1; roundIdx <= maxSets; roundIdx++) {
    bool roundCompleted = true;
    DateTime? firstCompletedInRound;
    DateTime? lastCompletedInRound;

    for (final ex in exercises) {
      final sets = setsByExerciseId[ex.id] ?? [];
      final set = sets.length >= roundIdx ? sets[roundIdx - 1] : null;
      if (set == null || !set.isCompleted) {
        roundCompleted = false;
        break;
      }
      if (set.completedAt != null) {
        if (firstCompletedInRound == null ||
            set.completedAt!.isBefore(firstCompletedInRound)) {
          firstCompletedInRound = set.completedAt;
        }
        if (lastCompletedInRound == null ||
            set.completedAt!.isAfter(lastCompletedInRound)) {
          lastCompletedInRound = set.completedAt;
        }
      }
    }

    if (roundCompleted) {
      completedRounds++;
      if (firstCompletedInRound != null && lastCompletedInRound != null) {
        roundStartTimestamps.add(firstCompletedInRound);
        roundEndTimestamps.add(lastCompletedInRound);
      }
    } else {
      // Circuits progress sequentially round by round; if round r is not complete, subsequent rounds aren't counted
      break;
    }
  }

  // Calculate average rest duration between completed rounds
  int? avgRestSeconds;
  if (roundStartTimestamps.length >= 2 && roundEndTimestamps.length >= 2) {
    int totalRestSec = 0;
    int intervals = 0;
    for (int i = 1; i < roundStartTimestamps.length; i++) {
      final diff = roundStartTimestamps[i]
          .difference(roundEndTimestamps[i - 1])
          .inSeconds;
      if (diff > 0 && diff < 1800) {
        // Sanity check: rest between rounds under 30 minutes
        totalRestSec += diff;
        intervals++;
      }
    }
    if (intervals > 0) {
      avgRestSeconds = (totalRestSec / intervals).round();
    }
  }

  return CircuitPerformanceStats(
    totalPlannedRounds: maxSets,
    completedRounds: completedRounds,
    averageRestBetweenRoundsSeconds: avgRestSeconds,
    isEntireCircuitCompleted: completedRounds >= maxSets && maxSets > 0,
  );
}
