import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/core/utils/units.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/nutrition/data/wear_sync_contract.dart';
import 'package:herculex/features/nutrition/data/wear_sync_service.dart';
import 'package:herculex/features/profile/domain/profile.dart';
import 'package:herculex/features/shell/main_scaffold.dart';
import 'package:herculex/features/workouts/data/workouts_repository.dart';
import 'package:herculex/features/workouts/domain/equipment_variants.dart';
import 'package:herculex/features/workouts/domain/progression_engine.dart';
import 'package:herculex/features/workouts/domain/watch_exercise_resolver.dart';
import 'package:herculex/features/workouts/presentation/workouts_providers.dart';

class WearWorkoutSyncService {
  final WorkoutsRepository _workoutsRepository;
  final WearSyncService _wearSyncService;
  final AppDatabase _db;
  final Ref _ref;
  int _lastCurrentExerciseIndex = 0;
  int _lastCurrentSetIndex = 0;
  int? _lastSyncedSessionId;
  String? _lastSyncedEntityId;
  bool _isApplyingRemoteSession = false;
  DateTime? _suppressOutboundUntil;
  Future<void> _remoteApplyQueue = Future.value();
  Timer? _pendingOutboundTimer;
  WorkoutSessionData? _pendingOutboundSession;
  late final WearRevisionAllocator _revisionAllocator;
  final WearDedupeState _remoteDedupe = WearDedupeState();

  WearWorkoutSyncService(
    this._workoutsRepository,
    this._wearSyncService,
    this._db,
    this._ref,
  ) {
    _revisionAllocator = WearRevisionAllocator(
      _ref.read(sharedPreferencesProvider),
      'workout',
    );
    WearSyncService.onWatchWorkoutStarted = _handleWatchWorkoutStarted;
    WearSyncService.onWatchWorkoutUpdated = _handleWatchWorkoutUpdated;
    WearSyncService.onWatchWorkoutEnded = _handleWatchWorkoutEnded;
    WearSyncService.onWatchWorkoutSavedAsTemplate =
        _handleWatchWorkoutSavedAsTemplate;
  }

  bool get shouldSkipOutboundSync {
    if (_isApplyingRemoteSession) return true;
    final until = _suppressOutboundUntil;
    return until != null && DateTime.now().isBefore(until);
  }

  void scheduleOutboundSync(WorkoutSessionData session) {
    _pendingOutboundSession = session;
    if (_isApplyingRemoteSession) {
      return;
    }
    final until = _suppressOutboundUntil;
    final now = DateTime.now();
    if (until != null && now.isBefore(until)) {
      final delay = until.difference(now) + const Duration(milliseconds: 50);
      _pendingOutboundTimer?.cancel();
      _pendingOutboundTimer = Timer(delay, () {
        if (_pendingOutboundSession != null && !_isApplyingRemoteSession) {
          final s = _pendingOutboundSession!;
          _pendingOutboundSession = null;
          pushActiveSessionToWatch(s);
        }
      });
      return;
    }
    _pendingOutboundTimer?.cancel();
    _pendingOutboundSession = null;
    pushActiveSessionToWatch(session);
  }

  bool get hasActiveSyncedSession =>
      _lastSyncedSessionId != null ||
      (_lastSyncedEntityId != null && _lastSyncedEntityId!.isNotEmpty);

  SetEntryData? _findPriorSet(
    SetEntryData currentSet,
    int index,
    List<SetEntryData> allCurrentSets,
    List<SetEntryData> allLastSets,
  ) {
    if (allLastSets.isEmpty) return null;
    final sameTypeCurrent = allCurrentSets
        .where(
          (s) =>
              s.isWarmup == currentSet.isWarmup &&
              s.setType == currentSet.setType,
        )
        .toList();
    final subIdx = sameTypeCurrent.indexOf(currentSet);
    final sameTypePrior = allLastSets
        .where(
          (s) =>
              s.isWarmup == currentSet.isWarmup &&
              s.setType == currentSet.setType,
        )
        .toList();
    if (sameTypePrior.isNotEmpty) {
      if (subIdx >= 0 && subIdx < sameTypePrior.length) {
        return sameTypePrior[subIdx];
      }
      return sameTypePrior.last;
    }
    if (index < allLastSets.length) return allLastSets[index];
    return allLastSets.lastOrNull;
  }

  Future<({ProgressionGoal goal, double? weeklyPctOverride})>
  _resolveProgressionGoal(int exerciseId) async {
    try {
      final override = await (_db.select(
        _db.exerciseProgressions,
      )..where((t) => t.exerciseId.equals(exerciseId))).getSingleOrNull();
      if (override != null && override.enabled) {
        final goal = ProgressionGoal.values.firstWhere(
          (g) => g.name == override.goal,
          orElse: () => ProgressionGoal.muscleGain,
        );
        return (goal: goal, weeklyPctOverride: override.weeklyIncreasePct);
      }
      final profile = _ref.read(profileProvider).valueOrNull;
      final fitnessGoal = profile?.goal ?? FitnessGoal.maintenance;
      final goal = switch (fitnessGoal) {
        FitnessGoal.weightLoss => ProgressionGoal.fatLoss,
        FitnessGoal.muscleGain ||
        FitnessGoal.maintenance => ProgressionGoal.muscleGain,
        FitnessGoal.improveHealth => ProgressionGoal.endurance,
      };
      return (goal: goal, weeklyPctOverride: null);
    } catch (_) {
      return (goal: ProgressionGoal.muscleGain, weeklyPctOverride: null);
    }
  }

  Future<void> syncTemplatesToWatch(
    List<WorkoutTemplateData> templates,
    Map<int, List<TemplateExerciseData>> templateExercises,
    Map<int, List<TemplateSetData>> templateSets,
    List<ExerciseCatalogData> catalog,
  ) async {
    final List<Map<String, dynamic>> jsonList = [];
    final prefs = _ref.read(sharedPreferencesProvider);
    final hintModeRaw = prefs.getString('performance_hint_mode');
    final isNextMode = hintModeRaw == 'next';
    final weightFmt = _ref.read(weightFormatProvider);

    for (final template in templates) {
      final exercises = templateExercises[template.id] ?? [];
      final List<Map<String, dynamic>> exJsonList = [];

      for (final ex in exercises) {
        final catalogItem = catalog
            .where((c) => c.id == ex.exerciseId)
            .firstOrNull;
        if (catalogItem == null) continue;

        final lastSnapshot = await _workoutsRepository
            .lastPerformanceSnapshotFor(catalogItem.id);
        final lastSets = lastSnapshot?.sets ?? const <SetEntryData>[];
        final progression = await _resolveProgressionGoal(catalogItem.id);

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
            lastReps: defaultPriorReps > 0 ? defaultPriorReps : 1,
            goal: progression.goal,
            equipmentVariant: catalogItem.modality,
            weeklyIncreasePctOverride: progression.weeklyPctOverride,
          );
          if (target.weightKg > 0) defaultHintWeight = target.weightKg;
          if (target.reps > 0) defaultHintReps = target.reps;
        }

        String? performanceHint;
        if (isNextMode && (defaultHintWeight > 0 || defaultHintReps > 0)) {
          performanceHint =
              'Next: ${weightFmt.format(defaultHintWeight)} × $defaultHintReps';
        } else if (defaultPriorWeight > 0 || defaultPriorReps > 0) {
          performanceHint =
              'Last: ${weightFmt.format(defaultPriorWeight)} × $defaultPriorReps';
        }

        final tSets = templateSets[ex.id] ?? [];
        final plannedSetsJson = tSets.map((ts) {
          final prior =
              (ts.setOrder - 1) < lastSets.length && (ts.setOrder - 1) >= 0
              ? lastSets[ts.setOrder - 1]
              : lastSets.lastOrNull;
          double pWeight = prior?.weightKg ?? defaultPriorWeight;
          int pReps = prior?.reps ?? defaultPriorReps;
          double hWeight = pWeight;
          int hReps = pReps;
          if (isNextMode && prior != null && !prior.isWarmup) {
            final target = ProgressionEngine.suggestNext(
              lastWeightKg: pWeight,
              lastReps: pReps > 0 ? pReps : 1,
              goal: progression.goal,
              equipmentVariant: catalogItem.modality,
              weeklyIncreasePctOverride: progression.weeklyPctOverride,
            );
            if (target.weightKg > 0) hWeight = target.weightKg;
            if (target.reps > 0) hReps = target.reps;
          }
          final finalWeight =
              (ts.targetWeightKg != null && ts.targetWeightKg! > 0)
              ? ts.targetWeightKg!
              : (hWeight > 0 ? hWeight : defaultHintWeight);
          final finalReps = (ts.targetReps != null && ts.targetReps! > 0)
              ? ts.targetReps!
              : (hReps > 0
                    ? hReps
                    : (defaultHintReps > 0
                          ? defaultHintReps
                          : (ex.targetRepsMin ?? 10)));

          return {
            'wireId': 'template_set_${ts.id}',
            'setIndex': ts.setOrder,
            'setType': normalizeWearSetType(ts.setType),
            'isWarmup': ts.isWarmup,
            'targetReps': finalReps,
            'targetRepsMin': ts.targetRepsMin,
            'targetRepsMax': ts.targetRepsMax,
            'targetWeightKg': finalWeight,
            'setTypeMetaJson': ts.setTypeMetaJson,
          };
        }).toList();

        exJsonList.add({
          ..._templateJson(catalogItem),
          'targetSets': ex.targetSets,
          'supersetGroup': ex.supersetGroup,
          'prevWeight': defaultHintWeight > 0
              ? defaultHintWeight
              : defaultPriorWeight,
          'prevReps': defaultHintReps > 0 ? defaultHintReps : defaultPriorReps,
          if (performanceHint != null) 'performanceHint': performanceHint,
          'plannedSets': plannedSetsJson,
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
        final envelope = _decodeWorkoutEnvelope(sessionJson);
        final data = envelope.payload;
        if (!_remoteDedupe.wouldAccept(envelope)) {
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
        if (activeSession != null &&
            activeSession.sessionUuid == envelope.entityId) {
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
          sessionId = await _workoutsRepository.startSession(
            sessionUuid: envelope.entityId,
          );
          // This session already exists on the watch (it started it) — mark it
          // as synced so the next push to the watch is treated as an update,
          // not a fresh start (which would otherwise bounce a "start" echo back).
          _lastSyncedSessionId = sessionId;
        }
        await _syncSessionStateToDrift(sessionId, data);
        // Only commit the dedupe mark and ack the native host once the
        // workout is durably on the phone. Committing on the earlier
        // wouldAccept() check (as the old combined shouldAccept() did) would
        // mark this revision "seen" even if the write above throws, so a
        // retried delivery of the exact same envelope would then be silently
        // dropped forever instead of reapplied.
        _remoteDedupe.commit(envelope);
        await _wearSyncService.markWatchWorkoutApplied();

        if (jumpToWorkout) {
          _ref.read(mainTabIndexProvider.notifier).state =
              2; // Jump to workouts tab
        }
      });
    } catch (e, st) {
      debugPrint('Failed to handle watch workout started: $e\n$st');
    }
  }

  Future<void> _handleWatchWorkoutUpdated(String? sessionJson) async {
    if (sessionJson == null || sessionJson.isEmpty) return;
    try {
      await _enqueueRemoteApply(() async {
        final envelope = _decodeWorkoutEnvelope(sessionJson);
        final data = envelope.payload;
        if (!_remoteDedupe.wouldAccept(envelope)) {
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
          if (activeSession.sessionUuid != envelope.entityId) {
            // Update for a session other than the one currently active on
            // the phone — don't apply it to the wrong session. Full
            // reconciliation (e.g. "A already ended, adopt B instead") is
            // Phase 4 territory; this is intentionally conservative.
            _wearLog(
              envelope,
              delivery: 'flutter',
              apply: 'ignored-entity-mismatch',
            );
            await _wearSyncService.markWatchWorkoutApplied();
            return;
          }
          sessionId = activeSession.id;
        } else {
          // The phone doesn't have a session yet — this update can arrive
          // before (or instead of) an explicit "start" event, e.g. via the
          // durable DataClient fallback after a missed MessageClient send.
          final exercises = data['exercises'] as List<dynamic>?;
          if (exercises == null || exercises.isEmpty) {
            return;
          }
          sessionId = await _workoutsRepository.startSession(
            sessionUuid: envelope.entityId,
          );
          _lastSyncedSessionId = sessionId;
        }
        await _syncSessionStateToDrift(sessionId, data);
        // See the matching comment in _handleWatchWorkoutStarted — commit
        // only after the write above has actually succeeded.
        _remoteDedupe.commit(envelope);
        await _wearSyncService.markWatchWorkoutApplied();
      });
    } catch (e, st) {
      debugPrint('Failed to handle watch workout updated: $e\n$st');
    }
  }

  Future<void> _handleWatchWorkoutEnded(
    String? entityId, [
    bool isDiscard = false,
  ]) async {
    try {
      final activeSession = await _workoutsRepository
          .watchActiveSession()
          .first;
      // A null entityId is a defensive fallback (shouldn't happen once both
      // sides are on schemaVersion 2), not a license to end anything — a
      // non-null, non-matching entityId is a hard no-op so an end event for
      // a session the phone already moved on from can't kill the wrong one.
      if (activeSession != null &&
          (entityId == null || activeSession.sessionUuid == entityId)) {
        if (isDiscard) {
          await _workoutsRepository.deleteSession(activeSession.id);
        } else {
          await _workoutsRepository.endSession(activeSession.id);
        }
      }
      _lastSyncedSessionId = null;
      _lastSyncedEntityId = null;
    } catch (e, st) {
      debugPrint('Failed to handle watch workout ended: $e\n$st');
    }
  }

  Future<void> _handleWatchWorkoutSavedAsTemplate(String? entityId) async {
    try {
      final activeSession = await _workoutsRepository
          .watchActiveSession()
          .first;
      if (activeSession != null &&
          (entityId == null || activeSession.sessionUuid == entityId)) {
        // Find existing templates with the same name to append a number if needed
        final templates = await _db.select(_db.workoutTemplates).get();
        final baseName = "Watch Template";
        String templateName = baseName;
        int counter = 1;
        while (templates.any((t) => t.name == templateName)) {
          counter++;
          templateName = "$baseName $counter";
        }

        final templatesRepo = _ref.read(templatesRepositoryProvider);
        await templatesRepo.saveSessionAsTemplate(
          activeSession.id,
          templateName,
        );
      }
    } catch (e, st) {
      debugPrint('Failed to handle watch workout saved as template: $e\n$st');
    }
  }

  Future<void> _enqueueRemoteApply(Future<void> Function() apply) {
    // _remoteApplyQueue is the shared anchor every call chains onto to keep
    // applies serialized. Future.then() without an onError handler leaves the
    // receiver's error unhandled on the chained future — if `apply()` throws
    // (a malformed watch payload, a Drift write failure, ...), the plain
    // `.then()` this used to be would turn _remoteApplyQueue itself into a
    // permanently-errored future, and every later call chaining onto it would
    // never invoke its own apply() body at all: watch sync would silently
    // stop working until the app restarts. Reset the anchor with
    // catchError() so one failed apply can't poison the ones after it, while
    // `result` (returned to this call's own caller) still carries the real
    // error so the existing per-call try/catch keeps logging it.
    //
    // _isApplyingRemoteSession/_suppressOutboundUntil are owned entirely by
    // this queue, set/reset atomically around apply() itself, rather than by
    // each caller's own outer `finally` (the pre-Phase-5 shape). A caller's
    // `finally` runs as soon as *that caller's* await resolves, which isn't
    // necessarily in lockstep with the next queued closure actually starting
    // — a second call already chained onto the same queue could begin (and
    // set the flag true) a moment before the first call's `finally` cleared
    // it back to false, briefly clobbering the second call's still-in-flight
    // echo guard. Doing both inside the chain makes each queued apply's
    // guard window exactly bracket its own execution, with no gap for
    // another chain link to interleave through.
    final result = _remoteApplyQueue.catchError((_) {}).then((_) async {
      _isApplyingRemoteSession = true;
      try {
        await apply();
      } finally {
        _isApplyingRemoteSession = false;
        _suppressOutboundUntil = DateTime.now().add(
          const Duration(milliseconds: 500),
        );
        if (_pendingOutboundSession != null) {
          _pendingOutboundTimer?.cancel();
          _pendingOutboundTimer = Timer(const Duration(milliseconds: 550), () {
            if (_pendingOutboundSession != null && !_isApplyingRemoteSession) {
              final s = _pendingOutboundSession!;
              _pendingOutboundSession = null;
              pushActiveSessionToWatch(s);
            }
          });
        }
      }
    });
    _remoteApplyQueue = result.catchError((_) {});
    return result;
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
  Future<void> notifySessionEnded([String? sessionUuid]) async {
    final targetEntityId = (sessionUuid != null && sessionUuid.isNotEmpty)
        ? sessionUuid
        : (_lastSyncedEntityId ?? '');
    _lastSyncedSessionId = null;
    _lastSyncedEntityId = null;
    await _wearSyncService.endWorkoutOnWatch(targetEntityId);
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
  ) {
    // Wrapped in a single transaction so a crash/exception partway through
    // (a malformed watch payload, a Drift write failure, ...) rolls back
    // everything applied so far instead of leaving the session in a
    // partially-applied state — see Phase 2 of
    // docs/wear-sync-race-conditions-remediation-plan-2026-08-11.md (ENG-06
    // audit finding "Remote session apply is not wrapped in a Drift
    // transaction").
    return _db.transaction(() async {
      var catalog = await _db.select(_db.exerciseCatalog).get();
      var resolver = await _buildResolver(catalog);

      // Watch sends 'exercises' array
      final exercises = data['exercises'] as List<dynamic>? ?? [];

      // Get current session exercises, keyed by Drift row id so incoming
      // entries can be matched by wire identity instead of list position —
      // positional matching used to silently substitute/overwrite the wrong
      // exercise (and its sets) whenever a mid-session delete or insert on
      // the watch shifted everything after it by one slot. See Phase 3 of
      // docs/wear-sync-race-conditions-remediation-plan-2026-08-11.md.
      final existingExercises = await _workoutsRepository
          .watchSessionExercises(sessionId)
          .first;
      final existingExerciseById = {for (final e in existingExercises) e.id: e};
      final matchedExerciseIds = <int>{};

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

        final existingExerciseId = _driftIdFromWireId(
          exData['wireId'],
          'exercise_',
        );
        final existingExercise = existingExerciseId == null
            ? null
            : existingExerciseById[existingExerciseId];

        int workoutExerciseId;
        if (existingExercise != null) {
          matchedExerciseIds.add(existingExercise.id);
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
          // No wireId (a watch-created exercise not yet round-tripped
          // through a full session push) or a wireId the phone doesn't
          // recognize (this session's first time seeing this row) — either
          // way, genuinely new.
          workoutExerciseId = await _workoutsRepository.addExerciseToSession(
            sessionId: sessionId,
            exerciseId: catalogItem.id,
            // The watch used to encode this by renaming the exercise to
            // "Squat (Barbell)", which no phone row could ever match; it now
            // travels as the same per-log variant the phone sheet writes.
            equipmentVariant: equipmentVariant,
          );
        }

        // Sync sets, matched by wire identity for the same reason as
        // exercises above.
        final sets = exData['sets'] as List<dynamic>? ?? [];
        final existingSets = await _workoutsRepository
            .watchSetsForWorkoutExercise(workoutExerciseId)
            .first;
        final existingSetById = {for (final s in existingSets) s.id: s};
        final matchedSetIds = <int>{};

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
          final rawMetaJson = setData['setTypeMetaJson'] as String?;
          String? setTypeMetaJson;
          if (rawMetaJson != null &&
              rawMetaJson.isNotEmpty &&
              rawMetaJson != 'null') {
            if (accessory != null &&
                accessory.isNotEmpty &&
                accessory != 'None') {
              try {
                final map = jsonDecode(rawMetaJson) as Map<String, dynamic>;
                map['watchAccessory'] = accessory;
                setTypeMetaJson = jsonEncode(map);
              } catch (_) {
                setTypeMetaJson = rawMetaJson;
              }
            } else {
              setTypeMetaJson = rawMetaJson;
            }
          } else if (accessory != null &&
              accessory.isNotEmpty &&
              accessory != 'None') {
            setTypeMetaJson = jsonEncode({'watchAccessory': accessory});
          }
          final bodyweightKg = (setData['bodyweightKg'] as num?)?.toDouble();
          final chainsKg = (setData['chainsKg'] as num?)?.toDouble();
          final durationSeconds = (setData['durationSeconds'] as num?)?.toInt();
          final distanceM = (setData['distanceM'] as num?)?.toDouble();
          final completedAtEpochMs = (setData['completedAtEpochMs'] as num?)
              ?.toInt();
          final completedAt = completedAtEpochMs == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(completedAtEpochMs);

          final existingSetId = _driftIdFromWireId(setData['wireId'], 'set_');
          final existing = existingSetId == null
              ? null
              : existingSetById[existingSetId];

          if (existing != null) {
            matchedSetIds.add(existing.id);
            if (existing.weightKg != weight ||
                existing.reps != reps ||
                existing.durationSeconds != durationSeconds ||
                existing.rpeX10 != rpeX10 ||
                existing.isCompleted != isCompleted ||
                existing.isWarmup != isWarmup ||
                existing.setType != setType ||
                existing.setTypeMetaJson != setTypeMetaJson ||
                existing.bodyweightKg != bodyweightKg ||
                existing.chainsKg != chainsKg ||
                existing.distanceM != distanceM) {
              await _workoutsRepository.updateSet(
                setId: existing.id,
                weightKg: weight,
                reps: reps,
                durationSeconds: durationSeconds,
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
                distanceM: distanceM,
                clearDistanceM: distanceM == null,
                completedAt: completedAt,
              );
            }
          } else {
            // No wireId, or one the phone doesn't recognize — insert new
            // regardless of completed flag so planned/uncompleted sets sync.
            await _workoutsRepository.addSet(
              workoutExerciseId: workoutExerciseId,
              weightKg: weight,
              reps: reps,
              durationSeconds: durationSeconds,
              rpeX10: rpeX10,
              isCompleted: isCompleted,
              isWarmup: isWarmup,
              setType: setType,
              setTypeMetaJson: setTypeMetaJson,
              bodyweightKg: bodyweightKg,
              chainsKg: chainsKg,
              distanceM: distanceM,
              completedAt: completedAt,
            );
          }
        }

        for (final s in existingSets) {
          if (!matchedSetIds.contains(s.id)) {
            await _workoutsRepository.deleteSet(s.id);
          }
        }
      }

      for (final e in existingExercises) {
        if (!matchedExerciseIds.contains(e.id)) {
          await _workoutsRepository.removeWorkoutExercise(e.id);
        }
      }
    });
  }

  /// Extracts the Drift row id embedded in a wire id of the form
  /// `'$prefix$id'` (e.g. `'exercise_42'`, `'set_7'`) — the format
  /// [pushActiveSessionToWatch] sends and the watch round-trips unmodified
  /// for rows it didn't originate. Returns null for anything else (missing,
  /// wrong type, wrong prefix, or a watch-minted id like `'watch_set_...'`),
  /// which callers correctly treat as "no match — this is new."
  int? _driftIdFromWireId(dynamic wireId, String prefix) {
    if (wireId is! String || !wireId.startsWith(prefix)) return null;
    return int.tryParse(wireId.substring(prefix.length));
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
      if (item?.loggingMetric != null) 'loggingMetric': item!.loggingMetric,
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
      final weightFmt = _ref.read(weightFormatProvider);

      for (var i = 0; i < exercises.length; i++) {
        final ex = exercises[i];
        final catalogItem = catalog
            .where((c) => c.id == ex.exerciseId)
            .firstOrNull;

        final lastSnapshot = catalogItem != null
            ? await _workoutsRepository.lastPerformanceSnapshotFor(
                catalogItem.id,
              )
            : null;
        final lastSets = lastSnapshot?.sets ?? const <SetEntryData>[];
        final progression = await _resolveProgressionGoal(ex.exerciseId);

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
            lastReps: defaultPriorReps > 0 ? defaultPriorReps : 1,
            goal: progression.goal,
            equipmentVariant:
                ex.equipmentVariant ?? catalogItem?.modality ?? 'barbell',
            weeklyIncreasePctOverride: progression.weeklyPctOverride,
          );
          if (target.weightKg > 0) defaultHintWeight = target.weightKg;
          if (target.reps > 0) defaultHintReps = target.reps;
        }

        String? performanceHint;
        if (isNextMode && (defaultHintWeight > 0 || defaultHintReps > 0)) {
          performanceHint =
              'Next: ${weightFmt.format(defaultHintWeight)} × $defaultHintReps';
        } else if (defaultPriorWeight > 0 || defaultPriorReps > 0) {
          performanceHint =
              'Last: ${weightFmt.format(defaultPriorWeight)} × $defaultPriorReps';
        }

        final sets = await _workoutsRepository
            .watchSetsForWorkoutExercise(ex.id)
            .first;
        final List<Map<String, dynamic>> setsJsonList = [];

        for (var j = 0; j < sets.length; j++) {
          final setEntry = sets[j];
          final priorSet = _findPriorSet(setEntry, j, sets, lastSets);

          double setPriorWeight = priorSet?.weightKg ?? defaultPriorWeight;
          int setPriorReps = priorSet?.reps ?? defaultPriorReps;

          double setHintWeight = setPriorWeight;
          int setHintReps = setPriorReps;

          if (isNextMode && priorSet != null && !priorSet.isWarmup) {
            final target = ProgressionEngine.suggestNext(
              lastWeightKg: setPriorWeight,
              lastReps: setPriorReps > 0 ? setPriorReps : 1,
              goal: progression.goal,
              equipmentVariant:
                  ex.equipmentVariant ?? catalogItem?.modality ?? 'barbell',
              weeklyIncreasePctOverride: progression.weeklyPctOverride,
            );
            if (target.weightKg > 0) setHintWeight = target.weightKg;
            if (target.reps > 0) setHintReps = target.reps;
          }

          final targetWeight = setEntry.weightKg > 0
              ? setEntry.weightKg
              : (setHintWeight > 0 ? setHintWeight : defaultHintWeight);
          final targetReps = setEntry.reps > 0
              ? setEntry.reps
              : (setHintReps > 0
                    ? setHintReps
                    : (defaultHintReps > 0 ? defaultHintReps : 10));

          final weight = setEntry.isCompleted
              ? setEntry.weightKg
              : targetWeight;
          final reps = setEntry.isCompleted ? setEntry.reps : targetReps;

          final setJson = <String, dynamic>{
            'wireId': 'set_${setEntry.id}',
            'setIndex': setEntry.setIndex,
            'weight': weight,
            'reps': reps,
            if (setEntry.durationSeconds != null)
              'durationSeconds': setEntry.durationSeconds,
            if (setEntry.distanceM != null) 'distanceM': setEntry.distanceM,
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

        final plannedSetsJson = sets.map((setEntry) {
          final idx = sets.indexOf(setEntry);
          final priorSet = _findPriorSet(setEntry, idx, sets, lastSets);
          double setPriorWeight = priorSet?.weightKg ?? defaultPriorWeight;
          int setPriorReps = priorSet?.reps ?? defaultPriorReps;
          double setHintWeight = setPriorWeight;
          int setHintReps = setPriorReps;
          if (isNextMode && priorSet != null && !priorSet.isWarmup) {
            final target = ProgressionEngine.suggestNext(
              lastWeightKg: setPriorWeight,
              lastReps: setPriorReps > 0 ? setPriorReps : 1,
              goal: progression.goal,
              equipmentVariant:
                  ex.equipmentVariant ?? catalogItem?.modality ?? 'barbell',
              weeklyIncreasePctOverride: progression.weeklyPctOverride,
            );
            if (target.weightKg > 0) setHintWeight = target.weightKg;
            if (target.reps > 0) setHintReps = target.reps;
          }
          final tWeight = setEntry.weightKg > 0
              ? setEntry.weightKg
              : (setHintWeight > 0 ? setHintWeight : defaultHintWeight);
          final tReps = setEntry.reps > 0
              ? setEntry.reps
              : (setHintReps > 0
                    ? setHintReps
                    : (defaultHintReps > 0 ? defaultHintReps : 10));
          return {
            'wireId': 'set_${setEntry.id}',
            'setIndex': setEntry.setIndex,
            'setType': normalizeWearSetType(setEntry.setType),
            'isWarmup': setEntry.isWarmup,
            'targetReps': tReps,
            'targetWeightKg': tWeight,
            if (setEntry.durationSeconds != null)
              'durationSeconds': setEntry.durationSeconds,
            if (setEntry.distanceM != null)
              'targetDistanceM': setEntry.distanceM,
            'setTypeMetaJson': setEntry.setTypeMetaJson,
          };
        }).toList();

        exJsonList.add({
          'wireId': 'exercise_${ex.id}',
          'supersetGroup': ex.supersetGroup,
          'template': {
            ..._templateJson(
              catalogItem,
              equipmentVariant: ex.equipmentVariant,
            ),
            'supersetGroup': ex.supersetGroup,
            'targetSets': sets.length,
            'prevWeight': defaultHintWeight > 0
                ? defaultHintWeight
                : defaultPriorWeight,
            'prevReps': defaultHintReps > 0
                ? defaultHintReps
                : defaultPriorReps,
            if (performanceHint != null) 'performanceHint': performanceHint,
            'plannedSets': plannedSetsJson,
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
        _lastCurrentExerciseIndex = currentExerciseIndex;
        _lastCurrentSetIndex = currentSetIndex;
        sessionPayload['currentExerciseIndex'] = currentExerciseIndex;
        sessionPayload['currentSetIndex'] = currentSetIndex;
      } else if (exercises.isNotEmpty) {
        final lastIdx = exercises.length - 1;
        _lastCurrentExerciseIndex = lastIdx;
        sessionPayload['currentExerciseIndex'] = lastIdx;
        sessionPayload['currentSetIndex'] = 0;
      }

      // Fallback only guards a theoretical pre-migration NULL race; every
      // session created after schema 22 has a sessionUuid.
      final entityId = session.sessionUuid ?? 'phone_session_${session.id}';
      _lastSyncedEntityId = entityId;
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
