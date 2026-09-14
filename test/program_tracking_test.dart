import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/programs/data/programs_repository.dart';

import 'support/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  setUp(() async => db = await openTestDatabase());
  tearDown(() => db.close());

  test(
    'tracking combines adherence, quality, ME history and rotations',
    () async {
      final lowBarId = await db
          .into(db.exerciseCatalog)
          .insert(
            ExerciseCatalogCompanion.insert(
              name: 'Low-Bar Squat Tracking Test',
              primaryMuscle: 'Quads',
              equipment: 'Barbell',
              mechanics: 'compound',
              force: 'push',
              plane: 'axial',
              movementPattern: const Value('squat'),
              movementFamily: const Value('squat_family'),
              maxEffortEligibility: const Value('suitable'),
            ),
          );
      final highBarId = await db
          .into(db.exerciseCatalog)
          .insert(
            ExerciseCatalogCompanion.insert(
              name: 'High-Bar Squat Tracking Test',
              primaryMuscle: 'Quads',
              equipment: 'Barbell',
              mechanics: 'compound',
              force: 'push',
              plane: 'axial',
              movementPattern: const Value('squat'),
              movementFamily: const Value('squat_family'),
              maxEffortEligibility: const Value('suitable'),
            ),
          );
      final programId = await db
          .into(db.programs)
          .insert(
            ProgramsCompanion.insert(name: 'Tracked powerbuilding block'),
          );
      final weekId = await db
          .into(db.programWeeks)
          .insert(
            ProgramWeeksCompanion.insert(
              programId: programId,
              weekIndex: 0,
              blockPhase: const Value('accumulation'),
            ),
          );
      final dayId = await db
          .into(db.programDays)
          .insert(
            ProgramDaysCompanion.insert(
              programWeekId: weekId,
              dayOfWeek: DateTime.now().weekday,
              name: 'Lower Intensity',
            ),
          );
      final slotId = await db
          .into(db.programExerciseSlots)
          .insert(
            ProgramExerciseSlotsCompanion.insert(
              programId: programId,
              slotKey: 'lower-main',
              daySlotLabel: 'Lower Intensity',
              orderIndex: 0,
              movementPattern: const Value('squat'),
              trainingMethod: const Value('max_effort'),
            ),
          );
      await db
          .into(db.programDayExercises)
          .insert(
            ProgramDayExercisesCompanion.insert(
              programDayId: dayId,
              exerciseId: lowBarId,
              orderIndex: 0,
              targetSets: const Value(3),
              targetRepsMin: const Value(1),
              targetRepsMax: const Value(3),
              programExerciseSlotId: Value(slotId),
              slotRole: const Value('main'),
              trainingMethod: const Value('max_effort'),
              prescriptionWhy: const Value(
                'Best available squat variation for this wave.',
              ),
            ),
          );
      await db.batch((batch) {
        batch.insertAll(db.rotationAssignments, [
          RotationAssignmentsCompanion.insert(
            slotId: slotId,
            exerciseId: lowBarId,
            weekIndex: 0,
            reason: 'Primary variation for this wave',
          ),
          RotationAssignmentsCompanion.insert(
            slotId: slotId,
            exerciseId: highBarId,
            weekIndex: 1,
            reason: 'Planned movement-family rotation',
          ),
        ]);
      });

      final sessionId = await db
          .into(db.workoutSessions)
          .insert(
            WorkoutSessionsCompanion.insert(
              name: const Value('Lower Intensity'),
              startedAt: DateTime.now(),
              endedAt: Value(DateTime.now()),
            ),
          );
      final workoutExerciseId = await db
          .into(db.workoutExercises)
          .insert(
            WorkoutExercisesCompanion.insert(
              sessionId: sessionId,
              exerciseId: lowBarId,
              orderIndex: 0,
              programExerciseSlotId: Value(slotId),
              plannedTrainingMethod: const Value('max_effort'),
            ),
          );
      await db
          .into(db.setEntries)
          .insert(
            SetEntriesCompanion.insert(
              workoutExerciseId: workoutExerciseId,
              setIndex: 0,
              weightKg: 100,
              reps: 3,
              rpeX10: const Value(90),
              isCompleted: const Value(true),
              completedAt: Value(DateTime.now()),
              plannedRepsMin: const Value(1),
              plannedRepsMax: const Value(3),
              plannedRpeX10: const Value(90),
              plannedIntent: const Value('ramp_to_max'),
            ),
          );
      final now = DateTime.now();
      final today =
          '${now.year.toString().padLeft(4, '0')}-'
          '${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')}';
      await db
          .into(db.scheduledWorkouts)
          .insert(
            ScheduledWorkoutsCompanion.insert(
              dateIso: today,
              programDayId: dayId,
              completedSessionId: Value(sessionId),
              status: const Value('done'),
              programId: Value(programId),
            ),
          );

      final snapshot = await ProgramsRepository(
        db,
      ).watchProgramTracking(programId).first;

      expect(snapshot.plannedSessions, 1);
      expect(snapshot.completedSessions, 1);
      expect(snapshot.adherence, 1);
      expect(snapshot.phase, 'accumulation');
      expect(snapshot.qualitySets, 1);
      expect(snapshot.maxEffortTopSets, 1);
      expect(snapshot.exercisePrs.single.label, 'Low-Bar Squat Tracking Test');
      expect(snapshot.exercisePrs.single.e1RmKg, closeTo(110, 0.01));
      expect(snapshot.movementFamilyTrends.single.label, 'squat_family');
      expect(snapshot.nextRotation, 'Week 2 · High-Bar Squat Tracking Test');

      final dayPreview = await ProgramsRepository(
        db,
      ).watchDayExerciseSummaries(dayId).first;
      expect(dayPreview.single.name, 'Low-Bar Squat Tracking Test');
      expect(dayPreview.single.targetLabel, '3 × 1–3');
      expect(dayPreview.single.method, 'max_effort');
      expect(dayPreview.single.why, contains('this wave'));
    },
  );
}
