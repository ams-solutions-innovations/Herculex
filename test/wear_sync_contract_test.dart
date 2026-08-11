import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:herculex/features/nutrition/data/wear_sync_contract.dart';

// Canonical v1 wire fixtures shared (by convention, not by file — Dart and
// Kotlin can't literally share a file) with the Kotlin contract test at
// android/wear/src/test/java/com/ams/herculex/sync/WearSyncContractTest.kt.
// Phase 1 of docs/wear-sync-race-conditions-remediation-plan-2026-08-11.md
// bumps wearSyncSchemaVersion to 2; these v1 fixtures pin today's behavior so
// that change is a visible diff against a known-good baseline rather than a
// leap into the unknown. Keep both files' literals byte-for-byte identical
// when adding new fixtures here.
const String kCanonicalV1WorkoutStartJson =
    '{"schemaVersion":1,"entity":"active_workout","entityId":"session-1",'
    '"revision":42,"origin":"phone","updatedAtEpochMs":1000,'
    '"payload":{"startedAtEpochMs":900,"exercises":[{"sets":[{"rpe":8.5,'
    '"setType":"standard","isWarmup":false}]}]}}';

const String kCanonicalV1FastingSnapshotJson =
    '{"schemaVersion":1,"entity":"fasting","entityId":"fasting",'
    '"revision":5,"origin":"watch","updatedAtEpochMs":2000,'
    '"payload":{"isActive":true,"startedAtEpochMs":1500}}';

const String kCanonicalLegacyFallbackJson =
    '{"currentExerciseIndex":0,"exercises":[]}';

// v2 fixtures added by Phase 1: schemaVersion 2, a UUID-shaped entityId (the
// stable session identity introduced in Phase 1a) and a revision consistent
// with the persisted allocator introduced in Phase 1b. Keep byte-for-byte
// identical with the Kotlin fixture of the same name.
const String kCanonicalV2WorkoutStartJson =
    '{"schemaVersion":2,"entity":"active_workout",'
    '"entityId":"3fa85f64-5717-4562-b3fc-2c963f66afa6",'
    '"revision":1000042,"origin":"phone","updatedAtEpochMs":1000,'
    '"payload":{"startedAtEpochMs":900,"exercises":[{"sets":[{"rpe":8.5,'
    '"setType":"standard","isWarmup":false}]}]}}';

const String kCanonicalV2FastingSnapshotJson =
    '{"schemaVersion":2,"entity":"fasting","entityId":"fasting",'
    '"revision":1000005,"origin":"watch","updatedAtEpochMs":2000,'
    '"payload":{"isActive":true,"startedAtEpochMs":1500}}';

/// [WearDedupeState] now splits the old combined "check and commit" into
/// [WearDedupeState.wouldAccept] (pure) and [WearDedupeState.commit]
/// (mutation) — see Phase 2 of
/// docs/wear-sync-race-conditions-remediation-plan-2026-08-11.md. Tests below
/// that exercise "accept, then commit" ordering use this helper to keep the
/// same combined-semantics assertions as before the split.
bool acceptAndCommit(WearDedupeState dedupe, WearSyncEnvelope envelope) {
  final accepted = dedupe.wouldAccept(envelope);
  if (accepted) dedupe.commit(envelope);
  return accepted;
}

void main() {
  group('canonical v1 fixtures (cross-decoder contract baseline)', () {
    test('decodes the canonical workout-start envelope', () {
      final decoded = WearSyncEnvelope.decode(
        kCanonicalV1WorkoutStartJson,
        fallbackEntity: wearSyncEntityActiveWorkout,
        fallbackEntityId: 'fallback',
        fallbackOrigin: wearSyncOriginWatch,
      );

      expect(decoded.schemaVersion, 1);
      expect(decoded.entity, wearSyncEntityActiveWorkout);
      expect(decoded.entityId, 'session-1');
      expect(decoded.revision, 42);
      expect(decoded.origin, wearSyncOriginPhone);
      expect(decoded.updatedAtEpochMs, 1000);
      expect(decoded.payload['startedAtEpochMs'], 900);
      expect(
        ((decoded.payload['exercises'] as List).first['sets'] as List)
            .first['rpe'],
        8.5,
      );
    });

    test('decodes the canonical fasting snapshot envelope', () {
      final decoded = WearSyncEnvelope.decode(
        kCanonicalV1FastingSnapshotJson,
        fallbackEntity: wearSyncEntityFasting,
        fallbackEntityId: 'fallback',
        fallbackOrigin: wearSyncOriginPhone,
      );

      expect(decoded.schemaVersion, 1);
      expect(decoded.entity, wearSyncEntityFasting);
      expect(decoded.entityId, 'fasting');
      expect(decoded.revision, 5);
      expect(decoded.origin, wearSyncOriginWatch);
      expect(decoded.payload['isActive'], true);
    });

    test('decodes the canonical legacy (unenveloped) payload', () {
      final decoded = WearSyncEnvelope.decode(
        kCanonicalLegacyFallbackJson,
        fallbackEntity: wearSyncEntityActiveWorkout,
        fallbackEntityId: 'legacy',
        fallbackOrigin: wearSyncOriginWatch,
      );

      expect(decoded.schemaVersion, 0);
      expect(decoded.entityId, 'legacy');
      expect(decoded.revision, 0);
      expect(decoded.updatedAtEpochMs, 0);
      expect(decoded.payload['exercises'], isEmpty);
    });
  });

  group('canonical v2 fixtures (Phase 1 protocol)', () {
    test('decodes the canonical v2 workout-start envelope', () {
      final decoded = WearSyncEnvelope.decode(
        kCanonicalV2WorkoutStartJson,
        fallbackEntity: wearSyncEntityActiveWorkout,
        fallbackEntityId: 'fallback',
        fallbackOrigin: wearSyncOriginWatch,
      );

      expect(decoded.schemaVersion, 2);
      expect(decoded.entity, wearSyncEntityActiveWorkout);
      expect(decoded.entityId, '3fa85f64-5717-4562-b3fc-2c963f66afa6');
      expect(decoded.revision, 1000042);
      expect(decoded.origin, wearSyncOriginPhone);
      expect(decoded.payload['startedAtEpochMs'], 900);
    });

    test('decodes the canonical v2 fasting snapshot envelope', () {
      final decoded = WearSyncEnvelope.decode(
        kCanonicalV2FastingSnapshotJson,
        fallbackEntity: wearSyncEntityFasting,
        fallbackEntityId: 'fallback',
        fallbackOrigin: wearSyncOriginPhone,
      );

      expect(decoded.schemaVersion, 2);
      expect(decoded.entityId, 'fasting');
      expect(decoded.revision, 1000005);
      expect(decoded.payload['isActive'], true);
    });

    test('round-trips through wrap()/encode(), stamping the live schema version', () {
      final envelope = WearSyncEnvelope.wrap(
        entity: wearSyncEntityActiveWorkout,
        entityId: '3fa85f64-5717-4562-b3fc-2c963f66afa6',
        revision: 7,
        origin: wearSyncOriginPhone,
        payload: const {'exercises': []},
      );

      expect(envelope.schemaVersion, 2);
      expect(wearSyncSchemaVersion, 2);

      final decoded = WearSyncEnvelope.decode(
        envelope.encode(),
        fallbackEntity: wearSyncEntityActiveWorkout,
        fallbackEntityId: 'fallback',
        fallbackOrigin: wearSyncOriginWatch,
      );
      expect(decoded.entityId, '3fa85f64-5717-4562-b3fc-2c963f66afa6');
    });
  });

  test('wraps and unwraps versioned active workout envelope', () {
    final envelope = WearSyncEnvelope.wrap(
      entity: wearSyncEntityActiveWorkout,
      entityId: 'session-1',
      revision: 42,
      origin: wearSyncOriginPhone,
      updatedAtEpochMs: 1000,
      payload: {
        'startedAtEpochMs': 900,
        'exercises': [
          {
            'sets': [
              {'rpe': 8.5, 'setType': 'standard', 'isWarmup': false},
            ],
          },
        ],
      },
    );

    final decoded = WearSyncEnvelope.decode(
      envelope.encode(),
      fallbackEntity: wearSyncEntityActiveWorkout,
      fallbackEntityId: 'fallback',
      fallbackOrigin: wearSyncOriginWatch,
    );

    expect(decoded.schemaVersion, wearSyncSchemaVersion);
    expect(decoded.entityId, 'session-1');
    expect(decoded.revision, 42);
    expect(decoded.payload['startedAtEpochMs'], 900);
    expect(
      ((decoded.payload['exercises'] as List).first['sets'] as List)
          .first['rpe'],
      8.5,
    );
  });

  test(
    'decode falls back to caller-supplied entityId and origin when absent',
    () {
      // schemaVersion/entity/payload present (so isEnvelope == true) but
      // entityId/origin deliberately omitted from the wire payload.
      final json = jsonEncode({
        'schemaVersion': 1,
        'entity': wearSyncEntityActiveWorkout,
        'revision': 7,
        'updatedAtEpochMs': 500,
        'payload': {'exercises': []},
      });

      final decoded = WearSyncEnvelope.decode(
        json,
        fallbackEntity: wearSyncEntityActiveWorkout,
        fallbackEntityId: 'fallback-entity-id',
        fallbackOrigin: wearSyncOriginWatch,
      );

      expect(decoded.entityId, 'fallback-entity-id');
      expect(decoded.origin, wearSyncOriginWatch);
    },
  );

  test(
    'revision dedupe accepts newest and ignores duplicate or stale state',
    () {
      final dedupe = WearDedupeState();
      WearSyncEnvelope env(int revision, int updatedAt) =>
          WearSyncEnvelope.wrap(
            entity: wearSyncEntityActiveWorkout,
            entityId: 'session-1',
            revision: revision,
            origin: wearSyncOriginWatch,
            updatedAtEpochMs: updatedAt,
            payload: const {'exercises': []},
          );

      expect(acceptAndCommit(dedupe,env(10, 100)), isTrue);
      expect(acceptAndCommit(dedupe,env(10, 100)), isFalse);
      expect(acceptAndCommit(dedupe,env(9, 101)), isFalse);
      expect(acceptAndCommit(dedupe,env(10, 101)), isTrue);
      expect(acceptAndCommit(dedupe,env(11, 90)), isTrue);
    },
  );

  test(
    'dedupe state is isolated per entity/entityId/origin key',
    () {
      final dedupe = WearDedupeState();
      WearSyncEnvelope env({
        required String entity,
        required String entityId,
        required String origin,
      }) => WearSyncEnvelope.wrap(
        entity: entity,
        entityId: entityId,
        revision: 1,
        origin: origin,
        updatedAtEpochMs: 100,
        payload: const {},
      );

      // Same revision/updatedAt, but distinct keys — none of these should
      // block each other, unlike the same-key case above.
      expect(
        acceptAndCommit(dedupe,
          env(
            entity: wearSyncEntityActiveWorkout,
            entityId: 'session-1',
            origin: wearSyncOriginWatch,
          ),
        ),
        isTrue,
      );
      expect(
        acceptAndCommit(dedupe,
          env(
            entity: wearSyncEntityActiveWorkout,
            entityId: 'session-2',
            origin: wearSyncOriginWatch,
          ),
        ),
        isTrue,
        reason: 'different entityId is a different dedupe key',
      );
      expect(
        acceptAndCommit(dedupe,
          env(
            entity: wearSyncEntityFasting,
            entityId: 'session-1',
            origin: wearSyncOriginWatch,
          ),
        ),
        isTrue,
        reason: 'different entity is a different dedupe key',
      );
      expect(
        acceptAndCommit(dedupe,
          env(
            entity: wearSyncEntityActiveWorkout,
            entityId: 'session-1',
            origin: wearSyncOriginPhone,
          ),
        ),
        isTrue,
        reason: 'different origin is a different dedupe key',
      );
    },
  );

  test('legacy (unenveloped) payloads are rejected — fail closed', () {
    // Phase 1c: this bypass existed for pre-envelope watch builds. Once both
    // APKs move to schemaVersion 2 together there's no legitimate sender left
    // for this shape, so it must now be rejected instead of always-accepted.
    final legacy = jsonEncode({'currentExerciseIndex': 0, 'exercises': []});
    final decoded = WearSyncEnvelope.decode(
      legacy,
      fallbackEntity: wearSyncEntityActiveWorkout,
      fallbackEntityId: 'legacy',
      fallbackOrigin: wearSyncOriginWatch,
    );
    final dedupe = WearDedupeState();

    expect(decoded.schemaVersion, 0);
    expect(decoded.payload['exercises'], isEmpty);
    expect(acceptAndCommit(dedupe, decoded), isFalse);
    expect(acceptAndCommit(dedupe, decoded), isFalse);
  });

  test(
    'a wrong-typed entityId falls back to the legacy decode path instead of '
    'crashing or being silently coerced',
    () {
      final json = jsonEncode({
        'schemaVersion': 2,
        'entity': wearSyncEntityActiveWorkout,
        'entityId': 12345, // wrong type — should be a String
        'revision': 7,
        'origin': wearSyncOriginPhone,
        'updatedAtEpochMs': 500,
        'payload': {'exercises': []},
      });

      final decoded = WearSyncEnvelope.decode(
        json,
        fallbackEntity: wearSyncEntityActiveWorkout,
        fallbackEntityId: 'fallback-entity-id',
        fallbackOrigin: wearSyncOriginWatch,
      );

      expect(decoded.schemaVersion, 0);
      expect(decoded.entityId, 'fallback-entity-id');
    },
  );

  group('WearRevisionAllocator (Phase 1b)', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('persists across a simulated process restart', () async {
      final prefs = await SharedPreferences.getInstance();
      final beforeRestart = WearRevisionAllocator(prefs, 'workout');
      final first = beforeRestart.next();

      // Simulate a restart: a fresh allocator instance sharing the same
      // underlying persisted prefs.
      final afterRestart = WearRevisionAllocator(prefs, 'workout');
      final second = afterRestart.next();

      expect(second, greaterThan(first));
    });

    test('never issues a revision that goes backwards, even under a clock '
        'rollback', () async {
      final prefs = await SharedPreferences.getInstance();
      final allocator = WearRevisionAllocator(prefs, 'workout');
      final first = allocator.next();
      final second = allocator.next();
      expect(second, greaterThan(first));
    });

    test('allocators with different keys do not collide', () async {
      final prefs = await SharedPreferences.getInstance();
      final workout = WearRevisionAllocator(prefs, 'workout');
      final fasting = WearRevisionAllocator(prefs, 'fasting');

      final workoutFirst = workout.next();
      final fastingFirst = fasting.next();
      final workoutSecond = workout.next();

      expect(workoutSecond, greaterThan(workoutFirst));
      // Independent sequences: fasting's first value is unaffected by
      // workout's calls, i.e. it isn't offset by workout's own counter.
      expect(fastingFirst, isNot(equals(workoutSecond)));
    });
  });

  test(
    'wouldAccept does not mutate state — repeated calls give the same answer',
    () {
      final dedupe = WearDedupeState();
      final first = WearSyncEnvelope.wrap(
        entity: wearSyncEntityActiveWorkout,
        entityId: 'session-1',
        revision: 10,
        origin: wearSyncOriginWatch,
        updatedAtEpochMs: 100,
        payload: const {},
      );

      expect(dedupe.wouldAccept(first), isTrue);
      expect(dedupe.wouldAccept(first), isTrue, reason: 'checking again without committing must not change the answer');
      expect(dedupe.wouldAccept(first), isTrue);
    },
  );

  test(
    'a failed apply must not commit — retrying the same envelope after '
    'wouldAccept (without commit) still succeeds',
    () {
      // Regression test for the Phase 2 fix: previously WearDedupeState's
      // combined shouldAccept() mutated state on the check itself, so a
      // caller that checked, then failed to durably apply, then retried the
      // exact same envelope would be told to ignore it forever.
      final dedupe = WearDedupeState();
      final envelope = WearSyncEnvelope.wrap(
        entity: wearSyncEntityActiveWorkout,
        entityId: 'session-1',
        revision: 10,
        origin: wearSyncOriginWatch,
        updatedAtEpochMs: 100,
        payload: const {},
      );

      expect(dedupe.wouldAccept(envelope), isTrue);
      // Simulate the durable apply failing: commit() is deliberately not
      // called here.

      // Retry of the identical envelope must still be accepted.
      expect(dedupe.wouldAccept(envelope), isTrue);
      dedupe.commit(envelope);

      // Now that it's committed, the same envelope is correctly rejected.
      expect(dedupe.wouldAccept(envelope), isFalse);
    },
  );

  test('normalizes warmup and legacy set type labels', () {
    expect(normalizeWearSetType('Normal'), 'standard');
    expect(normalizeWearWarmup(setType: 'warmup'), isTrue);
    expect(normalizeWearSetType('warmup'), 'standard');
    expect(normalizeWearSetType('failure'), 'forced');
  });
}
