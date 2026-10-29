import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/core/notifications/in_app_notification_controller.dart';
import 'package:herculex/core/notifications/in_app_notification_model.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/health/application/health_providers.dart';
import 'package:herculex/features/health/data/health_service.dart';
import 'package:herculex/features/profile/domain/profile.dart';
import 'package:herculex/features/workouts/application/calendar_providers.dart';
import 'package:herculex/features/workouts/application/calisthenics_providers.dart';
import 'package:herculex/features/workouts/application/workouts_providers.dart';
import 'package:herculex/features/workouts/data/calisthenics_progression_repository.dart';
import 'package:herculex/features/workouts/data/wear_workout_sync_service.dart';
import 'package:herculex/features/workouts/data/workout_energy_service.dart';
import 'package:herculex/features/workouts/data/workouts_repository.dart';
import 'package:herculex/features/workouts/domain/calendar_service.dart';

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
    required CalendarService calendarService,
    required bool isCalendarSyncEnabled,
    required String? calendarId,
    required DateTime now,
    required WorkoutEnergyService energyService,
    required Profile? profile,
    required void Function(int sessionId) clearEditedEndedAt,
    required CalisthenicsProgressionRepository calisthenics,
    required InAppNotificationNotifier notices,
  }) : _repository = repository,
       _healthService = healthService,
       _wearSync = wearSync,
       _calendarService = calendarService,
       _isCalendarSyncEnabled = isCalendarSyncEnabled,
       _calendarId = calendarId,
       _now = now,
       _energyService = energyService,
       _profile = profile,
       _clearEditedEndedAt = clearEditedEndedAt,
       _calisthenics = calisthenics,
       _notices = notices;

  /// Resolves every dependency eagerly. **Call this before the first `await`**
  /// in the handler that finishes a workout.
  factory FinishWorkoutAction.resolve(WidgetRef ref) {
    final profile = ref.read(profileProvider).valueOrNull;
    final editedEndedAt = ref.read(
      editingSessionOriginalEndedAtProvider.notifier,
    );

    return FinishWorkoutAction._(
      repository: ref.read(workoutsRepositoryProvider),
      healthService: ref.read(healthServiceProvider),
      wearSync: ref.read(wearWorkoutSyncServiceProvider),
      calendarService: ref.read(calendarServiceProvider),
      isCalendarSyncEnabled: ref.read(calendarSyncEnabledProvider),
      calendarId: ref.read(selectedCalendarIdProvider),
      now: ref.read(clockProvider).now(),
      energyService: ref.read(workoutEnergyServiceProvider),
      profile: profile,
      clearEditedEndedAt: (sessionId) => editedEndedAt.update((state) {
        final copy = Map<int, DateTime>.from(state);
        copy.remove(sessionId);
        return copy;
      }),
      calisthenics: ref.read(calisthenicsProgressionRepositoryProvider),
      notices: ref.read(inAppNotificationControllerProvider.notifier),
    );
  }

  final WorkoutsRepository _repository;
  final HealthService _healthService;
  final WearWorkoutSyncService _wearSync;
  final CalendarService _calendarService;
  final bool _isCalendarSyncEnabled;
  final String? _calendarId;
  final DateTime _now;
  final WorkoutEnergyService _energyService;
  final Profile? _profile;
  final void Function(int sessionId) _clearEditedEndedAt;
  final CalisthenicsProgressionRepository _calisthenics;
  final InAppNotificationNotifier _notices;

  DateTime resolveEnd(DateTime? explicitEndedAt) => explicitEndedAt ?? _now;

  /// Runs the whole finish sequence. Never throws for the optional side
  /// effects (Health, watch) — only a failed database write propagates, since
  /// that one means the workout was not saved.
  Future<void> run({
    required WorkoutSessionData session,
    String? name,
    DateTime? endedAt,
  }) async {
    if (session.endedAt != null && endedAt == null) return;
    final end = resolveEnd(endedAt);
    final energy = await _energyService.estimate(
      session: session,
      profile: _profile,
      endedAt: end,
      readHeartRate: true,
    );
    final calories = energy.activeKcal;

    final finalName = name?.trim();
    if (finalName != null && finalName.isNotEmpty) {
      await _repository.updateSessionName(session.id, finalName);
    }

    await _repository.endSession(
      session.id,
      endedAt: end,
      caloriesBurned: calories,
    );

    // From here the calling widget is already disposed. Nothing below may
    // touch `ref` or a `BuildContext`.
    if (endedAt == null && session.endedAt == null) {
      try {
        for (final recommendation in await _calisthenics.newlyReady(
          session.id,
        )) {
          _notices.show(
            InAppNotificationItem.info(
              label: recommendation.path.label,
              value: 'Ready to try ${recommendation.target.label}',
              duration: const Duration(seconds: 6),
            ),
          );
        }
      } catch (_) {
        // Optional coaching must never prevent a saved workout finishing.
      }
    }
    try {
      await _healthService.writeWorkoutToHealth(
        workoutSessionId: session.id,
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

    if (_isCalendarSyncEnabled) {
      try {
        await _calendarService.syncTwoWay(calendarId: _calendarId);
      } catch (_) {
        // Best-effort calendar mirror.
      }
    }

    if (endedAt != null) {
      _clearEditedEndedAt(session.id);
    }
  }
}
