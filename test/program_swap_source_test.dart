import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/core/utils/clock.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/programs/data/programs_repository.dart';
import 'package:herculex/features/workouts/data/workouts_repository.dart';

import 'support/test_database.dart';

class _Clock implements Clock {
  @override
  DateTime now() => DateTime(2026, 10, 14, 18);
}

/// An in-workout swap must reach the program through the rotation-aware
/// replacement, never through a bare `program_day_exercises` write that the
/// slot's `rotation_assignments` would shadow.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late ProgramsRepository programs;
  late WorkoutsRepository workouts;

  setUp(() async {
    db = await openTestDatabase();
    programs = ProgramsRepository(db);
    workouts = WorkoutsRepository(db, _Clock());
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

  /// Four weeks, one slot: A,A,B,B. Returns the day / blueprint ids per week.
  Future<
    ({
      int programId,
      int slotId,
      List<int> dayIds,
      List<int> rowIds,
      int a,
      int b,
      int c,
    })
  >
  rotating() async {
    final a = await exercise('Exercise A');
    final b = await exercise('Exercise B');
    final c = await exercise('Exercise C');
    final programId = await db
        .into(db.programs)
        .insert(ProgramsCompanion.insert(name: 'Rotation'));
    final slotId = await db
        .into(db.programExerciseSlots)
        .insert(
          ProgramExerciseSlotsCompanion.insert(
            programId: programId,
            slotKey: 'day:main:0',
            daySlotLabel: 'Day',
            orderIndex: 0,
          ),
        );
    final dayIds = <int>[];
    final rowIds = <int>[];
    for (var week = 0; week < 4; week++) {
      final weekId = await db
          .into(db.programWeeks)
          .insert(
            ProgramWeeksCompanion.insert(programId: programId, weekIndex: week),
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
      dayIds.add(dayId);
      rowIds.add(
        await db
            .into(db.programDayExercises)
            .insert(
              ProgramDayExercisesCompanion.insert(
                programDayId: dayId,
                exerciseId: week < 2 ? a : b,
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
              exerciseId: week < 2 ? a : b,
              weekIndex: week,
              reason: 'Planned rotation',
            ),
          );
    }
    return (
      programId: programId,
      slotId: slotId,
      dayIds: dayIds,
      rowIds: rowIds,
      a: a,
      b: b,
      c: c,
    );
  }

  /// A started session for [dayId] holding one exercise.
  Future<int> startedWorkoutExercise({
    required int dayId,
    required int exerciseId,
    int? slotId,
    int? templateIdOverride,
  }) async {
    final sessionId = await workouts.startSession();
    await db
        .into(db.scheduledWorkouts)
        .insert(
          ScheduledWorkoutsCompanion.insert(
            dateIso: '2026-10-14',
            programDayId: dayId,
            completedSessionId: Value(sessionId),
            templateIdOverride: Value(templateIdOverride),
          ),
        );
    return db
        .into(db.workoutExercises)
        .insert(
          WorkoutExercisesCompanion.insert(
            sessionId: sessionId,
            exerciseId: exerciseId,
            orderIndex: 0,
            programExerciseSlotId: Value(slotId),
          ),
        );
  }

  Future<List<int>> blueprint(List<int> rowIds) async => [
    for (final id in rowIds)
      (await (db.select(
        db.programDayExercises,
      )..where((r) => r.id.equals(id))).getSingle()).exerciseId,
  ];

  test('a slot-based session resolves to its blueprint row', () async {
    final f = await rotating();
    final we = await startedWorkoutExercise(
      dayId: f.dayIds[1],
      exerciseId: f.a,
      slotId: f.slotId,
    );

    final source = await programs.programSourceForWorkoutExercise(we);

    expect(source, isNotNull);
    expect(source!.programId, f.programId);
    expect(source.programDayExerciseId, f.rowIds[1]);
    expect(source.hasSlot, isTrue);
  });

  test('without a slot the row is matched on the starting exercise', () async {
    final f = await rotating();
    await (db.update(
      db.programDayExercises,
    )..where((r) => r.id.equals(f.rowIds[0]))).write(
      const ProgramDayExercisesCompanion(programExerciseSlotId: Value(null)),
    );
    final we = await startedWorkoutExercise(
      dayId: f.dayIds[0],
      exerciseId: f.a,
    );

    final source = await programs.programSourceForWorkoutExercise(we);

    expect(source!.programDayExerciseId, f.rowIds[0]);
    expect(source.hasSlot, isFalse);
  });

  test('a freestyle workout has nothing to write back to', () async {
    final f = await rotating();
    final sessionId = await workouts.startSession();
    final we = await db
        .into(db.workoutExercises)
        .insert(
          WorkoutExercisesCompanion.insert(
            sessionId: sessionId,
            exerciseId: f.a,
            orderIndex: 0,
          ),
        );

    expect(await programs.programSourceForWorkoutExercise(we), isNull);
  });

  test('a template-driven day reports no blueprint row', () async {
    final f = await rotating();
    final templateId = await db
        .into(db.workoutTemplates)
        .insert(WorkoutTemplatesCompanion.insert(name: 'Template'));
    await (db.update(db.programDays)..where((d) => d.id.equals(f.dayIds[0])))
        .write(ProgramDaysCompanion(templateId: Value(templateId)));
    final we = await startedWorkoutExercise(
      dayId: f.dayIds[0],
      exerciseId: f.a,
    );

    final source = await programs.programSourceForWorkoutExercise(we);

    expect(source, isNotNull);
    expect(source!.programDayExerciseId, isNull);
    expect(source.programId, f.programId);
  });

  test('swap + this wave rewrites the wave but not the later one', () async {
    final f = await rotating();
    final we = await startedWorkoutExercise(
      dayId: f.dayIds[1],
      exerciseId: f.a,
      slotId: f.slotId,
    );
    final source = (await programs.programSourceForWorkoutExercise(we))!;

    await workouts.substituteExercise(
      workoutExerciseId: we,
      newExerciseId: f.c,
    );
    await programs.replaceProgramExerciseSlot(
      programDayExerciseId: source.programDayExerciseId!,
      replacementExerciseId: f.c,
    );

    expect(await blueprint(f.rowIds), [f.c, f.c, f.b, f.b]);
    final assignments = await (db.select(
      db.rotationAssignments,
    )..orderBy([(r) => OrderingTerm(expression: r.weekIndex)])).get();
    expect(assignments.map((r) => r.exerciseId), [f.c, f.c, f.b, f.b]);
    expect(
      (await (db.select(
        db.workoutExercises,
      )..where((r) => r.id.equals(we))).getSingle()).exerciseId,
      f.c,
    );
  });

  test(
    'substituteExercise(permanently) no longer writes a shadowed blueprint row',
    () async {
      final f = await rotating();
      final we = await startedWorkoutExercise(
        dayId: f.dayIds[1],
        exerciseId: f.a,
        slotId: f.slotId,
      );

      await workouts.substituteExercise(
        workoutExerciseId: we,
        newExerciseId: f.c,
        permanently: true,
      );

      // The old code rewrote week 1's row only, which the slot's rotation
      // assignment then overrode. Program edits belong to the scoped path.
      expect(await blueprint(f.rowIds), [f.a, f.a, f.b, f.b]);
    },
  );

  test('a template day is edited in place by a permanent swap', () async {
    final f = await rotating();
    final templateId = await db
        .into(db.workoutTemplates)
        .insert(WorkoutTemplatesCompanion.insert(name: 'Template'));
    final templateExerciseId = await db
        .into(db.templateExercises)
        .insert(
          TemplateExercisesCompanion.insert(
            templateId: templateId,
            exerciseId: f.a,
            orderIndex: 0,
          ),
        );
    await (db.update(db.programDays)..where((d) => d.id.equals(f.dayIds[0])))
        .write(ProgramDaysCompanion(templateId: Value(templateId)));
    final we = await startedWorkoutExercise(
      dayId: f.dayIds[0],
      exerciseId: f.a,
    );

    await workouts.substituteExercise(
      workoutExerciseId: we,
      newExerciseId: f.c,
      permanently: true,
    );

    expect(
      (await (db.select(
        db.templateExercises,
      )..where((r) => r.id.equals(templateExerciseId))).getSingle()).exerciseId,
      f.c,
    );
  });
}
