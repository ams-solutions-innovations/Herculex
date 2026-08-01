import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local/database.dart';
import '../../nutrition/data/wear_sync_service.dart';
import '../../shell/main_scaffold.dart';
import 'workouts_repository.dart';

class WearWorkoutSyncService {
  final WorkoutsRepository _workoutsRepository;
  final WearSyncService _wearSyncService;
  final AppDatabase _db;
  final Ref _ref;
  int _lastCurrentExerciseIndex = 0;
  int _lastCurrentSetIndex = 0;
  int? _lastSyncedSessionId;
  bool _isApplyingRemoteSession = false;
  DateTime? _suppressOutboundUntil;

  WearWorkoutSyncService(
    this._workoutsRepository,
    this._wearSyncService,
    this._db,
    this._ref,
  ) {
    WearSyncService.onWatchWorkoutStarted = _handleWatchWorkoutStarted;
    WearSyncService.onWatchWorkoutUpdated = _handleWatchWorkoutUpdated;
    WearSyncService.onWatchWorkoutEnded = _handleWatchWorkoutEnded;
  }

  bool get shouldSkipOutboundSync {
    if (_isApplyingRemoteSession) return true;
    final until = _suppressOutboundUntil;
    return until != null && DateTime.now().isBefore(until);
  }

  Future<void> syncTemplatesToWatch(
    List<WorkoutTemplateData> templates,
    Map<int, List<TemplateExerciseData>> templateExercises,
    List<ExerciseCatalogData> catalog,
  ) async {
    final List<Map<String, dynamic>> jsonList = [];

    for (final template in templates) {
      final exercises = templateExercises[template.id] ?? [];
      final List<Map<String, dynamic>> exJsonList = [];

      for (final ex in exercises) {
        final catalogItem = catalog
            .where((c) => c.id == ex.exerciseId)
            .firstOrNull;
        if (catalogItem == null) continue;

        exJsonList.add({
          'name': catalogItem.name,
          'targetSets': ex.targetSets,
          'prevWeight': 0.0,
          'prevReps': 0,
        });
      }

      jsonList.add({
        'id': template.id.toString(),
        'name': template.name,
        'exercises': exJsonList,
      });
    }

    final jsonString = jsonEncode(jsonList);
    await _wearSyncService.syncWorkouts(jsonString);
  }

  Future<void> _handleWatchWorkoutStarted(
    String? sessionJson,
    bool jumpToWorkout,
  ) async {
    if (sessionJson == null || sessionJson.isEmpty) return;
    try {
      _isApplyingRemoteSession = true;
      final data = jsonDecode(sessionJson) as Map<String, dynamic>;
      _captureCursor(data);

      final activeSession = await _workoutsRepository
          .watchActiveSession()
          .first;
      int sessionId;
      if (activeSession != null && activeSession.id == _lastSyncedSessionId) {
        // Redundant re-delivery of a "started" event for the session we
        // already adopted from the watch — e.g. the user tapping the
        // "workout started" notification again, or the fast MessageClient
        // path and the durable DataClient fallback both firing. Apply in
        // place instead of destructively ending and recreating the session,
        // which used to wipe/replace an already-progressing workout with
        // whatever snapshot happened to be in this particular event and
        // could leave the UI briefly showing no active session at all.
        sessionId = activeSession.id;
      } else {
        // Either no session yet, or the phone has some other unrelated
        // active session — end that one and adopt the watch's new workout.
        if (activeSession != null) {
          await _workoutsRepository.endSession(activeSession.id);
        }
        sessionId = await _workoutsRepository.startSession();
        // This session already exists on the watch (it started it) — mark it
        // as synced so the next push to the watch is treated as an update,
        // not a fresh start (which would otherwise bounce a "start" echo back).
        _lastSyncedSessionId = sessionId;
      }
      await _syncSessionStateToDrift(sessionId, data);

      if (jumpToWorkout) {
        _ref.read(mainTabIndexProvider.notifier).state =
            2; // Jump to workouts tab
      }
    } catch (e, st) {
      debugPrint('Failed to handle watch workout started: $e\n$st');
    } finally {
      _isApplyingRemoteSession = false;
      _suppressOutboundUntil = DateTime.now().add(
        const Duration(milliseconds: 500),
      );
    }
  }

  Future<void> _handleWatchWorkoutUpdated(String? sessionJson) async {
    if (sessionJson == null || sessionJson.isEmpty) return;
    try {
      _isApplyingRemoteSession = true;
      final data = jsonDecode(sessionJson) as Map<String, dynamic>;
      _captureCursor(data);

      final activeSession = await _workoutsRepository
          .watchActiveSession()
          .first;
      int sessionId;
      if (activeSession != null) {
        sessionId = activeSession.id;
      } else {
        // The phone doesn't have a session yet — this update can arrive
        // before (or instead of) an explicit "start" event, e.g. via the
        // durable DataClient fallback after a missed MessageClient send.
        // Self-correct by creating one instead of silently dropping the
        // update, which used to leave watch-side edits (like adding an
        // exercise) invisible on the phone whenever the start signal missed.
        sessionId = await _workoutsRepository.startSession();
        _lastSyncedSessionId = sessionId;
      }
      await _syncSessionStateToDrift(sessionId, data);
    } catch (e, st) {
      debugPrint('Failed to handle watch workout updated: $e\n$st');
    } finally {
      _isApplyingRemoteSession = false;
      _suppressOutboundUntil = DateTime.now().add(
        const Duration(milliseconds: 500),
      );
    }
  }

  Future<void> _handleWatchWorkoutEnded() async {
    try {
      final activeSession = await _workoutsRepository
          .watchActiveSession()
          .first;
      if (activeSession != null) {
        await _workoutsRepository.endSession(activeSession.id);
      }
      _lastSyncedSessionId = null;
    } catch (e, st) {
      debugPrint('Failed to handle watch workout ended: $e\n$st');
    }
  }

  /// Call when the active session on the phone ends (finished or discarded)
  /// so the watch tears down its session and stops surfacing it in the
  /// background (ongoing activity, media controls, etc.).
  Future<void> notifySessionEnded() async {
    if (_lastSyncedSessionId == null) return;
    _lastSyncedSessionId = null;
    await _wearSyncService.endWorkoutOnWatch();
  }

  Future<void> _syncSessionStateToDrift(
    int sessionId,
    Map<String, dynamic> data,
  ) async {
    var catalog = await _db.select(_db.exerciseCatalog).get();

    // Watch sends 'exercises' array
    final exercises = data['exercises'] as List<dynamic>? ?? [];

    // Get current session exercises
    final existingExercises = await _workoutsRepository
        .watchSessionExercises(sessionId)
        .first;

    for (int i = 0; i < exercises.length; i++) {
      final exData = exercises[i] as Map<String, dynamic>;
      final template = exData['template'] as Map<String, dynamic>?;
      if (template == null) continue;

      final name = template['name'] as String?;
      if (name == null) continue;

      var catalogItem = catalog
          .where((c) => c.name.toLowerCase() == name.toLowerCase())
          .firstOrNull;
      if (catalogItem == null) {
        // The watch can send names not in the phone's catalog yet — e.g. it
        // appends an equipment suffix like "Squat (Barbell)" when the base
        // exercise required an equipment prompt. Create a minimal custom
        // catalog entry instead of silently dropping the exercise from sync.
        try {
          catalogItem = await _workoutsRepository.createCustomExercise(
            name: name,
            primaryMuscles: const [],
            equipment: 'other',
          );
          catalog = [...catalog, catalogItem];
        } catch (_) {
          // Lost a race with a concurrent sync call creating the same
          // custom exercise (unique index on name+equipment) — re-fetch
          // and use the one that just got created instead of failing this
          // whole update.
          catalog = await _db.select(_db.exerciseCatalog).get();
          catalogItem = catalog
              .where((c) => c.name.toLowerCase() == name.toLowerCase())
              .firstOrNull;
          if (catalogItem == null) rethrow;
        }
      }

      int workoutExerciseId;
      if (i < existingExercises.length) {
        workoutExerciseId = existingExercises[i].id;
      } else {
        workoutExerciseId = await _workoutsRepository.addExerciseToSession(
          sessionId: sessionId,
          exerciseId: catalogItem.id,
        );
      }

      // Sync sets
      final sets = exData['sets'] as List<dynamic>? ?? [];
      final existingSets = await _workoutsRepository
          .watchSetsForWorkoutExercise(workoutExerciseId)
          .first;

      for (int j = 0; j < sets.length; j++) {
        final setData = sets[j] as Map<String, dynamic>;
        final weight = (setData['weight'] as num?)?.toDouble() ?? 0.0;
        final reps = (setData['reps'] as num?)?.toInt() ?? 0;
        final rpeNum = (setData['rpe'] as num?)?.toDouble();
        final rpeX10 = rpeNum != null ? (rpeNum * 10).round() : null;
        final isCompleted = setData['completed'] as bool? ?? false;
        final watchSetType = setData['setType'] as String? ?? 'standard';
        final isWarmup = watchSetType == 'warmup';
        final setType = isWarmup ? 'standard' : watchSetType;
        final accessory = setData['accessory'] as String?;
        final setTypeMetaJson = accessory == null || accessory.isEmpty
            ? null
            : jsonEncode({'watchAccessory': accessory});

        if (j < existingSets.length) {
          // Update existing
          final existing = existingSets[j];
          if (existing.weightKg != weight ||
              existing.reps != reps ||
              existing.rpeX10 != rpeX10 ||
              existing.isCompleted != isCompleted ||
              existing.isWarmup != isWarmup ||
              existing.setType != setType ||
              (setTypeMetaJson != null &&
                  existing.setTypeMetaJson != setTypeMetaJson)) {
            await _workoutsRepository.updateSet(
              setId: existing.id,
              weightKg: weight,
              reps: reps,
              rpeX10: rpeX10,
              isCompleted: isCompleted,
              isWarmup: isWarmup,
              setType: setType,
              setTypeMetaJson: setTypeMetaJson,
            );
          }
        } else {
          // Insert new
          if (isCompleted) {
            await _workoutsRepository.addSet(
              workoutExerciseId: workoutExerciseId,
              weightKg: weight,
              reps: reps,
              rpeX10: rpeX10,
              isCompleted: true,
              isWarmup: isWarmup,
              setType: setType,
              setTypeMetaJson: setTypeMetaJson,
            );
          }
        }
      }
    }
  }

  void _captureCursor(Map<String, dynamic> data) {
    _lastCurrentExerciseIndex =
        (data['currentExerciseIndex'] as num?)?.toInt() ?? 0;
    _lastCurrentSetIndex = (data['currentSetIndex'] as num?)?.toInt() ?? 0;
  }

  Future<void> syncCatalogToWatch(List<ExerciseCatalogData> catalog) async {
    final list = catalog
        .map(
          (item) => {
            'name': item.name,
            'targetSets': 3,
            'prevWeight': 0.0,
            'prevReps': 0,
          },
        )
        .toList();
    await _wearSyncService.syncCatalog(jsonEncode(list));
  }

  Future<void> pushActiveSessionToWatch(WorkoutSessionData session) async {
    final isStart = _lastSyncedSessionId != session.id;
    _lastSyncedSessionId = session.id;

    try {
      final exercises = await _workoutsRepository
          .watchSessionExercises(session.id)
          .first;
      final catalog = await _db.select(_db.exerciseCatalog).get();

      final List<Map<String, dynamic>> exJsonList = [];
      var currentExerciseIndex = 0;
      var currentSetIndex = 0;
      var foundCurrent = false;

      for (var i = 0; i < exercises.length; i++) {
        final ex = exercises[i];
        final catalogItem = catalog
            .where((c) => c.id == ex.exerciseId)
            .firstOrNull;
        final String exerciseName = catalogItem?.name ?? 'Exercise';

        final sets = await _workoutsRepository
            .watchSetsForWorkoutExercise(ex.id)
            .first;
        final List<Map<String, dynamic>> setsJsonList = [];

        for (final setEntry in sets) {
          final setJson = <String, dynamic>{
            'weight': setEntry.weightKg,
            'reps': setEntry.reps,
            'setType': setEntry.setType,
            'completed': setEntry.isCompleted,
          };
          if (setEntry.rpeX10 != null) {
            setJson['rpe'] = setEntry.rpeX10! / 10.0;
          }
          setsJsonList.add(setJson);
        }

        final firstOpenSet = sets.indexWhere(
          (setEntry) => !setEntry.isCompleted,
        );
        if (!foundCurrent && firstOpenSet >= 0) {
          currentExerciseIndex = i;
          currentSetIndex = firstOpenSet;
          foundCurrent = true;
        }

        exJsonList.add({
          'template': {
            'name': exerciseName,
            'targetSets': 3,
            'prevWeight': 0.0,
            'prevReps': 0,
          },
          'sets': setsJsonList,
        });
      }

      final Map<String, dynamic> sessionJson = {
        'template': {
          'id': 'phone_session',
          'name': 'Active Workout',
          'exercises': exJsonList.map((e) => e['template']).toList(),
        },
        'currentExerciseIndex': _lastCurrentExerciseIndex,
        'currentSetIndex': _lastCurrentSetIndex,
        'startedAtEpochMs': session.startedAt.millisecondsSinceEpoch,
        'exercises': exJsonList,
      };

      if (foundCurrent) {
        sessionJson['currentExerciseIndex'] = currentExerciseIndex;
        sessionJson['currentSetIndex'] = currentSetIndex;
      }

      await _wearSyncService.syncActiveSession(
        jsonEncode(sessionJson),
        isStart: isStart,
      );
    } catch (e, st) {
      debugPrint('Failed to push active session to watch: $e\n$st');
    }
  }
}
