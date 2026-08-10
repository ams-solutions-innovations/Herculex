import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/nutrition/data/wear_sync_contract.dart';

void main() {
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

      expect(dedupe.shouldAccept(env(10, 100)), isTrue);
      expect(dedupe.shouldAccept(env(10, 100)), isFalse);
      expect(dedupe.shouldAccept(env(9, 101)), isFalse);
      expect(dedupe.shouldAccept(env(10, 101)), isTrue);
      expect(dedupe.shouldAccept(env(11, 90)), isTrue);
    },
  );

  test('legacy payloads remain backward compatible without revision', () {
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
    expect(dedupe.shouldAccept(decoded), isTrue);
    expect(dedupe.shouldAccept(decoded), isTrue);
  });

  test('normalizes warmup and legacy set type labels', () {
    expect(normalizeWearSetType('Normal'), 'standard');
    expect(normalizeWearWarmup(setType: 'warmup'), isTrue);
    expect(normalizeWearSetType('warmup'), 'standard');
    expect(normalizeWearSetType('failure'), 'forced');
  });
}
