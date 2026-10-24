import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/core/utils/clock.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/nutrition/data/wear_sync_contract.dart';
import 'package:herculex/features/nutrition/data/wear_sync_service.dart';
import 'package:herculex/features/workouts/data/wear_workout_sync_service.dart';
import 'package:herculex/features/workouts/data/workouts_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late WorkoutsRepository repo;
  late ProviderContainer container;
  late WearWorkoutSyncService service;
  late Map<String, dynamic> fixture;

  setUp(() async {
    WearSyncService.resetForTesting();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel(WearSyncService.channelName),
          (_) async => null,
        );
    SharedPreferences.setMockInitialValues({});
    db = await openTestDatabase();
    repo = WorkoutsRepository(db, const SystemClock());
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sharedPreferencesProvider.overrideWithValue(
          await SharedPreferences.getInstance(),
        ),
      ],
    );
    final refProvider = Provider<Ref>((ref) => ref);
    service = WearWorkoutSyncService(
      repo,
      WearSyncService(),
      db,
      container.read(refProvider),
    );
    fixture =
        jsonDecode(File('test/fixtures/watch_sync_v2.json').readAsStringSync())
            as Map<String, dynamic>;
    final catalogId = await db
        .into(db.exerciseCatalog)
        .insert(
          ExerciseCatalogCompanion.insert(
            name: 'Watch Fixture Press',
            slug: const Value('watch-fixture-press'),
            primaryMuscle: 'Chest',
            equipment: 'barbell',
            mechanics: 'compound',
            force: 'push',
            plane: 'horizontal',
          ),
        );
    ((fixture['payload']['exercises'] as List).first['template']
            as Map)['catalogExerciseId'] =
        catalogId;
  });
  tearDown(() async {
    service.dispose();
    container.dispose();
    await db.close();
    WearSyncService.resetForTesting();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel(WearSyncService.channelName),
          null,
        );
  });

  Future<bool> deliver(
    String eventId, {
    String action = 'updated',
    int? revision,
  }) {
    if (revision != null) fixture['revision'] = revision;
    return WearSyncService.onAppleWatchWorkoutEvent!({
      'eventId': eventId,
      'action': action,
      'session_json': jsonEncode(fixture),
    });
  }

  test(
    'shared v2 fixture preserves set identity, fractional RPE and opaque metadata',
    () async {
      expect(await deliver('first'), isTrue);
      expect(await deliver('first'), isTrue);
      final sessions = await db.select(db.workoutSessions).get();
      expect(sessions.length, 1);
      expect(
        sessions.single.startedAt.millisecondsSinceEpoch,
        fixture['payload']['startedAtEpochMs'],
      );
      final sets = await db.select(db.setEntries).get();
      expect(sets.length, 1);
      expect(sets.single.weightKg, 80.5);
      expect(sets.single.rpeX10, 85);
      expect(
        jsonDecode(sets.single.setTypeMetaJson!)['unknownFutureField'],
        isTrue,
      );
      final envelope = WearSyncEnvelope.decode(
        jsonEncode(fixture),
        fallbackEntity: 'active_workout',
        fallbackEntityId: '',
        fallbackOrigin: 'watch',
      );
      expect(envelope.schemaVersion, 2);
    },
  );

  test(
    'final snapshot alone imports an offline workout and later updates cannot reopen it',
    () async {
      fixture['payload']['endedAtEpochMs'] = 1792580400000;
      expect(
        await deliver('finish', action: 'finished', revision: 101),
        isTrue,
      );
      expect(
        (await db.select(db.workoutSessions).get()).single.endedAt,
        isNotNull,
      );
      expect(await deliver('late-start', revision: 102), isTrue);
      expect(await repo.watchActiveSession().first, isNull);
      expect((await db.select(db.setEntries).get()).length, 1);
    },
  );

  test(
    'unrelated active phone workout is preserved through offline watch import',
    () async {
      final phoneId = await repo.startSession(sessionUuid: 'phone-existing');
      expect(await deliver('watch-start'), isTrue);
      expect((await repo.watchActiveSession().first)?.id, phoneId);
      expect((await db.select(db.workoutSessions).get()).length, 1);
      fixture['payload']['endedAtEpochMs'] = 1792580400000;
      expect(
        await deliver('watch-end', action: 'finished', revision: 101),
        isTrue,
      );
      expect((await repo.watchActiveSession().first)?.id, phoneId);
      expect((await db.select(db.workoutSessions).get()).length, 2);
    },
  );

  test(
    'discard tombstone prevents an older delivered start from resurrecting a workout',
    () async {
      expect(
        await deliver('discard', action: 'discarded', revision: 110),
        isTrue,
      );
      expect(await deliver('late', revision: 100), isTrue);
      expect(await db.select(db.workoutSessions).get(), isEmpty);
    },
  );

  test(
    'failed apply has no receipt or partial session and can be retried',
    () async {
      final exercise = fixture['payload']['exercises'][0] as Map;
      final original = exercise['sets'];
      exercise['sets'] = 'invalid';
      expect(await deliver('retry'), isFalse);
      expect(await db.select(db.workoutSessions).get(), isEmpty);
      expect(
        await db.customSelect('SELECT * FROM processed_watch_commands').get(),
        isEmpty,
      );
      exercise['sets'] = original;
      expect(await deliver('retry'), isTrue);
      expect((await db.select(db.workoutSessions).get()).length, 1);
    },
  );

  test(
    'HealthKit confirmation after workout completion updates export without reopening',
    () async {
      fixture['payload']['endedAtEpochMs'] = 1792580400000;
      await deliver('finish', action: 'finished');
      fixture['payload']['healthExport'] = {
        'owner': 'watch',
        'status': 'saved',
        'healthKitUuid': 'health-uuid',
      };
      expect(
        await deliver('health', action: 'healthSaved', revision: 101),
        isTrue,
      );
      final health = await db
          .customSelect('SELECT * FROM watch_health_exports')
          .getSingle();
      expect(health.data['healthkit_uuid'], 'health-uuid');
      expect(health.data['status'], 'saved');
      expect(await repo.watchActiveSession().first, isNull);
    },
  );

  test(
    'watch cannot take HealthKit ownership after the phone reserved export',
    () async {
      await db.customStatement(
        'INSERT INTO watch_health_exports (entity_id, owner, status) VALUES (?, ?, ?)',
        [fixture['entityId'], 'phone', 'saved'],
      );
      expect(await deliver('claim', action: 'healthClaim'), isTrue);
      final health = await db
          .customSelect('SELECT * FROM watch_health_exports')
          .getSingle();
      expect(health.data['owner'], 'phone');
    },
  );
}
