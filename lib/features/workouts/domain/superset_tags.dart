import 'package:herculex/data/local/database.dart';

/// Letter-and-position tags for linked exercises, as a programme sheet prints
/// them: the session's first superset is A (A1, A2), the next one B, and so
/// on. Exercises outside a superset get no entry.
///
/// [exercises] must be in session order — the tags follow it.
Map<int, String> supersetTags(List<WorkoutExerciseData> exercises) {
  final letters = <int, String>{};
  final positions = <int, int>{};
  final tags = <int, String>{};
  for (final we in exercises) {
    final group = we.supersetGroup;
    if (group == null) continue;
    final letter = letters.putIfAbsent(
      group,
      () => String.fromCharCode(0x41 + letters.length % 26),
    );
    final position = (positions[group] ?? 0) + 1;
    positions[group] = position;
    tags[we.id] = '$letter$position';
  }
  return tags;
}
