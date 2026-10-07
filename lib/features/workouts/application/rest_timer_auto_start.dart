import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:herculex/app/providers.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/workouts/application/rest_timer_controller.dart';
import 'package:herculex/features/workouts/application/workouts_providers.dart';
import 'package:herculex/features/workouts/domain/rest_rule.dart';

/// Starts the rest timer whenever a set of the active workout becomes
/// completed — no matter where it was completed: the exercise card, the
/// full-screen mode, the ongoing notification, the Workout Bubble or the
/// watch.
///
/// Each of those used to start (or forget to start) the timer on its own, so
/// a set ticked off anywhere but the exercise card never rested. Watching the
/// database instead makes the rest a consequence of the set being done.
///
/// Watched once from the app root, next to the wear-sync controllers.
final restTimerAutoStartProvider = Provider<void>((ref) {
  final session = ref.watch(activeSessionProvider).valueOrNull;
  if (session == null) return;
  final exercises = ref.watch(sessionExercisesProvider(session.id)).valueOrNull;
  if (exercises == null) return;

  final seen = ref.watch(_completionLedgerProvider(session.id));
  for (final workoutExercise in exercises) {
    ref.listen<AsyncValue<List<SetEntryData>>>(
      setsForWorkoutExerciseProvider(workoutExercise.id),
      (_, next) {
        final sets = next.valueOrNull;
        if (sets == null) return;
        final newlyCompleted = seen.record(workoutExercise.id, sets);
        if (newlyCompleted == null) return;
        _startRestFor(ref, workoutExercise, newlyCompleted, sets, exercises);
      },
      fireImmediately: true,
    );
  }
});

/// What [restTimerAutoStartProvider] already knows about each set, so a
/// rebuild (exercise added, list reordered) never mistakes old completions
/// for new ones. Lives as long as the session does.
final _completionLedgerProvider = Provider.family<_CompletionLedger, int>(
  (ref, sessionId) => _CompletionLedger(),
);

class _CompletionLedger {
  final Map<int, bool> _completedBySetId = {};
  final Set<int> _seededExercises = {};

  /// Records [sets] for [workoutExerciseId] and returns the set that has just
  /// become completed, if any. The first snapshot of an exercise only seeds
  /// the ledger — it reflects the past, not a tap.
  SetEntryData? record(int workoutExerciseId, List<SetEntryData> sets) {
    final seeded = _seededExercises.contains(workoutExerciseId);
    SetEntryData? latest;
    for (final set in sets) {
      final before = _completedBySetId[set.id];
      _completedBySetId[set.id] = set.isCompleted;
      if (!seeded || !set.isCompleted) continue;
      // A set that was open, or a brand-new row that arrived already done
      // (the watch logging an extra set), counts as completed just now.
      if (before == false || before == null) latest = set;
    }
    _seededExercises.add(workoutExerciseId);
    return latest;
  }
}

void _startRestFor(
  Ref ref,
  WorkoutExerciseData workoutExercise,
  SetEntryData set,
  List<SetEntryData> sets,
  List<WorkoutExerciseData> sessionExercises,
) {
  final catalogEntry = ref
      .read(exerciseCatalogSnapshotProvider)
      .valueOrNull
      ?.find(workoutExercise.exerciseId);
  final plan = restAfterCompletedSet(
    completed: workoutExercise,
    sessionExercises: sessionExercises,
    exerciseName: catalogEntry?.name ?? 'Rest',
    catalogDefaultRestSeconds: catalogEntry?.defaultRestSeconds,
    round: sets.where((s) => !s.isWarmup && s.isCompleted).length,
  );
  if (plan == null) return;

  // A completion that reached us late (watch over Bluetooth, a notification
  // tap drained on resume) rests from when it happened, not from now.
  final now = ref.read(clockProvider).now();
  final completedAt = set.completedAt;
  final elapsed = completedAt == null || completedAt.isAfter(now)
      ? 0
      : now.difference(completedAt).inSeconds;
  final remaining = plan.seconds - elapsed;
  if (remaining <= 1) return;

  // Everything is read above; only the write is deferred. `fireImmediately`
  // can land here while this provider is still building, and Riverpod
  // forbids touching another provider's state from inside a build.
  final timer = ref.read(restTimerProvider.notifier);
  Future.microtask(
    () => timer.start(
      seconds: remaining,
      totalSeconds: plan.seconds,
      exerciseName: plan.label,
    ),
  );
}
