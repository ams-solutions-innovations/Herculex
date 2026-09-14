import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/programs/domain/selection_explanation.dart';
import 'package:herculex/features/recovery/domain/joint_model.dart';

import 'support/test_database.dart';

void main() {
  group('ProgramSlotExplanations table', () {
    late AppDatabase db;
    late int programId;
    late int slotId;
    late int exerciseId;

    setUp(() async {
      db = await openTestDatabase();
      programId = await db
          .into(db.programs)
          .insert(ProgramsCompanion.insert(name: 'Test Program'));
      slotId = await db
          .into(db.programExerciseSlots)
          .insert(
            ProgramExerciseSlotsCompanion.insert(
              programId: programId,
              slotKey: 'lower-main',
              daySlotLabel: 'Lower',
              orderIndex: 0,
            ),
          );
      exerciseId = await db
          .into(db.exerciseCatalog)
          .insert(
            ExerciseCatalogCompanion.insert(
              name: 'Test Back Squat',
              primaryMuscle: 'Quads',
              equipment: 'Barbell',
              mechanics: 'compound',
              force: 'push',
              plane: 'axial',
            ),
          );
    });

    tearDown(() => db.close());

    test('inserts a filled row and reads it back', () async {
      final id = await db
          .into(db.programSlotExplanations)
          .insert(
            ProgramSlotExplanationsCompanion.insert(
              slotId: slotId,
              weekIndex: 1,
              chosenExerciseId: Value(exerciseId),
              status: 'filled',
              rationale: 'test',
            ),
          );

      final row = await (db.select(
        db.programSlotExplanations,
      )..where((t) => t.id.equals(id))).getSingle();
      expect(row.chosenExerciseId, exerciseId);
      expect(row.status, 'filled');
      expect(row.rationale, 'test');
    });

    test('inserts an empty row with null chosenExerciseId', () async {
      await db
          .into(db.programSlotExplanations)
          .insert(
            ProgramSlotExplanationsCompanion.insert(
              slotId: slotId,
              weekIndex: 2,
              chosenExerciseId: const Value(null),
              status: 'empty',
              rationale: 'No safe squat movement available.',
            ),
          );

      final row = await (db.select(
        db.programSlotExplanations,
      )..where((t) => t.weekIndex.equals(2))).getSingle();
      expect(row.chosenExerciseId, isNull);
      expect(row.status, 'empty');
      expect(row.rationale, 'No safe squat movement available.');
    });

    test('rejects a duplicate (slotId, weekIndex) pair', () async {
      await db
          .into(db.programSlotExplanations)
          .insert(
            ProgramSlotExplanationsCompanion.insert(
              slotId: slotId,
              weekIndex: 1,
              status: 'filled',
              rationale: 'first',
              chosenExerciseId: Value(exerciseId),
            ),
          );

      expect(
        () => db
            .into(db.programSlotExplanations)
            .insert(
              ProgramSlotExplanationsCompanion.insert(
                slotId: slotId,
                weekIndex: 1,
                status: 'filled',
                rationale: 'duplicate',
                chosenExerciseId: Value(exerciseId),
              ),
            ),
        throwsA(anything),
      );
    });

    test('cascades delete from the parent slot', () async {
      await db
          .into(db.programSlotExplanations)
          .insert(
            ProgramSlotExplanationsCompanion.insert(
              slotId: slotId,
              weekIndex: 1,
              status: 'filled',
              rationale: 'first',
              chosenExerciseId: Value(exerciseId),
            ),
          );
      await db
          .into(db.programSlotExplanations)
          .insert(
            ProgramSlotExplanationsCompanion.insert(
              slotId: slotId,
              weekIndex: 2,
              status: 'empty',
              rationale: 'second',
            ),
          );

      await (db.delete(
        db.programExerciseSlots,
      )..where((t) => t.id.equals(slotId))).go();

      final remaining = await (db.select(
        db.programSlotExplanations,
      )..where((t) => t.slotId.equals(slotId))).get();
      expect(remaining, isEmpty);
    });
  });

  group('SelectionExplanation', () {
    test('filled sets isFilled and exerciseId', () {
      const explanation = SelectionExplanation.filled(
        exerciseId: 42,
        rationale: 'chosen',
      );
      expect(explanation.isFilled, isTrue);
      expect(explanation.exerciseId, 42);
      expect(explanation.status, 'filled');
    });

    test('empty sets isFilled false and null exerciseId', () {
      const explanation = SelectionExplanation.empty(
        rationale: 'no safe candidate',
      );
      expect(explanation.isFilled, isFalse);
      expect(explanation.exerciseId, isNull);
      expect(explanation.status, 'empty');
    });
  });

  group('JointModel.excludedMusclesFor', () {
    test('includes muscles at/above threshold, excludes those below', () {
      final excluded = JointModel.excludedMusclesFor({'Elbow'});
      expect(excluded, containsAll(<String>['Triceps', 'Biceps']));
      expect(excluded, isNot(contains('Chest')));
    });
  });
}
