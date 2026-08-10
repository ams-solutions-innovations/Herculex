import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local/database.dart';
import '../../nutrition/data/wear_sync_service.dart';
import '../../nutrition/data/wear_sync_contract.dart';
import '../../shell/main_scaffold.dart';
import '../domain/equipment_variants.dart';
import '../domain/watch_exercise_resolver.dart';
import '../../../app/providers.dart';
import '../domain/progression_engine.dart';
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
  Future<void> _remoteApplyQueue = Future.value();
  final WearRevisionAllocator _revisionAllocator = WearRevisionAllocator();
  final WearDedupeState _remoteDedupe = WearDedupeState();

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
    Map<int, List<TemplateSetData>> templateSets,
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
          ..._templateJson(catalogItem),
          'targetSets': ex.targetSets,
          'plannedSets': (templateSets[ex.id] ?? [])
              .map(_templateSetJson)
              .toList(),
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
      await _enqueueRemoteApply(() async {
        _isApplyingRemoteSession = true;
        final envelope = _decodeWorkoutEnvelope(sessionJson);
        final data = envelope.payload;
        if (!_remoteDedupe.shouldAccept(envelope)) {
          _wearLog(envelope, delivery: 'flutter', apply: 'ignored');
          await _wearSyncService.markWatchWorkoutApplied();
          return;
        }
        _wearLog(envelope, delivery: 'flutter', apply: 'accepted');
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
        // Only now is the workout durably on the phone — release the native
        // host's persisted copy. Acking before this point (which is what
        // dispatchPendingWorkout used to do implicitly) loses the session
        // outright if anything above throws.
        await _wearSyncService.markWatchWorkoutApplied();

        if (jumpToWorkout) {
          _ref.read(mainTabIndexProvider.notifier).state =
              2; // Jump to workouts tab
        }
      });
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
      await _enqueueRemoteApply(() async {
        _isApplyingRemoteSession = true;
        final envelope = _decodeWorkoutEnvelope(sessionJson);
        final data = envelope.payload;
        if (!_remoteDedupe.shouldAccept(envelope)) {
          _wearLog(envelope, delivery: 'flutter', apply: 'ignored');
          await _wearSyncService.markWatchWorkoutApplied();
          return;
        }
        _wearLog(envelope, delivery: 'flutter', apply: 'accepted');
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
          final exercises = data['exercises'] as List<dynamic>?;
          if (exercises == null || exercises.isEmpty) {
            return;
          }
          sessionId = await _workoutsRepository.startSession();
          _lastSyncedSessionId = sessionId;
        }
        await _syncSessionStateToDrift(sessionId, data);
        await _wearSyncService.markWatchWorkoutApplied();
      });
    } catch (e, st) {
      debugPrint('Failed to handle watch workout updated: $e\n$st');
    } finally {
      _isApplyingRemoteSession = false;
      _suppressOutboundUntil = DateTime.now().add(
        const Duration(milliseconds: 500),
      );
    }
  }

  Future<void> _handleWatchWorkoutEnded([bool isDiscard = false]) async {
    try {
      final activeSession = await _workoutsRepository
          .watchActiveSession()
          .first;
      if (activeSession != null) {
        if (isDiscard) {
          await _workoutsRepository.deleteSession(activeSession.id);
        } else {
          await _workoutsRepository.endSession(activeSession.id);
        }
      }
      _lastSyncedSessionId = null;
    } catch (e, st) {
      debugPrint('Failed to handle watch workout ended: $e\n$st');
    }
  }

  Future<void> _enqueueRemoteApply(Future<void> Function() apply) {
    _remoteApplyQueue = _remoteApplyQueue.then((_) => apply());
    return _remoteApplyQueue;
  }

  WearSyncEnvelope _decodeWorkoutEnvelope(String sessionJson) {
    return WearSyncEnvelope.decode(
      sessionJson,
      fallbackEntity: wearSyncEntityActiveWorkout,
      fallbackEntityId: 'watch_active_workout',
      fallbackOrigin: wearSyncOriginWatch,
    );
  }

  void _wearLog(
    WearSyncEnvelope envelope, {
    required String delivery,
    required String apply,
  }) {
    debugPrint(
      'WearSync entity=${envelope.entity} revision=${envelope.revision} '
      'origin=${envelope.origin} entityId=${envelope.entityId} '
      'delivery=$delivery apply=$apply',
    );
  }

  /// Call when the active session on the phone ends (finished or discarded)
  /// so the watch tears down its session and stops surfacing it in the
  /// background (ongoing activity, media controls, etc.).
  Future<void> notifySessionEnded() async {
    _lastSyncedSessionId = null;
    await _wearSyncService.endWorkoutOnWatch();
  }

  /// Indexes the catalog for inbound watch matching.
  ///
  /// Aliases come from both the normalized [ExerciseAliases] table and the
  /// denormalized `aka` blob, because seeded rows carry them in `aka` while
  /// custom exercises write the table.
  Future<WatchExerciseIndex> _buildResolver(
    List<ExerciseCatalogData> catalog,
  ) async {
    final aliasRows = await _db.select(_db.exerciseAliases).get();
    final aliasesById = <int, List<String>>{};
    for (final row in aliasRows) {
      (aliasesById[row.exerciseId] ??= []).add(row.alias);
    }
    return WatchExerciseIndex.build([
      for (final exercise in catalog)
        ResolvableExercise(
          id: exercise.id,
          slug: exercise.slug,
          name: exercise.name,
          aliases: [
            ...?aliasesById[exercise.id],
            ...WorkoutsRepository.splitAka(exercise.aka),
          ],
        ),
    ]);
  }

  Future<void> _syncSessionStateToDrift(
    int sessionId,
    Map<String, dynamic> data,
  ) async {
    var catalog = await _db.select(_db.exerciseCatalog).get();
    var resolver = await _buildResolver(catalog);

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

      final match = resolver.resolve(
        catalogExerciseId: template['catalogExerciseId'] as int?,
        slug: template['slug'] as String?,
        name: name,
      );
      final rawVariant = template['equipmentVariant'] as String?;
      final equipmentVariant =
          rawVariant != null && isKnownEquipmentVariant(rawVariant)
          ? rawVariant
          : null;

      ExerciseCatalogData? catalogItem = match == null
          ? null
          : catalog.where((c) => c.id == match.exerciseId).firstOrNull;

      if (catalogItem == null) {
        // Genuinely unknown to the phone — every identity and name rung of
        // [WatchExerciseIndex.resolve] missed. Create a minimal custom entry
        // instead of silently dropping the exercise from sync.
        try {
          catalogItem = await _workoutsRepository.createCustomExercise(
            name: name,
            primaryMuscles: const [],
            equipment: 'other',
          );
          catalog = [...catalog, catalogItem];
          resolver = await _buildResolver(catalog);
        } catch (_) {
          // Lost a race with a concurrent sync call creating the same
          // custom exercise (unique index on name+equipment) — re-fetch
          // and use the one that just got created instead of failing this
          // whole update.
          catalog = await _db.select(_db.exerciseCatalog).get();
          resolver = await _buildResolver(catalog);
          final retry = resolver.resolve(name: name);
          catalogItem = retry == null
              ? null
              : catalog.where((c) => c.id == retry.exerciseId).firstOrNull;
          if (catalogItem == null) rethrow;
        }
      }

      int workoutExerciseId;
      if (i < existingExercises.length) {
        final existingExercise = existingExercises[i];
        workoutExerciseId = existingExercise.id;
        if (existingExercise.exerciseId != catalogItem.id) {
          await _workoutsRepository.substituteExercise(
            workoutExerciseId: workoutExerciseId,
            newExerciseId: catalogItem.id,
          );
        }
        if (equipmentVariant != null &&
            existingExercise.equipmentVariant != equipmentVariant) {
          await _workoutsRepository.setEquipmentVariant(
            workoutExerciseId: workoutExerciseId,
            equipmentVariant: equipmentVariant,
          );
        }
      } else {
        workoutExerciseId = await _workoutsRepository.addExerciseToSession(
          sessionId: sessionId,
          exerciseId: catalogItem.id,
          // The watch used to encode this by renaming the exercise to
          // "Squat (Barbell)", which no phone row could ever match; it now
          // travels as the same per-log variant the phone sheet writes.
          equipmentVariant: equipmentVariant,
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
        final isWarmup = normalizeWearWarmup(
          setType: watchSetType,
          isWarmup: setData['isWarmup'] as bool?,
        );
        final setType = normalizeWearSetType(watchSetType);
        final accessory = setData['accessory'] as String?;
        final setTypeMetaJson =
            setData['setTypeMetaJson'] as String? ??
            (accessory == null || accessory.isEmpty
                ? null
                : jsonEncode({'watchAccessory': accessory}));
        final bodyweightKg = (setData['bodyweightKg'] as num?)?.toDouble();
        final chainsKg = (setData['chainsKg'] as num?)?.toDouble();
        final completedAtEpochMs = (setData['completedAtEpochMs'] as num?)
            ?.toInt();
        final completedAt = completedAtEpochMs == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(completedAtEpochMs);

        if (j < existingSets.length) {
          // Update existing
          final existing = existingSets[j];
          if (existing.weightKg != weight ||
              existing.reps != reps ||
              existing.rpeX10 != rpeX10 ||
              existing.isCompleted != isCompleted ||
              existing.isWarmup != isWarmup ||
              existing.setType != setType ||
              existing.setTypeMetaJson != setTypeMetaJson ||
              existing.bodyweightKg != bodyweightKg ||
              existing.chainsKg != chainsKg) {
            await _workoutsRepository.updateSet(
              setId: existing.id,
              weightKg: weight,
              reps: reps,
              rpeX10: rpeX10,
              clearRpe: rpeX10 == null,
              isCompleted: isCompleted,
              isWarmup: isWarmup,
              setType: setType,
              setTypeMetaJson: setTypeMetaJson,
              clearSetTypeMetaJson: setTypeMetaJson == null,
              bodyweightKg: bodyweightKg,
              clearBodyweightKg: bodyweightKg == null,
              chainsKg: chainsKg,
              clearChainsKg: chainsKg == null,
              completedAt: completedAt,
            );
          }
        } else {
          // Insert new set regardless of completed flag so planned/uncompleted sets sync
          await _workoutsRepository.addSet(
            workoutExerciseId: workoutExerciseId,
            weightKg: weight,
            reps: reps,
            rpeX10: rpeX10,
            isCompleted: isCompleted,
            isWarmup: isWarmup,
            setType: setType,
            setTypeMetaJson: setTypeMetaJson,
            bodyweightKg: bodyweightKg,
            chainsKg: chainsKg,
            completedAt: completedAt,
          );
        }
      }

      for (var j = existingSets.length - 1; j >= sets.length; j--) {
        await _workoutsRepository.deleteSet(existingSets[j].id);
      }
    }

    for (var i = existingExercises.length - 1; i >= exercises.length; i--) {
      await _workoutsRepository.removeWorkoutExercise(existingExercises[i].id);
    }
  }

  Map<String, dynamic> _templateSetJson(TemplateSetData set) {
    return {
      'wireId': 'template_set_${set.id}',
      'setIndex': set.setOrder,
      'setType': normalizeWearSetType(set.setType),
      'isWarmup': set.isWarmup,
      'targetReps': set.targetReps,
      'targetRepsMin': set.targetRepsMin,
      'targetRepsMax': set.targetRepsMax,
      'targetWeightKg': set.targetWeightKg,
      'setTypeMetaJson': set.setTypeMetaJson,
    };
  }

  void _captureCursor(Map<String, dynamic> data) {
    _lastCurrentExerciseIndex =
        (data['currentExerciseIndex'] as num?)?.toInt() ?? 0;
    _lastCurrentSetIndex = (data['currentSetIndex'] as num?)?.toInt() ?? 0;
  }

  Future<void> syncCatalogToWatch(List<ExerciseCatalogData> catalog) async {
    final list = catalog.map(_templateJson).toList();
    await _wearSyncService.syncCatalog(jsonEncode(list));
  }

  /// The shape every exercise crosses the wire in.
  ///
  /// [catalogExerciseId] and [slug] are what let the watch hand an exercise
  /// back without the phone having to guess from a display name;
  /// `equipmentOptions` is the movement's real equipment list, so the watch
  /// prompt offers the same choices the phone sheet does instead of a
  /// hardcoded ten-item menu.
  ///
  /// Fields the watch parser already defaults are omitted rather than sent as
  /// their default. The full catalog crosses as a single Wearable DataItem,
  /// which is hard-capped at 100 KB — with 400+ rows, the constant
  /// `targetSets`/`prevWeight`/`prevReps` triple cost more than the identity
  /// fields it was crowding out.
  Map<String, dynamic> _templateJson(
    ExerciseCatalogData? item, {
    String? fallbackName,
    String? equipmentVariant,
  }) {
    final json = <String, dynamic>{
      if (item != null) 'catalogExerciseId': item.id,
      if (item?.slug != null) 'slug': item!.slug,
      'name': item?.name ?? fallbackName ?? 'Exercise',
    };
    if (item != null) {
      final options = equipmentVariantsFor(item);
      // A single option is nothing to prompt about; the watch skips it either
      // way, so don't pay for the array.
      if (options.length > 1) json['equipmentOptions'] = options;
    }
    if (equipmentVariant != null) json['equipmentVariant'] = equipmentVariant;
    return json;
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

      final prefs = _ref.read(sharedPreferencesProvider);
      final hintModeRaw = prefs.getString('performance_hint_mode');
      final isNextMode = hintModeRaw == 'next';

      for (var i = 0; i < exercises.length; i++) {
        final ex = exercises[i];
        final catalogItem = catalog
            .where((c) => c.id == ex.exerciseId)
            .firstOrNull;

        final lastSnapshot = catalogItem != null
            ? await _workoutsRepository.lastPerformanceSnapshotFor(catalogItem.id)
            : null;
        final lastSets = lastSnapshot?.sets ?? const <SetEntryData>[];

        double defaultPriorWeight = 0.0;
        int defaultPriorReps = 0;
        if (lastSets.isNotEmpty) {
          final firstWorkingSet = lastSets.firstWhere(
            (s) => !s.isWarmup,
            orElse: () => lastSets.first,
          );
          defaultPriorWeight = firstWorkingSet.weightKg;
          defaultPriorReps = firstWorkingSet.reps;
        }

        double defaultHintWeight = defaultPriorWeight;
        int defaultHintReps = defaultPriorReps;

        if (isNextMode && (defaultPriorWeight > 0 || defaultPriorReps > 0)) {
          final target = ProgressionEngine.suggestNext(
            lastWeightKg: defaultPriorWeight,
            lastReps: defaultPriorReps > 0 ? defaultPriorReps : 8,
            goal: ProgressionGoal.muscleGain,
            equipmentVariant: ex.equipmentVariant ?? catalogItem?.modality ?? 'barbell',
          );
          if (target.weightKg > 0) defaultHintWeight = target.weightKg;
          if (target.reps > 0) defaultHintReps = target.reps;
        }

        final sets = await _workoutsRepository
            .watchSetsForWorkoutExercise(ex.id)
            .first;
        final List<Map<String, dynamic>> setsJsonList = [];

        for (var j = 0; j < sets.length; j++) {
          final setEntry = sets[j];
          final priorSet = j < lastSets.length ? lastSets[j] : lastSets.lastOrNull;
          
          double setPriorWeight = priorSet?.weightKg ?? defaultPriorWeight;
          int setPriorReps = priorSet?.reps ?? defaultPriorReps;

          double setHintWeight = setPriorWeight;
          int setHintReps = setPriorReps;

          if (isNextMode && priorSet != null && !priorSet.isWarmup) {
            final target = ProgressionEngine.suggestNext(
              lastWeightKg: setPriorWeight,
              lastReps: setPriorReps > 0 ? setPriorReps : 8,
              goal: ProgressionGoal.muscleGain,
              equipmentVariant: ex.equipmentVariant ?? catalogItem?.modality ?? 'barbell',
            );
            if (target.weightKg > 0) setHintWeight = target.weightKg;
            if (target.reps > 0) setHintReps = target.reps;
          }

          final weight = setEntry.weightKg > 0 ? setEntry.weightKg : setHintWeight;
          final reps = setEntry.reps > 0 ? setEntry.reps : (setHintReps > 0 ? setHintReps : 8);

          final setJson = <String, dynamic>{
            'wireId': 'set_${setEntry.id}',
            'setIndex': setEntry.setIndex,
            'weight': weight,
            'reps': reps,
            'setType': normalizeWearSetType(setEntry.setType),
            'isWarmup': setEntry.isWarmup,
            'setTypeMetaJson': setEntry.setTypeMetaJson,
            'bodyweightKg': setEntry.bodyweightKg,
            'chainsKg': setEntry.chainsKg,
            'completed': setEntry.isCompleted,
            'completedAtEpochMs': setEntry.completedAt?.millisecondsSinceEpoch,
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
          'wireId': 'exercise_${ex.id}',
          'template': {
            ..._templateJson(
              catalogItem,
              equipmentVariant: ex.equipmentVariant,
            ),
            'targetSets': sets.length,
            'prevWeight': defaultHintWeight > 0 ? defaultHintWeight : defaultPriorWeight,
            'prevReps': defaultHintReps > 0 ? defaultHintReps : defaultPriorReps,
            'plannedSets': sets
                .map(
                  (setEntry) => {
                    'wireId': 'set_${setEntry.id}',
                    'setIndex': setEntry.setIndex,
                    'setType': normalizeWearSetType(setEntry.setType),
                    'isWarmup': setEntry.isWarmup,
                    'targetReps': setEntry.reps > 0 ? setEntry.reps : (defaultHintReps > 0 ? defaultHintReps : 8),
                    'targetWeightKg': setEntry.weightKg > 0 ? setEntry.weightKg : defaultHintWeight,
                    'setTypeMetaJson': setEntry.setTypeMetaJson,
                  },
                )
                .toList(),
          },
          'sets': setsJsonList,
        });
      }

      final templateName =
          (session.name != null && session.name!.trim().isNotEmpty)
          ? session.name!
          : 'Active Workout';

      final Map<String, dynamic> sessionPayload = {
        'template': {
          'id': 'phone_session',
          'name': templateName,
          'exercises': exJsonList.map((e) => e['template']).toList(),
        },
        'currentExerciseIndex': _lastCurrentExerciseIndex,
        'currentSetIndex': _lastCurrentSetIndex,
        'startedAtEpochMs': session.startedAt.millisecondsSinceEpoch,
        'exercises': exJsonList,
      };

      if (foundCurrent) {
        sessionPayload['currentExerciseIndex'] = currentExerciseIndex;
        sessionPayload['currentSetIndex'] = currentSetIndex;
      }

      final entityId = 'phone_session_${session.id}';
      final sessionJson = WearSyncEnvelope.wrap(
        entity: wearSyncEntityActiveWorkout,
        entityId: entityId,
        revision: _revisionAllocator.next(),
        origin: wearSyncOriginPhone,
        payload: sessionPayload,
      ).encode();

      await _wearSyncService.syncActiveSession(sessionJson, isStart: isStart);
    } catch (e, st) {
      debugPrint('Failed to push active session to watch: $e\n$st');
    }
  }
}
