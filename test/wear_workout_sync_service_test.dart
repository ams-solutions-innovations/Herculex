import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/core/clock.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/nutrition/data/wear_sync_contract.dart';
import 'package:herculex/features/nutrition/data/wear_sync_service.dart';
import 'package:herculex/features/workouts/data/wear_workout_sync_service.dart';
import 'package:herculex/features/workouts/data/workouts_repository.dart';

/// Regression tests for the Phase 2 fixes in
/// docs/wear-sync-race-conditions-remediation-plan-2026-08-11.md:
/// transactional session apply (ENG-06), dedupe committed only after a
/// successful apply (ENG-07/10/12), and the remote-apply queue no longer
/// poisoning itself on a failed apply (ENG-06/19).
///
/// [WearWorkoutSyncService]'s watch-event handlers are private, so these
/// tests drive them the same way the production native host does: through
/// the [WearSyncService] platform channel, which dispatches to whichever
/// handler the constructor registered. Handler bodies run un-awaited by the
/// dispatcher, so [pumpEventQueue] is used to let their internal awaits
/// (Drift I/O) settle before asserting.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const codec = StandardMethodCodec();
  final wearBinding = TestDefaultBinaryMessengerBinding.instance;

  Future<void> emitWorkoutUpdated(String sessionJson) {
    return wearBinding.defaultBinaryMessenger.handlePlatformMessage(
      WearSyncService.channelName,
      codec.encodeMethodCall(
        MethodCall('onWatchWorkoutUpdated', {'session_json': sessionJson}),
      ),
      (_) {},
    );
  }

  Future<void> emitWorkoutStarted(
    String sessionJson, {
    bool jumpToWorkout = false,
  }) {
    return wearBinding.defaultBinaryMessenger.handlePlatformMessage(
      WearSyncService.channelName,
      codec.encodeMethodCall(
        MethodCall('onWatchWorkoutStarted', {
          'session_json': sessionJson,
          'jump_to_workout': jumpToWorkout,
        }),
      ),
      (_) {},
    );
  }

  Future<void> emitWorkoutEnded(String? entityId, {bool isDiscard = false}) {
    return wearBinding.defaultBinaryMessenger.handlePlatformMessage(
      WearSyncService.channelName,
      codec.encodeMethodCall(
        MethodCall('onWatchWorkoutEnded', {
          'entityId': entityId,
          'isDiscard': isDiscard,
        }),
      ),
      (_) {},
    );
  }

  late AppDatabase db;
  late WorkoutsRepository repo;
  late ProviderContainer container;

  setUp(() async {
    WearSyncService.resetForTesting();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel(WearSyncService.channelName),
          (call) async => null,
        );

    // Required once WearWorkoutSyncService's constructor reads
    // sharedPreferencesProvider to build its persisted WearRevisionAllocator
    // (Phase 1b) — without this override every test in this file throws
    // UnimplementedError before it even gets to exercise anything.
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = WorkoutsRepository(db, const SystemClock());
    container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel(WearSyncService.channelName),
          null,
        );
    WearSyncService.resetForTesting();
  });

  Ref readRef() {
    final refProvider = Provider<Ref>((ref) => ref);
    return container.read(refProvider);
  }

  // Constructing the service wires WearSyncService.onWatchWorkoutUpdated to
  // this instance's handler as a side effect — the returned value only
  // needs to be kept alive for the duration of the test.
  WearWorkoutSyncService buildService() {
    return WearWorkoutSyncService(repo, WearSyncService(), db, readRef());
  }

  Future<int> createExercise(String name) {
    return db
        .into(db.exerciseCatalog)
        .insert(
          ExerciseCatalogCompanion.insert(
            name: name,
            primaryMuscle: 'Chest',
            equipment: 'Dumbbell',
            mechanics: 'compound',
            force: 'push',
            plane: 'horizontal',
          ),
        );
  }

  String workoutEnvelopeJson({
    required String entityId,
    required int revision,
    required List<Map<String, dynamic>> exercises,
    int updatedAtEpochMs = 1000,
  }) {
    return WearSyncEnvelope.wrap(
      entity: wearSyncEntityActiveWorkout,
      entityId: entityId,
      revision: revision,
      origin: wearSyncOriginWatch,
      updatedAtEpochMs: updatedAtEpochMs,
      payload: {
        'currentExerciseIndex': 0,
        'currentSetIndex': 0,
        'exercises': exercises,
      },
    ).encode();
  }

  Map<String, dynamic> validExercise(int catalogExerciseId, String name) {
    return {
      'template': {'catalogExerciseId': catalogExerciseId, 'name': name},
      'sets': [
        {'weight': 40, 'reps': 8, 'completed': true},
      ],
    };
  }

  Map<String, dynamic> exerciseWithMalformedSets(
    int catalogExerciseId,
    String name,
  ) {
    return {
      'template': {'catalogExerciseId': catalogExerciseId, 'name': name},
      // 'sets' must decode as a List — a String here forces a TypeError
      // partway through _syncSessionStateToDrift's exercise loop.
      'sets': 'not-a-list',
    };
  }

  test(
    'a malformed exercise mid-payload rolls back the whole apply (transactional)',
    () async {
      buildService();
      // Phase 1 apply-time gating rejects an update whose entityId doesn't
      // match the phone's active session, so the session must be started
      // with the same entityId the incoming envelope carries.
      final sessionId = await repo.startSession(sessionUuid: 'watch-session-1');
      final exerciseId = await createExercise('Bench Press');

      final badPayload = workoutEnvelopeJson(
        entityId: 'watch-session-1',
        revision: 1,
        exercises: [
          // First exercise is fully valid and would, without a transaction,
          // be durably written before the second exercise's malformed
          // 'sets' field throws.
          validExercise(exerciseId, 'Bench Press'),
          exerciseWithMalformedSets(exerciseId, 'Bench Press'),
        ],
      );

      await emitWorkoutUpdated(badPayload);
      await pumpEventQueue();

      final exercises = await repo.watchSessionExercises(sessionId).first;
      expect(
        exercises,
        isEmpty,
        reason:
            'the whole apply must roll back — the first exercise must not '
            'be left durably written while the second one failed',
      );
    },
  );

  test(
    'a failed apply does not poison dedupe — retrying the same revision '
    'after a failure still applies',
    () async {
      buildService();
      final exerciseId = await createExercise('Bench Press');

      // First delivery: revision 1, payload fails partway through
      // (malformed 'sets'), so _syncSessionStateToDrift throws and the
      // whole session apply is rolled back by the Phase 2 transaction fix.
      final failingPayload = workoutEnvelopeJson(
        entityId: 'watch-session-2',
        revision: 1,
        exercises: [exerciseWithMalformedSets(exerciseId, 'Bench Press')],
      );
      await emitWorkoutUpdated(failingPayload);
      await pumpEventQueue();

      final sessionAfterFailure = await repo.watchActiveSession().first;
      expect(
        sessionAfterFailure,
        isNotNull,
        reason: 'startSession() itself is not part of the failed transaction',
      );
      expect(
        await repo.watchSessionExercises(sessionAfterFailure!.id).first,
        isEmpty,
      );

      // Second delivery: the exact same entityId + revision, this time with
      // a valid payload. Before the Phase 2 fix, WearDedupeState committed
      // the revision on the first (failed) attempt's check alone, so this
      // retry would have been silently ignored as a stale duplicate and
      // never actually applied.
      final retryPayload = workoutEnvelopeJson(
        entityId: 'watch-session-2',
        revision: 1,
        exercises: [validExercise(exerciseId, 'Bench Press')],
      );
      await emitWorkoutUpdated(retryPayload);
      await pumpEventQueue();

      final exercisesAfterRetry = await repo
          .watchSessionExercises(sessionAfterFailure.id)
          .first;
      expect(
        exercisesAfterRetry,
        hasLength(1),
        reason: 'the retried revision must actually be applied, not dropped',
      );
    },
  );

  test(
    'two updates delivered back-to-back without awaiting between them both '
    'apply, in order (Phase 5 — echo-guard flag owned by the queue itself, '
    'not each caller\'s own finally block)',
    () async {
      buildService();
      final exerciseId = await createExercise('Bench Press');

      final first = workoutEnvelopeJson(
        entityId: 'session-echo-guard',
        revision: 1,
        exercises: [validExercise(exerciseId, 'Bench Press')],
      );
      final second = workoutEnvelopeJson(
        entityId: 'session-echo-guard',
        revision: 2,
        exercises: [
          validExercise(exerciseId, 'Bench Press'),
          validExercise(exerciseId, 'Bench Press'),
        ],
      );

      // Deliberately not awaited between them, mirroring how the platform
      // channel dispatcher actually drives these handlers in production
      // (un-awaited, see this file's own doc comment) — this is exactly the
      // interleaving window the echo-guard fix targets: the second call's
      // queued closure gets chained onto _remoteApplyQueue while the first
      // is still in flight, before the first caller's own `try/catch` has
      // had a chance to return.
      final firstFuture = emitWorkoutUpdated(first);
      final secondFuture = emitWorkoutUpdated(second);
      await Future.wait([firstFuture, secondFuture]);
      await pumpEventQueue();

      final session = await repo.watchActiveSession().first;
      expect(session, isNotNull);
      expect(
        await repo.watchSessionExercises(session!.id).first,
        hasLength(2),
        reason:
            'both updates must apply, strictly in order, ending on '
            'revision 2\'s two-exercise payload',
      );
    },
  );

  test(
    'a failed apply does not poison the remote-apply queue — a later '
    'update still applies',
    () async {
      buildService();

      // Not valid JSON at all — throws inside _decodeWorkoutEnvelope, which
      // runs as the very first line inside the queued apply closure. Before
      // the Phase 2 fix, this alone was enough to leave _remoteApplyQueue
      // permanently errored, silently dropping every later watch update.
      await emitWorkoutUpdated('not valid json {{{');
      await pumpEventQueue();

      final exerciseId = await createExercise('Bench Press');
      final goodPayload = workoutEnvelopeJson(
        entityId: 'watch-session-3',
        revision: 1,
        exercises: [validExercise(exerciseId, 'Bench Press')],
      );
      await emitWorkoutUpdated(goodPayload);
      await pumpEventQueue();

      final session = await repo.watchActiveSession().first;
      expect(
        session,
        isNotNull,
        reason: 'the update after the malformed one must still be applied',
      );
      expect(
        await repo.watchSessionExercises(session!.id).first,
        hasLength(1),
      );
    },
  );

  test(
    'an update for a different entityId than the active session is ignored '
    '— the active session is left unmutated (Phase 1a apply-time gating)',
    () async {
      buildService();
      final sessionId = await repo.startSession(sessionUuid: 'session-a');
      final exerciseId = await createExercise('Bench Press');

      final updateForOtherSession = workoutEnvelopeJson(
        entityId: 'session-b',
        revision: 1,
        exercises: [validExercise(exerciseId, 'Bench Press')],
      );
      await emitWorkoutUpdated(updateForOtherSession);
      await pumpEventQueue();

      final activeSession = await repo.watchActiveSession().first;
      expect(
        activeSession?.id,
        sessionId,
        reason: 'the mismatched update must not end/replace session A',
      );
      expect(
        await repo.watchSessionExercises(sessionId).first,
        isEmpty,
        reason: 'the mismatched update must not be applied to session A',
      );
    },
  );

  test(
    'an ended event with a non-matching entityId does not end the active '
    'session (Phase 1a apply-time gating)',
    () async {
      buildService();
      await repo.startSession(sessionUuid: 'session-a');

      await emitWorkoutEnded('some-other-session-uuid');
      await pumpEventQueue();

      expect(
        await repo.watchActiveSession().first,
        isNotNull,
        reason: 'a mismatched entityId must not end session A',
      );
    },
  );

  test(
    'an ended event with the matching entityId ends the active session',
    () async {
      buildService();
      await repo.startSession(sessionUuid: 'session-a');

      await emitWorkoutEnded('session-a');
      await pumpEventQueue();

      expect(await repo.watchActiveSession().first, isNull);
    },
  );

  test(
    'a started-event redelivery with the same UUID applies in place instead '
    'of destroying and recreating the session',
    () async {
      buildService();
      final exerciseId = await createExercise('Bench Press');

      final firstStart = workoutEnvelopeJson(
        entityId: 'session-a',
        revision: 1,
        exercises: [validExercise(exerciseId, 'Bench Press')],
      );
      await emitWorkoutStarted(firstStart);
      await pumpEventQueue();

      final firstSession = await repo.watchActiveSession().first;
      expect(firstSession, isNotNull);

      final redelivery = workoutEnvelopeJson(
        entityId: 'session-a',
        revision: 2,
        exercises: [
          validExercise(exerciseId, 'Bench Press'),
          validExercise(exerciseId, 'Bench Press'),
        ],
      );
      await emitWorkoutStarted(redelivery);
      await pumpEventQueue();

      final secondSession = await repo.watchActiveSession().first;
      expect(
        secondSession?.id,
        firstSession!.id,
        reason:
            'redelivery of the same session UUID must apply in place, not '
            'end and recreate the session under a new local id',
      );
      expect(
        await repo.watchSessionExercises(secondSession!.id).first,
        hasLength(2),
      );
    },
  );

  // ── Phase 3: ID-based exercise/set reconciliation ───────────────────────
  //
  // These mirror the wireId round trip the real watch now performs (see the
  // Kotlin-side ActiveExercise.wireId / LoggedSet.wireId additions): the
  // phone sends 'exercise_<driftId>' / 'set_<driftId>' wireIds on its own
  // pushes, and the watch echoes them back unmodified for rows it didn't
  // originate. A wireId the phone doesn't recognize (missing, or a
  // watch-minted 'watch_...' one) is always a genuinely new row.

  Map<String, dynamic> exerciseWithWireId(
    int catalogExerciseId,
    String name, {
    String? wireId,
    List<Map<String, dynamic>> sets = const [
      {'weight': 40, 'reps': 8, 'completed': true},
    ],
  }) {
    return {
      if (wireId != null) 'wireId': wireId,
      'template': {'catalogExerciseId': catalogExerciseId, 'name': name},
      'sets': sets,
    };
  }

  Map<String, dynamic> setWithWireId({
    required double weight,
    required int reps,
    String? wireId,
    bool completed = true,
  }) {
    return {
      if (wireId != null) 'wireId': wireId,
      'weight': weight,
      'reps': reps,
      'completed': completed,
    };
  }

  test(
    'deleting the first exercise of three (ID-based) leaves the other two '
    'with their original row identity, not shifted/corrupted',
    () async {
      buildService();
      final exerciseA = await createExercise('Bench Press');
      final exerciseB = await createExercise('Squat');
      final exerciseC = await createExercise('Deadlift');

      final firstPayload = workoutEnvelopeJson(
        entityId: 'session-p3-1',
        revision: 1,
        exercises: [
          exerciseWithWireId(exerciseA, 'Bench Press'),
          exerciseWithWireId(exerciseB, 'Squat'),
          exerciseWithWireId(exerciseC, 'Deadlift'),
        ],
      );
      await emitWorkoutUpdated(firstPayload);
      await pumpEventQueue();

      final session = await repo.watchActiveSession().first;
      final rowsAfterFirst = await repo
          .watchSessionExercises(session!.id)
          .first;
      expect(rowsAfterFirst, hasLength(3));
      final bId = rowsAfterFirst
          .firstWhere((r) => r.exerciseId == exerciseB)
          .id;
      final cId = rowsAfterFirst
          .firstWhere((r) => r.exerciseId == exerciseC)
          .id;

      // Watch deletes the first exercise (Bench Press) and echoes back the
      // phone-assigned wireIds for the two that remain.
      final secondPayload = workoutEnvelopeJson(
        entityId: 'session-p3-1',
        revision: 2,
        exercises: [
          exerciseWithWireId(exerciseB, 'Squat', wireId: 'exercise_$bId'),
          exerciseWithWireId(exerciseC, 'Deadlift', wireId: 'exercise_$cId'),
        ],
      );
      await emitWorkoutUpdated(secondPayload);
      await pumpEventQueue();

      final rowsAfterSecond = await repo
          .watchSessionExercises(session.id)
          .first;
      expect(
        rowsAfterSecond.map((r) => r.id).toSet(),
        {bId, cId},
        reason:
            'Squat and Deadlift must keep their original row identity — '
            'positional matching would have substituted Squat\'s row into '
            'Bench Press\'s slot, substituted Deadlift\'s row into Squat\'s '
            'slot, and deleted the real Deadlift row entirely',
      );
    },
  );

  test(
    'a matching wireId with a different exercise substitutes in place '
    '(row identity preserved)',
    () async {
      buildService();
      final exerciseA = await createExercise('Bench Press');
      final exerciseB = await createExercise('Squat');

      final firstPayload = workoutEnvelopeJson(
        entityId: 'session-p3-2',
        revision: 1,
        exercises: [exerciseWithWireId(exerciseA, 'Bench Press')],
      );
      await emitWorkoutUpdated(firstPayload);
      await pumpEventQueue();

      final session = await repo.watchActiveSession().first;
      final originalRowId =
          (await repo.watchSessionExercises(session!.id).first).single.id;

      final substitutionPayload = workoutEnvelopeJson(
        entityId: 'session-p3-2',
        revision: 2,
        exercises: [
          exerciseWithWireId(
            exerciseB,
            'Squat',
            wireId: 'exercise_$originalRowId',
          ),
        ],
      );
      await emitWorkoutUpdated(substitutionPayload);
      await pumpEventQueue();

      final rowsAfter = await repo.watchSessionExercises(session.id).first;
      expect(rowsAfter, hasLength(1));
      expect(
        rowsAfter.single.id,
        originalRowId,
        reason: 'a matching wireId is a substitution, not a delete+insert',
      );
      expect(rowsAfter.single.exerciseId, exerciseB);
    },
  );

  test(
    'an unrecognized wireId with a different exercise is a delete+insert, '
    'not a substitution (row identity changes) — the explicit slot-id '
    'signal the plan calls for, not positional coincidence',
    () async {
      buildService();
      final exerciseA = await createExercise('Bench Press');
      final exerciseB = await createExercise('Squat');

      final firstPayload = workoutEnvelopeJson(
        entityId: 'session-p3-3',
        revision: 1,
        exercises: [exerciseWithWireId(exerciseA, 'Bench Press')],
      );
      await emitWorkoutUpdated(firstPayload);
      await pumpEventQueue();

      final session = await repo.watchActiveSession().first;
      final originalRowId =
          (await repo.watchSessionExercises(session!.id).first).single.id;

      final replacementPayload = workoutEnvelopeJson(
        entityId: 'session-p3-3',
        revision: 2,
        exercises: [
          exerciseWithWireId(
            exerciseB,
            'Squat',
            wireId: 'watch_exercise_brand-new',
          ),
        ],
      );
      await emitWorkoutUpdated(replacementPayload);
      await pumpEventQueue();

      final rowsAfter = await repo.watchSessionExercises(session.id).first;
      expect(rowsAfter, hasLength(1));
      expect(
        rowsAfter.single.id,
        isNot(originalRowId),
        reason:
            'an unrecognized wireId must not be mistaken for the slot the '
            'old exercise vacated',
      );
      expect(rowsAfter.single.exerciseId, exerciseB);
    },
  );

  test(
    'deleting the middle set of three (ID-based) leaves the other two sets '
    'with their original identity and data',
    () async {
      buildService();
      final exerciseA = await createExercise('Bench Press');

      final firstPayload = workoutEnvelopeJson(
        entityId: 'session-p3-4',
        revision: 1,
        exercises: [
          exerciseWithWireId(
            exerciseA,
            'Bench Press',
            sets: [
              setWithWireId(weight: 10, reps: 8),
              setWithWireId(weight: 20, reps: 8),
              setWithWireId(weight: 30, reps: 8),
            ],
          ),
        ],
      );
      await emitWorkoutUpdated(firstPayload);
      await pumpEventQueue();

      final session = await repo.watchActiveSession().first;
      final workoutExerciseId =
          (await repo.watchSessionExercises(session!.id).first).single.id;
      final setsAfterFirst = await repo
          .watchSetsForWorkoutExercise(workoutExerciseId)
          .first;
      expect(setsAfterFirst, hasLength(3));
      final set1Id = setsAfterFirst[0].id;
      final set3Id = setsAfterFirst[2].id;

      // Watch deletes the middle set and echoes back the phone-assigned
      // wireIds for the exercise and the two sets that remain.
      final secondPayload = workoutEnvelopeJson(
        entityId: 'session-p3-4',
        revision: 2,
        exercises: [
          exerciseWithWireId(
            exerciseA,
            'Bench Press',
            wireId: 'exercise_$workoutExerciseId',
            sets: [
              setWithWireId(weight: 10, reps: 8, wireId: 'set_$set1Id'),
              setWithWireId(weight: 30, reps: 8, wireId: 'set_$set3Id'),
            ],
          ),
        ],
      );
      await emitWorkoutUpdated(secondPayload);
      await pumpEventQueue();

      final setsAfterSecond = await repo
          .watchSetsForWorkoutExercise(workoutExerciseId)
          .first;
      expect(
        setsAfterSecond.map((s) => s.id).toSet(),
        {set1Id, set3Id},
        reason:
            'the surviving sets must keep their original row identity — '
            'positional matching would have overwritten the second set\'s '
            'row with the third set\'s weight and deleted the real third '
            'set',
      );
      expect(setsAfterSecond.map((s) => s.weightKg).toList(), [10.0, 30.0]);
    },
  );

  test(
    'inserting a new set in the middle of the list does not disturb the '
    'existing sets around it',
    () async {
      buildService();
      final exerciseA = await createExercise('Bench Press');

      final firstPayload = workoutEnvelopeJson(
        entityId: 'session-p3-5',
        revision: 1,
        exercises: [
          exerciseWithWireId(
            exerciseA,
            'Bench Press',
            sets: [
              setWithWireId(weight: 10, reps: 8),
              setWithWireId(weight: 30, reps: 8),
            ],
          ),
        ],
      );
      await emitWorkoutUpdated(firstPayload);
      await pumpEventQueue();

      final session = await repo.watchActiveSession().first;
      final workoutExerciseId =
          (await repo.watchSessionExercises(session!.id).first).single.id;
      final setsAfterFirst = await repo
          .watchSetsForWorkoutExercise(workoutExerciseId)
          .first;
      final set1Id = setsAfterFirst[0].id;
      final set2Id = setsAfterFirst[1].id;

      // Watch inserts a new set between the two existing ones and echoes
      // back the phone-assigned wireIds for the two originals.
      final secondPayload = workoutEnvelopeJson(
        entityId: 'session-p3-5',
        revision: 2,
        exercises: [
          exerciseWithWireId(
            exerciseA,
            'Bench Press',
            wireId: 'exercise_$workoutExerciseId',
            sets: [
              setWithWireId(weight: 10, reps: 8, wireId: 'set_$set1Id'),
              setWithWireId(weight: 20, reps: 8, wireId: 'watch_set_new'),
              setWithWireId(weight: 30, reps: 8, wireId: 'set_$set2Id'),
            ],
          ),
        ],
      );
      await emitWorkoutUpdated(secondPayload);
      await pumpEventQueue();

      final setsAfterSecond = await repo
          .watchSetsForWorkoutExercise(workoutExerciseId)
          .first;
      expect(setsAfterSecond, hasLength(3));
      final byId = {for (final s in setsAfterSecond) s.id: s};
      expect(byId[set1Id]?.weightKg, 10.0);
      expect(byId[set2Id]?.weightKg, 30.0);
      final newSet = setsAfterSecond.firstWhere(
        (s) => s.id != set1Id && s.id != set2Id,
      );
      expect(newSet.weightKg, 20.0);
    },
  );
}
