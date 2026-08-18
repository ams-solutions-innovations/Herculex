import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/data/sync/sync_service.dart';

import '../support/test_database.dart';
import 'fake_sync_backend_service.dart';

/// Covers the catalogue/band FK payload paths in
/// `SyncService._buildRemotePayload` and `SyncIdResolver`, which
/// `sync_service_test.dart` never reaches — almost every test there drives
/// `gyms`, a table with no FK fields at all, so ~35 of the 36 table specs
/// were exercised only by the one shape that has nothing interesting in it.
///
/// The interesting rule: a reference to a catalogue table travels as a
/// `sync_uuid` when it points at a **custom** row and as a stable natural key
/// (slug / catalogue_id / kind / colour+tension) when it points at a
/// **seeded** one, because seeded rows are never pushed but exist identically
/// on every device from the same bundled assets. Postgres enforces
/// exactly-one-of via a `check` constraint, so getting this wrong is a hard
/// push failure, not a cosmetic one.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The two-device tests below deliberately open a second `AppDatabase`.
  // Drift's warning is about two instances sharing one `QueryExecutor`; these
  // have separate in-memory ones, which is the whole point.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late FakeSyncBackendService backend;
  late SyncService sync;
  const userId = 'user-1';

  setUp(() async {
    db = await openTestDatabase();
    backend = FakeSyncBackendService();
    sync = SyncService(db: db, backend: backend);
  });

  tearDown(() async {
    await sync.dispose();
    backend.close();
    await db.close();
  });

  /// The payload the backend actually received for [table].
  Map<String, dynamic> pushed(String table) =>
      backend.upsertCalls.lastWhere((c) => c.$1 == table).$2;

  Future<String> uuidOf(String table, int id) async {
    final row = await db
        .customSelect(
          'SELECT sync_uuid FROM $table WHERE id = ?',
          variables: [Variable(id)],
        )
        .getSingle();
    return row.data['sync_uuid'] as String;
  }

  Future<int> insertExercise(
    AppDatabase into, {
    required String name,
    String? slug,
    required bool isCustom,
  }) {
    return into
        .into(into.exerciseCatalog)
        .insert(
          ExerciseCatalogCompanion.insert(
            name: name,
            primaryMuscle: 'Quads',
            equipment: 'Barbell',
            mechanics: 'compound',
            force: 'push',
            plane: 'axial',
            slug: Value(slug),
            isCustom: Value(isCustom),
          ),
        );
  }

  Future<int> insertBand(
    AppDatabase into, {
    required String name,
    required String color,
    required double tensionKg,
    required bool isCustom,
  }) {
    return into
        .into(into.bands)
        .insert(
          BandsCompanion.insert(
            name: name,
            color: color,
            tensionKg: tensionKg,
            isCustom: Value(isCustom),
          ),
        );
  }

  /// `set_bands` sits four levels down. Returns the new set entry's local id.
  Future<int> insertSetEntry(AppDatabase into, {required int exerciseId}) async {
    final sessionId = await into
        .into(into.workoutSessions)
        .insert(WorkoutSessionsCompanion.insert(startedAt: DateTime.now()));
    final workoutExerciseId = await into
        .into(into.workoutExercises)
        .insert(
          WorkoutExercisesCompanion.insert(
            sessionId: sessionId,
            exerciseId: exerciseId,
            orderIndex: 0,
          ),
        );
    return into
        .into(into.setEntries)
        .insert(
          SetEntriesCompanion.insert(
            workoutExerciseId: workoutExerciseId,
            setIndex: 0,
            weightKg: 100,
            reps: 5,
          ),
        );
  }

  Future<int> insertMicroWorkout(AppDatabase into, {required int exerciseId}) {
    return into
        .into(into.microWorkouts)
        .insert(
          MicroWorkoutsCompanion.insert(
            name: 'Daily squats',
            exerciseId: exerciseId,
            targetReps: 30,
          ),
        );
  }

  group('CatalogueFk push', () {
    test('a reference to a seeded row travels as its natural key', () async {
      await sync.start(userId);
      // Seeded: `is_custom = 0`, so the outbox trigger's `AND NEW.is_custom
      // = 1` guard suppresses it and the catalogue row itself never leaves
      // the device — only the reference to it does.
      final exerciseId = await insertExercise(
        db,
        name: 'Back Squat',
        slug: 'back-squat',
        isCustom: false,
      );
      await insertMicroWorkout(db, exerciseId: exerciseId);
      await sync.pushOnce();

      expect(
        backend.upsertCalls.map((c) => c.$1),
        isNot(contains('exercise_catalog')),
        reason: 'seeded catalogue rows must never reach the cloud',
      );
      final row = pushed('micro_workouts');
      expect(row['exercise_slug'], 'back-squat');
      expect(row['exercise_catalog_id'], isNull);
    });

    test('a reference to a custom row travels as its sync_uuid', () async {
      await sync.start(userId);
      final exerciseId = await insertExercise(
        db,
        name: 'Zercher Good Morning',
        isCustom: true,
      );
      await insertMicroWorkout(db, exerciseId: exerciseId);
      await sync.pushOnce();

      final row = pushed('micro_workouts');
      expect(row['exercise_catalog_id'], await uuidOf('exercise_catalog', exerciseId));
      expect(row['exercise_slug'], isNull);
    });

    test('the custom parent is pushed before the child that references it',
        () async {
      await sync.start(userId);
      final exerciseId = await insertExercise(
        db,
        name: 'Zercher Good Morning',
        isCustom: true,
      );
      await insertMicroWorkout(db, exerciseId: exerciseId);
      await sync.pushOnce();

      final order = backend.upsertCalls.map((c) => c.$1).toList();
      expect(
        order.indexOf('exercise_catalog'),
        lessThan(order.indexOf('micro_workouts')),
        reason: 'Postgres FKs reject the child otherwise',
      );
    });

    test('a null reference sends both catalogue columns as null', () async {
      await sync.start(userId);
      // `food_entries.food_id` is nullable — a recipe entry has no catalogue
      // food behind it at all. Both remote columns must still be *present*
      // and null, or the upsert would silently leave a stale value in place.
      await db
          .into(db.foodEntries)
          .insert(
            FoodEntriesCompanion.insert(dateIso: '2026-08-12', meal: 'lunch'),
          );
      await sync.pushOnce();

      final row = pushed('food_entries');
      expect(row.containsKey('food_catalogue_id'), isTrue);
      expect(row.containsKey('food_catalogue_ref'), isTrue);
      expect(row['food_catalogue_id'], isNull);
      expect(row['food_catalogue_ref'], isNull);
    });

    test('a seeded food travels as its catalogue_id', () async {
      await sync.start(userId);
      final foodId = await db
          .into(db.foods)
          .insert(
            FoodsCompanion.insert(
              name: 'Oats',
              kcalPer100g: 389,
              catalogueId: const Value('off:1234567890'),
              isCustom: const Value(false),
            ),
          );
      await db
          .into(db.foodEntries)
          .insert(
            FoodEntriesCompanion.insert(
              dateIso: '2026-08-12',
              meal: 'breakfast',
              foodId: Value(foodId),
            ),
          );
      await sync.pushOnce();

      expect(
        backend.upsertCalls.map((c) => c.$1),
        isNot(contains('foods')),
        reason: 'seeded foods are never pushed',
      );
      final row = pushed('food_entries');
      expect(row['food_catalogue_ref'], 'off:1234567890');
      expect(row['food_catalogue_id'], isNull);
    });

    test('a custom food travels as its sync_uuid', () async {
      await sync.start(userId);
      final foodId = await db
          .into(db.foods)
          .insert(
            FoodsCompanion.insert(
              name: 'Nonna\'s ragu',
              kcalPer100g: 210,
              isCustom: const Value(true),
            ),
          );
      await db
          .into(db.foodEntries)
          .insert(
            FoodEntriesCompanion.insert(
              dateIso: '2026-08-12',
              meal: 'dinner',
              foodId: Value(foodId),
            ),
          );
      await sync.pushOnce();

      final row = pushed('food_entries');
      expect(row['food_catalogue_id'], await uuidOf('foods', foodId));
      expect(row['food_catalogue_ref'], isNull);
    });
  });

  group('CatalogueFk pull', () {
    test('a natural key resolves to this device\'s own local id', () async {
      // The receiving device has the same seeded exercise under a *different*
      // autoincrement id — that mismatch is the entire reason the natural key
      // exists.
      await insertExercise(db, name: 'Filler', slug: 'filler', isCustom: false);
      final localExerciseId = await insertExercise(
        db,
        name: 'Back Squat',
        slug: 'back-squat',
        isCustom: false,
      );
      backend.seedRemoteRow('micro_workouts', {
        'id': 'remote-mw-1',
        'user_id': userId,
        'name': 'Daily squats',
        'exercise_catalog_id': null,
        'exercise_slug': 'back-squat',
        'target_reps': 30,
        'times_per_day': 1,
        'active': true,
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'deleted_at': null,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });

      await sync.start(userId);

      final row = await db
          .customSelect(
            "SELECT exercise_id FROM micro_workouts WHERE sync_uuid = 'remote-mw-1'",
          )
          .getSingle();
      expect(row.data['exercise_id'], localExerciseId);
      expect(localExerciseId, isNot(1), reason: 'ids must genuinely differ');
    });
  });

  group('BandFk', () {
    test('a seeded band travels as colour + tension, not a uuid', () async {
      await sync.start(userId);
      final exerciseId =
          await insertExercise(db, name: 'Squat', slug: 'squat', isCustom: false);
      final setEntryId = await insertSetEntry(db, exerciseId: exerciseId);
      final bandId = await insertBand(
        db,
        name: 'Red',
        color: 'red',
        tensionKg: 12.5,
        isCustom: false,
      );
      await db
          .into(db.setBands)
          .insert(SetBandsCompanion.insert(setEntryId: setEntryId, bandId: bandId));
      await sync.pushOnce();

      final row = pushed('set_bands');
      expect(row['band_id'], isNull);
      expect(row['band_color'], 'red');
      expect(row['band_tension_kg'], 12.5);
    });

    test('a custom band travels as a uuid with no natural key', () async {
      await sync.start(userId);
      final exerciseId =
          await insertExercise(db, name: 'Squat', slug: 'squat', isCustom: false);
      final setEntryId = await insertSetEntry(db, exerciseId: exerciseId);
      final bandId = await insertBand(
        db,
        name: 'Homemade',
        color: 'teal',
        tensionKg: 31.0,
        isCustom: true,
      );
      await db
          .into(db.setBands)
          .insert(SetBandsCompanion.insert(setEntryId: setEntryId, bandId: bandId));
      await sync.pushOnce();

      final row = pushed('set_bands');
      expect(row['band_id'], await uuidOf('bands', bandId));
      expect(row['band_color'], isNull);
      expect(row['band_tension_kg'], isNull);
    });

    test('a pulled colour + tension pair resolves to the local band', () async {
      await insertBand(db, name: 'Filler', color: 'grey', tensionKg: 5, isCustom: false);
      final localBandId = await insertBand(
        db,
        name: 'Red',
        color: 'red',
        tensionKg: 12.5,
        isCustom: false,
      );
      final exerciseId =
          await insertExercise(db, name: 'Squat', slug: 'squat', isCustom: false);
      final setEntryId = await insertSetEntry(db, exerciseId: exerciseId);
      final setEntryUuid = await uuidOf('set_entries', setEntryId);

      backend.seedRemoteRow('set_bands', {
        'id': 'remote-sb-1',
        'user_id': userId,
        'set_entry_id': setEntryUuid,
        'band_id': null,
        'band_color': 'red',
        'band_tension_kg': 12.5,
        'count': 2,
        'mode': 'resistance',
        'deleted_at': null,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });

      await sync.start(userId);

      final row = await db
          .customSelect(
            "SELECT band_id, count FROM set_bands WHERE sync_uuid = 'remote-sb-1'",
          )
          .getSingle();
      expect(row.data['band_id'], localBandId);
      expect(row.data['count'], 2);
    });
  });

  group('is_custom crosses the wire', () {
    // Regression for the defect found while closing RB-02: `is_custom` used
    // to be in `localOnlyColumns` on all four catalogue tables, on the
    // reasoning that only custom rows are ever pushed so the flag is
    // redundant. True on the way up, false on the way down — the receiving
    // device's local default is `false`, so a pulled custom row became a
    // seeded one and `resolveCatalogueRefForPush` then took the wrong branch
    // for every child referencing it.
    // See `supabase/migrations/0007_catalogue_is_custom.sql`.

    test('a custom exercise is still custom on the receiving device', () async {
      await sync.start(userId);
      final exerciseId =
          await insertExercise(db, name: 'Zercher Good Morning', isCustom: true);
      await sync.pushOnce();

      expect(pushed('exercise_catalog')['is_custom'], isNotNull,
          reason: 'is_custom must be part of the payload at all');

      // Second device, same account, same fake cloud.
      final dbB = await openTestDatabase();
      final syncB = SyncService(db: dbB, backend: backend);
      addTearDown(() async {
        await syncB.dispose();
        await dbB.close();
      });
      await syncB.start(userId);

      final uuid = await uuidOf('exercise_catalog', exerciseId);
      final onB = await dbB
          .customSelect(
            'SELECT is_custom, slug FROM exercise_catalog WHERE sync_uuid = ?',
            variables: [Variable(uuid)],
          )
          .getSingle();
      expect(onB.data['is_custom'], 1,
          reason: 'a user-created exercise must not arrive as a stock one');
      expect(onB.data['slug'], isNull,
          reason: 'slug stays local-only; custom rows have none anyway');
    });

    test(
      'a child created on the receiving device references the custom parent '
      'by uuid, not by a null natural key',
      () async {
        await sync.start(userId);
        final exerciseId =
            await insertExercise(db, name: 'Zercher Good Morning', isCustom: true);
        await sync.pushOnce();

        final dbB = await openTestDatabase();
        final syncB = SyncService(db: dbB, backend: backend);
        addTearDown(() async {
          await syncB.dispose();
          await dbB.close();
        });
        await syncB.start(userId);

        final uuid = await uuidOf('exercise_catalog', exerciseId);
        final localOnB = await dbB
            .customSelect(
              'SELECT id FROM exercise_catalog WHERE sync_uuid = ?',
              variables: [Variable(uuid)],
            )
            .getSingle();
        await insertMicroWorkout(dbB, exerciseId: localOnB.data['id'] as int);
        await syncB.pushOnce();

        final row = backend.upsertCalls
            .lastWhere((c) => c.$1 == 'micro_workouts')
            .$2;
        // Before the fix this was (null, null), which Postgres rejects on
        // `check ((exercise_catalog_id is not null and exercise_slug is null)
        // or (exercise_catalog_id is null and exercise_slug is not null))`.
        expect(row['exercise_catalog_id'], uuid);
        expect(row['exercise_slug'], isNull);
      },
    );
  });

  group('buddy_session_id', () {
    // Phase 11 Gym Buddy (BUD-02/BUD-07): `buddy_session_id` is a plain
    // nullable text column on the already-synced `workout_sessions` table,
    // with no `SyncTableSpec` entry of its own. This is the concrete check
    // on research assumption A8 — `_buildRemotePayload`'s generic
    // pass-through carries it without any FK/rename/dateTime handling — and
    // it is BUD-07's only dependency on this phase.
    test('buddy_session_id', () async {
      const buddySessionId = 'buddy-session-uuid-1';

      await sync.start(userId);
      await db
          .into(db.workoutSessions)
          .insert(
            WorkoutSessionsCompanion.insert(
              startedAt: DateTime(2026, 8, 18),
              buddySessionId: const Value(buddySessionId),
            ),
          );
      await sync.pushOnce();

      final row = pushed('workout_sessions');
      expect(row['buddy_session_id'], buddySessionId);

      // Pull onto a second device, same account, same fake cloud.
      final dbB = await openTestDatabase();
      final syncB = SyncService(db: dbB, backend: backend);
      addTearDown(() async {
        await syncB.dispose();
        await dbB.close();
      });
      await syncB.start(userId);

      final onB = await dbB
          .customSelect(
            'SELECT buddy_session_id FROM workout_sessions WHERE '
            'sync_uuid = ?',
            variables: [
              Variable(await uuidOf('workout_sessions', 1)),
            ],
          )
          .getSingle();
      expect(onB.data['buddy_session_id'], buddySessionId);
    });
  });
}
