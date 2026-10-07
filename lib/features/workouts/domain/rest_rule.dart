import 'package:herculex/data/local/database.dart';

/// The rest period a completed set earns.
class RestPlan {
  final int seconds;
  final String label;

  const RestPlan({required this.seconds, required this.label});
}

/// Fallback when neither the session row nor the catalog names a rest.
const kDefaultRestSeconds = 90;

/// Decides the rest after a set of [completed] is finished — the one rule
/// every completion path (exercise card, full-screen mode, notification,
/// bubble, watch) shares.
///
/// Inside a superset / tri-set / giant set only the last member of the group
/// rests; finishing an earlier member flows straight into the next exercise,
/// so it returns `null`.
RestPlan? restAfterCompletedSet({
  required WorkoutExerciseData completed,
  required List<WorkoutExerciseData> sessionExercises,
  required String exerciseName,
  int? catalogDefaultRestSeconds,
  required int round,
}) {
  final seconds =
      completed.targetRestSeconds ??
      catalogDefaultRestSeconds ??
      kDefaultRestSeconds;
  if (seconds <= 0) return null;

  final group = completed.supersetGroup;
  if (group == null) {
    return RestPlan(seconds: seconds, label: exerciseName);
  }
  final members =
      sessionExercises.where((e) => e.supersetGroup == group).toList()
        ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
  if (members.length <= 1) {
    return RestPlan(seconds: seconds, label: exerciseName);
  }
  if (members.last.id != completed.id) return null;

  final groupLabel = switch (members.length) {
    2 => 'Superset',
    3 => 'Tri-Set',
    _ => 'Giant Set',
  };
  return RestPlan(seconds: seconds, label: '$groupLabel Rest (Round $round)');
}
