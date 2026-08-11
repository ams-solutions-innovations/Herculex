import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/core/clock.dart';
import 'package:herculex/data/local/accessory_seed.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/gyms/data/gyms_repository.dart';
import 'package:herculex/features/measurements/data/measurements_repository.dart';
import 'package:herculex/features/workouts/data/accessories_repository.dart';
import 'package:herculex/features/workouts/data/workouts_repository.dart';

import 'support/test_database.dart';

class _FixedClock implements Clock {
  final DateTime fixed;
  _FixedClock(this.fixed);
  @override
  DateTime now() => fixed;
}

/// In-memory database for v10 schema tests. The first statement triggers the
/// real onCreate path (createAll + asset importer + accessory seed), so these
/// tests also prove the fresh-install path end to end.
Future<AppDatabase> _openDb() => openTestDatabase();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;

  setUp(() async => db = await _openDb());
  tearDown(() async => db.close());

  group('v10 seed', () {
    test(
      'seeds 6 default accessories with fat grips forearm multiplier > 1',
      () async {
        final rows = await db.select(db.accessories).get();
        expect(rows, hasLength(6));
        final fatGrips = rows.singleWhere((a) => a.kind == 'fat_grips');
        expect(fatGrips.forearmMultiplier, greaterThan(1.0));
        expect(rows.every((a) => !a.isCustom), isTrue);
      },
    );

    test('seeds common bands ordered by tension', () async {
      final rows = await db.select(db.bands).get();
      expect(rows, hasLength(6));
      expect(rows.any((b) => b.color == 'green' && b.tensionKg == 20), isTrue);
    });

    test('re-running the seed does not duplicate', () async {
      await AccessorySeed.run(db);
      expect(await db.select(db.accessories).get(), hasLength(6));
      expect(await db.select(db.bands).get(), hasLength(6));
    });
  });

  group('gyms', () {
    test('create/setDefault keeps exactly one default', () async {
      final repo = GymsRepository(db);
      final a = await repo.createGym('Home Gym', isDefault: true);
      final b = await repo.createGym('Commercial Gym');
      await repo.setDefaultGym(b);
      final gyms = await db.select(db.gyms).get();
      expect(gyms.where((g) => g.isDefault).map((g) => g.id), [b]);
      expect(gyms.any((g) => g.id == a && !g.isDefault), isTrue);
    });

    test(
      'deleting a gym null-tags its sessions instead of deleting them',
      () async {
        final gymsRepo = GymsRepository(db);
        final clock = _FixedClock(DateTime(2026, 6, 12, 10));
        final workouts = WorkoutsRepository(db, clock);
        final gymId = await gymsRepo.createGym('Gym B');
        final sessionId = await workouts.startSession(gymId: gymId);
        await gymsRepo.deleteGym(gymId);
        final session = await (db.select(
          db.workoutSessions,
        )..where((t) => t.id.equals(sessionId))).getSingle();
        expect(session.gymId, isNull);
      },
    );
  });

  group('linked workout exercises', () {
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

    test('links exercises into a superset group and reorders them', () async {
      final workouts = WorkoutsRepository(
        db,
        _FixedClock(DateTime(2026, 7, 30)),
      );
      final sessionId = await workouts.startSession();
      final bench = await createExercise('Test Bench');
      final row = await createExercise('Test Row');
      final curl = await createExercise('Test Curl');

      final benchWe = await workouts.addExerciseToSession(
        sessionId: sessionId,
        exerciseId: bench,
      );
      final rowWe = await workouts.addExerciseToSession(
        sessionId: sessionId,
        exerciseId: row,
      );
      final curlWe = await workouts.addExerciseToSession(
        sessionId: sessionId,
        exerciseId: curl,
      );

      await workouts.linkWorkoutExercises(
        sessionId: sessionId,
        sourceWorkoutExerciseId: benchWe,
        targetWorkoutExerciseId: rowWe,
      );
      await workouts.linkWorkoutExercises(
        sessionId: sessionId,
        sourceWorkoutExerciseId: rowWe,
        targetWorkoutExerciseId: curlWe,
      );

      var rows =
          await (db.select(db.workoutExercises)
                ..where((t) => t.sessionId.equals(sessionId))
                ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
              .get();
      expect(rows.map((r) => r.supersetGroup).toSet(), hasLength(1));

      await workouts.reorderWorkoutExercises(
        sessionId: sessionId,
        oldIndex: 2,
        newIndex: 0,
      );

      rows =
          await (db.select(db.workoutExercises)
                ..where((t) => t.sessionId.equals(sessionId))
                ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]))
              .get();
      expect(rows.map((r) => r.id), [curlWe, benchWe, rowWe]);
      expect(rows.map((r) => r.orderIndex), [0, 1, 2]);

      await workouts.unlinkWorkoutExercise(benchWe);
      final unlinked = await (db.select(
        db.workoutExercises,
      )..where((t) => t.id.equals(benchWe))).getSingle();
      expect(unlinked.supersetGroup, isNull);
    });
  });

  group('set variants & accessories', () {
    late WorkoutsRepository workouts;
    late int workoutExerciseId;

    setUp(() async {
      workouts = WorkoutsRepository(db, _FixedClock(DateTime(2026, 6, 12)));
      final exerciseId = await db
          .into(db.exerciseCatalog)
          .insert(
            ExerciseCatalogCompanion.insert(
              name: 'Test Weighted Pull-Up (v10)',
              primaryMuscle: 'Back',
              equipment: 'Bodyweight',
              mechanics: 'compound',
              force: 'pull',
              plane: 'vertical',
              modality: const Value('bodyweight'),
              supportsWeightedBodyweight: const Value(true),
            ),
          );
      final sessionId = await workouts.startSession();
      workoutExerciseId = await workouts.addExerciseToSession(
        sessionId: sessionId,
        exerciseId: exerciseId,
        equipmentVariant: 'bodyweight',
      );
    });

    test('logs set type metadata and bodyweight snapshot', () async {
      final setId = await workouts.addSet(
        workoutExerciseId: workoutExerciseId,
        weightKg: 25,
        reps: 8,
        setType: 'pause',
        setTypeMetaJson: '{"pauseSeconds":3}',
        bodyweightKg: 80,
      );
      final set = await (db.select(
        db.setEntries,
      )..where((t) => t.id.equals(setId))).getSingle();
      expect(set.setType, 'pause');
      expect(set.setTypeMetaJson, contains('pauseSeconds'));
      expect(set.bodyweightKg, 80);
    });

    test('old-style addSet defaults to a standard set', () async {
      final setId = await workouts.addSet(
        workoutExerciseId: workoutExerciseId,
        weightKg: 100,
        reps: 5,
      );
      final set = await (db.select(
        db.setEntries,
      )..where((t) => t.id.equals(setId))).getSingle();
      expect(set.setType, 'standard');
      expect(set.bodyweightKg, isNull);
      expect(set.chainsKg, isNull);
    });

    test(
      'accessory toggle attaches and detaches; copy carries forward',
      () async {
        final accessoriesRepo = AccessoriesRepository(db);
        final belt = (await db.select(db.accessories).get()).singleWhere(
          (a) => a.kind == 'belt',
        );
        final set1 = await workouts.addSet(
          workoutExerciseId: workoutExerciseId,
          weightKg: 100,
          reps: 5,
        );
        expect(
          await accessoriesRepo.toggleSetAccessory(
            setEntryId: set1,
            accessoryId: belt.id,
          ),
          isTrue,
        );
        final set2 = await workouts.addSet(
          workoutExerciseId: workoutExerciseId,
          weightKg: 100,
          reps: 5,
        );
        await accessoriesRepo.copySetAccessories(
          fromSetId: set1,
          toSetId: set2,
        );
        expect(
          await (db.select(
            db.setAccessories,
          )..where((t) => t.setEntryId.equals(set2))).get(),
          hasLength(1),
        );
        expect(
          await accessoriesRepo.toggleSetAccessory(
            setEntryId: set1,
            accessoryId: belt.id,
          ),
          isFalse,
        );
      },
    );

    test('bands attach with mode and cascade-delete with the set', () async {
      final accessoriesRepo = AccessoriesRepository(db);
      final green = (await db.select(db.bands).get()).singleWhere(
        (b) => b.color == 'green',
      );
      final setId = await workouts.addSet(
        workoutExerciseId: workoutExerciseId,
        weightKg: 60,
        reps: 5,
      );
      await accessoriesRepo.attachBand(
        setEntryId: setId,
        bandId: green.id,
        count: 2,
        isResistance: true,
      );
      expect(await db.select(db.setBands).get(), hasLength(1));
      await workouts.deleteSet(setId);
      expect(await db.select(db.setBands).get(), isEmpty);
    });

    test('machine config saves per gym and recalls with fallback', () async {
      final gymId = await GymsRepository(db).createGym('Gym A');
      await workouts.setMachineConfig(
        workoutExerciseId: workoutExerciseId,
        settingsJson: '{"seat":"6"}',
        gymId: gymId,
      );
      final we = await (db.select(
        db.workoutExercises,
      )..where((t) => t.id.equals(workoutExerciseId))).getSingle();
      expect(we.machineConfigJson, '{"seat":"6"}');
      final recalled = await workouts.recallMachineConfig(
        exerciseId: we.exerciseId,
        gymId: gymId,
      );
      expect(recalled?.settingsJson, '{"seat":"6"}');
      // Different gym, no gym-agnostic config → nothing recalled.
      final otherGym = await GymsRepository(db).createGym('Gym B');
      expect(
        await workouts.recallMachineConfig(
          exerciseId: we.exerciseId,
          gymId: otherGym,
        ),
        isNull,
      );
    });
  });

  group('measurements', () {
    test('one sample per metric per day; latest bodyweight wins', () async {
      final repo = MeasurementsRepository(db);
      await repo.logMeasurement(
        dateIso: '2026-06-10',
        metric: 'bodyweight',
        value: 81,
      );
      await repo.logMeasurement(
        dateIso: '2026-06-12',
        metric: 'bodyweight',
        value: 80,
      );
      // Re-log same day overwrites.
      await repo.logMeasurement(
        dateIso: '2026-06-12',
        metric: 'bodyweight',
        value: 80.4,
      );
      final all = await db.select(db.bodyMeasurements).get();
      expect(all, hasLength(2));
      expect(await repo.latestBodyweightKg(), 80.4);
    });
  });
}
