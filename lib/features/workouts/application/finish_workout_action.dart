import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../data/local/database.dart';
import '../../health/data/health_service.dart';
import '../../health/presentation/health_providers.dart';
import '../data/wear_workout_sync_service.dart';
import '../data/workouts_repository.dart';
import '../presentation/workouts_providers.dart';

/// Ends a workout session: names it, stamps `ended_at` and calories, mirrors it
/// to Health, and tells the watch.
///
/// ## Why this exists as a standalone action
///
/// `endSession` sets `workout_sessions.ended_at`, and `activeSessionProvider`
/// watches a query filtered on `ended_at IS NULL`. The instant the write
/// commits, that stream emits `null`, `WorkoutsView` swaps `ActiveWorkoutView`
/// out of the tree, and `_ActiveWorkoutViewState` is **disposed** — while the
/// Finish dialog is still on the Navigator stack.
///
/// Riverpod's `ref` throws a real `StateError` once its element is disposed
/// (`ConsumerStatefulElement._assertNotDisposed`), in release as well as debug.
/// So any `ref.read` *after* the `endSession` await is a live crash, and any
/// `ref.watch` from a dialog builder that outlives the widget is a crash
/// **during build** — which is what painted the red `ErrorWidget`.
///
/// Everything this needs is therefore resolved from [ref] up front, before the
/// first `await`. Callers must do the same for anything they touch afterwards.
class FinishWorkoutAction {
  FinishWorkoutAction._({
    required WorkoutsRepository repository,
    required HealthService healthService,
    required WearWorkoutSyncService wearSync,
    required DateTime now,
    required double bodyweightKg,
    required void Function(int sessionId) clearEditedEndedAt,
  }) : _repository = repository,
       _healthService = healthService,
       _wearSync = wearSync,
       _now = now,
       _bodyweightKg = bodyweightKg,
       _clearEditedEndedAt = clearEditedEndedAt;

  /// Resolves every dependency eagerly. **Call this before the first `await`**
  /// in the handler that finishes a workout.
  factory FinishWorkoutAction.resolve(WidgetRef ref) {
    final profile = ref.read(profileProvider).valueOrNull;
    final weightKg = profile?.weightKg;
    final editedEndedAt = ref.read(
      editingSessionOriginalEndedAtProvider.notifier,
    );

    return FinishWorkoutAction._(
      repository: ref.read(workoutsRepositoryProvider),
      healthService: ref.read(healthServiceProvider),
      wearSync: ref.read(wearWorkoutSyncServiceProvider),
      now: ref.read(clockProvider).now(),
      // The 20 kg floor rejects placeholder/imported junk, not real users.
      bodyweightKg: (weightKg != null && weightKg > 20)
          ? weightKg
          : _fallbackKg,
      clearEditedEndedAt: (sessionId) => editedEndedAt.update((state) {
        final copy = Map<int, DateTime>.from(state);
        copy.remove(sessionId);
        return copy;
      }),
    );
  }

  static const double _fallbackKg = 75.0;

  final WorkoutsRepository _repository;
  final HealthService _healthService;
  final WearWorkoutSyncService _wearSync;
  final DateTime _now;
  final double _bodyweightKg;
  final void Function(int sessionId) _clearEditedEndedAt;

  /// MET-based estimate: ~5 METs for general resistance training.
  int caloriesFor(Duration duration) {
    final minutes = duration.inMinutes > 0 ? duration.inMinutes : 1;
    return (5.0 * _bodyweightKg * (minutes / 60.0)).round().clamp(10, 3000);
  }

  DateTime resolveEnd(DateTime? explicitEndedAt) => explicitEndedAt ?? _now;

  /// Runs the whole finish sequence. Never throws for the optional side
  /// effects (Health, watch) — only a failed database write propagates, since
  /// that one means the workout was not saved.
  Future<void> run({
    required WorkoutSessionData session,
    String? name,
    DateTime? endedAt,
  }) async {
    final end = resolveEnd(endedAt);
    final calories = caloriesFor(end.difference(session.startedAt));

    final finalName = name?.trim();
    if (finalName != null && finalName.isNotEmpty) {
      await _repository.updateSessionName(session.id, finalName);
    }

    await _repository.endSession(
      session.id,
      endedAt: endedAt,
      caloriesBurned: calories,
    );

    // From here the calling widget is already disposed. Nothing below may
    // touch `ref` or a `BuildContext`.
    try {
      await _healthService.writeWorkoutToHealth(
        activityName: finalName?.isNotEmpty == true
            ? finalName!
            : (session.name ?? 'Workout'),
        startTime: session.startedAt,
        endTime: end,
        totalCaloriesBurned: calories,
      );
    } catch (_) {
      // Best-effort mirror; a missing Health permission must not block finish.
    }

    try {
      _wearSync.notifySessionEnded(session.sessionUuid);
    } catch (_) {
      // Watch may be absent or the channel unregistered on this platform.
    }

    if (endedAt != null) {
      _clearEditedEndedAt(session.id);
    }
  }
}
