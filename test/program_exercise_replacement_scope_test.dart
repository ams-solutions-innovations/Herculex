import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/programs/data/programs_repository.dart';
import 'package:herculex/features/programs/domain/schedule_status.dart';

import 'support/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late ProgramsRepository repository;

  setUp(() async {
    db = await openTestDatabase();
    repository = ProgramsRepository(db);
  });
  tearDown(() => db.close());

  Future<int> exercise(String name) => db
      .into(db.exerciseCatalog)
      .insert(
        ExerciseCatalogCompanion.insert(
          name: name,
          primaryMuscle: 'Quads',
          equipment: 'barbell',
          mechanics: 'compound',
          force: 'push',
          plane: 'axial',
        ),
      );

  Future<
    ({List<int> rowIds, List<int> dayIds, int programId, int a, int b, int c})
  >
  rotatingFixture() async {
    final a = await exercise('Exercise A');
    final b = await exercise('Exercise B');
    final c = await exercise('Exercise C');
    final programId = await db
        .into(db.programs)
        .insert(ProgramsCompanion.insert(name: 'Rotation fixture'));
    final slotId = await db
        .into(db.programExerciseSlots)
        .insert(
          ProgramExerciseSlotsCompanion.insert(
            programId: programId,
            slotKey: 'full-body-a:main:0',
            daySlotLabel: 'Full Body A',
            orderIndex: 0,
          ),
        );

    final rowIds = <int>[];
    final dayIds = <int>[];
    for (var weekIndex = 0; weekIndex < 4; weekIndex++) {
      final weekId = await db
          .into(db.programWeeks)
          .insert(
            ProgramWeeksCompanion.insert(
              programId: programId,
              weekIndex: weekIndex,
            ),
          );
      final dayId = await db
          .into(db.programDays)
          .insert(
            ProgramDaysCompanion.insert(
              programWeekId: weekId,
              dayOfWeek: 1,
              name: 'Full Body A',
            ),
          );
      dayIds.add(dayId);
      rowIds.add(
        await db
            .into(db.programDayExercises)
            .insert(
              ProgramDayExercisesCompanion.insert(
                programDayId: dayId,
                exerciseId: weekIndex < 2 ? a : b,
                orderIndex: 0,
                programExerciseSlotId: Value(slotId),
              ),
            ),
      );
      await db
          .into(db.rotationAssignments)
          .insert(
            RotationAssignmentsCompanion.insert(
              slotId: slotId,
              exerciseId: weekIndex < 2 ? a : b,
              weekIndex: weekIndex,
              reason: 'Planned rotation',
            ),
          );
    }
    return (
      rowIds: rowIds,
      dayIds: dayIds,
      programId: programId,
      a: a,
      b: b,
      c: c,
    );
  }

  Future<List<int>> blueprintExercises(List<int> rowIds) async => [
    for (final rowId in rowIds)
      (await (db.select(
        db.programDayExercises,
      )..where((row) => row.id.equals(rowId))).getSingle()).exerciseId,
  ];

  test('this wave changes A,A to C,C but keeps the later B,B wave', () async {
    final fixture = await rotatingFixture();
    final completedSessionId = await db
        .into(db.workoutSessions)
        .insert(
          WorkoutSessionsCompanion.insert(startedAt: DateTime(2026, 9, 1)),
        );
    final materializedExerciseId = await db
        .into(db.workoutExercises)
        .insert(
          WorkoutExercisesCompanion.insert(
            sessionId: completedSessionId,
            exerciseId: fixture.a,
            orderIndex: 0,
          ),
        );

    await repository.replaceProgramExerciseSlot(
      programDayExerciseId: fixture.rowIds[1],
      replacementExerciseId: fixture.c,
    );

    expect(await blueprintExercises(fixture.rowIds), [
      fixture.c,
      fixture.c,
      fixture.b,
      fixture.b,
    ]);
    final assignments = await (db.select(
      db.rotationAssignments,
    )..orderBy([(row) => OrderingTerm(expression: row.weekIndex)])).get();
    expect(assignments.map((assignment) => assignment.exerciseId), [
      fixture.c,
      fixture.c,
      fixture.b,
      fixture.b,
    ]);
    expect(
      (await (db.select(
            db.workoutExercises,
          )..where((row) => row.id.equals(materializedExerciseId))).getSingle())
          .exerciseId,
      fixture.a,
      reason:
          'A replacement updates program blueprints, not a workout snapshot.',
    );
  });

  test('entire block changes every wave', () async {
    final fixture = await rotatingFixture();

    await repository.replaceProgramExerciseSlot(
      programDayExerciseId: fixture.rowIds[1],
      replacementExerciseId: fixture.c,
      scope: ProgramExerciseReplacementScope.entireBlock,
    );

    expect(await blueprintExercises(fixture.rowIds), [
      fixture.c,
      fixture.c,
      fixture.c,
      fixture.c,
    ]);
  });

  test('this and future waves preserves completed earlier waves', () async {
    final fixture = await rotatingFixture();

    await repository.replaceProgramExerciseSlot(
      programDayExerciseId: fixture.rowIds[2],
      replacementExerciseId: fixture.c,
      scope: ProgramExerciseReplacementScope.thisAndFutureWaves,
    );

    expect(await blueprintExercises(fixture.rowIds), [
      fixture.a,
      fixture.a,
      fixture.c,
      fixture.c,
    ]);
  });

  test('a non-slot replacement remains a one-off exercise edit', () async {
    final a = await exercise('One-off A');
    final c = await exercise('One-off C');
    final programId = await db
        .into(db.programs)
        .insert(ProgramsCompanion.insert(name: 'One-off fixture'));
    final weekId = await db
        .into(db.programWeeks)
        .insert(
          ProgramWeeksCompanion.insert(programId: programId, weekIndex: 0),
        );
    final dayId = await db
        .into(db.programDays)
        .insert(
          ProgramDaysCompanion.insert(
            programWeekId: weekId,
            dayOfWeek: 1,
            name: 'Day',
          ),
        );
    final rowId = await db
        .into(db.programDayExercises)
        .insert(
          ProgramDayExercisesCompanion.insert(
            programDayId: dayId,
            exerciseId: a,
            orderIndex: 0,
          ),
        );

    await repository.replaceProgramExerciseSlot(
      programDayExerciseId: rowId,
      replacementExerciseId: c,
      scope: ProgramExerciseReplacementScope.entireBlock,
    );

    expect(await blueprintExercises([rowId]), [c]);
  });

  test(
    'a post-commit replace and rematerialize never touches an in_progress or completed occurrence',
    () async {
      final fixture = await rotatingFixture();

      // Materialize real ScheduledWorkouts rows so there is something for
      // rematerializeProgram to preserve or rebuild. Jan 5 2026 is a Monday,
      // so the single Monday-slot day materializes an occurrence in week 0
      // instead of being dropped as "before the start date".
      await repository.materializeProgram(
        fixture.programId,
        DateTime(2026, 1, 5),
      );

      final week0Scheduled = await (db.select(
        db.scheduledWorkouts,
      )..where((t) => t.programDayId.equals(fixture.dayIds[0]))).getSingle();

      final completedSessionId = await db
          .into(db.workoutSessions)
          .insert(
            WorkoutSessionsCompanion.insert(startedAt: DateTime(2026, 1, 5)),
          );

      // Mark week 0's occurrence as user-touched, mirroring a real
      // in-progress session.
      await (db.update(
        db.scheduledWorkouts,
      )..where((t) => t.id.equals(week0Scheduled.id))).write(
        ScheduledWorkoutsCompanion(
          status: const Value(ScheduleStatus.inProgress),
          completedSessionId: Value(completedSessionId),
        ),
      );

      // entireBlock is the widest replacement scope — the worst case for
      // EDIT-03's safety property. If even this cannot disturb the
      // in-progress row, no narrower scope can either.
      await repository.replaceProgramExerciseSlot(
        programDayExerciseId: fixture.rowIds[0],
        replacementExerciseId: fixture.c,
        scope: ProgramExerciseReplacementScope.entireBlock,
      );
      await repository.rematerializeProgram(fixture.programId);

      final week0After = await (db.select(
        db.scheduledWorkouts,
      )..where((t) => t.id.equals(week0Scheduled.id))).getSingle();
      expect(week0After.id, week0Scheduled.id);
      expect(week0After.status, ScheduleStatus.inProgress);
      expect(week0After.completedSessionId, completedSessionId);
      expect(week0After.dateIso, week0Scheduled.dateIso);

      // A later, still-planned occurrence (created by the initial
      // materializeProgram call, never user-touched) does reflect the
      // exercise change, proving the replacement reached future planned
      // work while the started occurrence was left alone.
      final week3Scheduled = await (db.select(
        db.scheduledWorkouts,
      )..where((t) => t.programDayId.equals(fixture.dayIds[3]))).getSingle();
      expect(week3Scheduled.status, ScheduleStatus.planned);
      final week3Exercise = await (db.select(
        db.programDayExercises,
      )..where((t) => t.programDayId.equals(fixture.dayIds[3]))).getSingle();
      expect(week3Exercise.exerciseId, fixture.c);
    },
  );
}
