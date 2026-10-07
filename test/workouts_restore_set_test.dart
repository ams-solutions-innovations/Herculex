import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/core/utils/clock.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/workouts/data/workouts_repository.dart';

import 'support/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'WorkoutsRepository deleteSet and restoreSet restores set with accessories and bands',
    () async {
      final db = await openTestDatabase();
      addTearDown(db.close);
      final repo = WorkoutsRepository(db, const SystemClock());

      final exerciseRow = await (db.select(
        db.exerciseCatalog,
      )..limit(1)).getSingle();
      final exerciseId = exerciseRow.id;

      final accessoryId = await db
          .into(db.accessories)
          .insert(AccessoriesCompanion.insert(name: 'Belt', kind: 'belt'));

      final bandId = await db
          .into(db.bands)
          .insert(
            BandsCompanion.insert(
              name: 'Red band',
              color: 'red',
              tensionKg: 20,
            ),
          );

      final sessionId = await db
          .into(db.workoutSessions)
          .insert(
            WorkoutSessionsCompanion.insert(startedAt: DateTime(2026, 8, 30)),
          );

      final weId = await db
          .into(db.workoutExercises)
          .insert(
            WorkoutExercisesCompanion.insert(
              sessionId: sessionId,
              exerciseId: exerciseId,
              orderIndex: 0,
            ),
          );

      final setId = await repo.addSet(
        workoutExerciseId: weId,
        weightKg: 100.0,
        reps: 5,
      );

      await db
          .into(db.setBands)
          .insert(
            SetBandsCompanion.insert(
              setEntryId: setId,
              bandId: bandId,
              mode: const Value('resistance'),
            ),
          );

      await db
          .into(db.setAccessories)
          .insert(
            SetAccessoriesCompanion.insert(
              setEntryId: setId,
              accessoryId: accessoryId,
            ),
          );

      var sets = await repo.watchSetsForWorkoutExercise(weId).first;
      expect(sets.length, 1);
      final originalSet = sets.first;
      final originalBands = await repo.bandsForSet(originalSet.id);
      final originalAccs = await repo.accessoriesForSet(originalSet.id);
      expect(originalBands.length, 1);
      expect(originalAccs.length, 1);

      // Delete set
      await repo.deleteSet(originalSet.id);
      sets = await repo.watchSetsForWorkoutExercise(weId).first;
      expect(sets.isEmpty, isTrue);

      // Restore set
      await repo.restoreSet(
        originalSet,
        bands: originalBands,
        accessories: originalAccs,
      );

      sets = await repo.watchSetsForWorkoutExercise(weId).first;
      expect(sets.length, 1);
      expect(sets.first.weightKg, 100.0);
      expect(sets.first.reps, 5);

      final restoredBands = await repo.bandsForSet(sets.first.id);
      final restoredAccs = await repo.accessoriesForSet(sets.first.id);
      expect(restoredBands.length, 1);
      expect(restoredBands.first.bandId, bandId);
      expect(restoredAccs.length, 1);
      expect(restoredAccs.first.accessoryId, accessoryId);
    },
  );
}
