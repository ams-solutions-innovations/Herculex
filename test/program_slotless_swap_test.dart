import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/core/utils/clock.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/programs/data/programs_repository.dart';
import 'package:herculex/features/programs/data/weekly_adaptation_repository.dart';
import 'package:herculex/features/programs/domain/schedule_status.dart';
import 'package:herculex/features/programs/domain/session_completion.dart';
import 'package:herculex/features/programs/domain/weekly_adaptation_engine.dart';
import 'package:herculex/features/workouts/data/workouts_repository.dart';

import 'support/test_database.dart';

class _Clock implements Clock {
  @override
  DateTime now() => DateTime(2026, 10, 14, 18);
}

/// Manual blocks hold one copy of every exercise per week and no slot. A
/// "permanent" swap used to rewrite only the current week's copy, so the next
/// week came back with the old exercise.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late ProgramsRepository programs;

  setUp(() async {
    db = await openTestDatabase();
    programs = ProgramsRepository(db);
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

  /// Four weeks, Monday "Lower" day, rows [squat, curl] in every week.
  Future<({int programId, List<int> dayIds, List<int> rowIds, int a, int c})>
  slotless() async {
    final a = await exercise('Squat');
    final curl = await exercise('Leg Curl');
    final c = await exercise('Hack Squat');
    final programId = await db
        .into(db.programs)
        .insert(ProgramsCompanion.insert(name: 'Manual block'));
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
              name: 'Lower',
            ),
          );
      dayIds.add(dayId);
      rowIds.add(
        await db
            .into(db.programDayExercises)
            .insert(
              ProgramDayExercisesCompanion.insert(
                programDayId: dayId,
                exerciseId: a,
                orderIndex: 0,
              ),
            ),
      );
      await db
          .into(db.programDayExercises)
          .insert(
            ProgramDayExercisesCompanion.insert(
              programDayId: dayId,
              exerciseId: curl,
              orderIndex: 1,
            ),
          );
    }
    return (programId: programId, dayIds: dayIds, rowIds: rowIds, a: a, c: c);
  }

  Future<List<int>> blueprint(List<int> rowIds) async => [
    for (final id in rowIds)
      (await (db.select(
        db.programDayExercises,
      )..where((r) => r.id.equals(id))).getSingle()).exerciseId,
  ];

  test('this and future waves reaches every later week only', () async {
    final f = await slotless();

    await programs.replaceProgramExerciseSlot(
      programDayExerciseId: f.rowIds[1],
      replacementExerciseId: f.c,
      scope: ProgramExerciseReplacementScope.thisAndFutureWaves,
    );

    expect(await blueprint(f.rowIds), [f.a, f.c, f.c, f.c]);
  });

  test('entire block reaches every week', () async {
    final f = await slotless();

    await programs.replaceProgramExerciseSlot(
      programDayExerciseId: f.rowIds[2],
      replacementExerciseId: f.c,
      scope: ProgramExerciseReplacementScope.entireBlock,
    );

    expect(await blueprint(f.rowIds), [f.c, f.c, f.c, f.c]);
  });

  test('a week that already differs is left alone', () async {
    final f = await slotless();
    final other = await exercise('Leg Press');
    await (db.update(db.programDayExercises)
          ..where((r) => r.id.equals(f.rowIds[3])))
        .write(ProgramDayExercisesCompanion(exerciseId: Value(other)));

    await programs.replaceProgramExerciseSlot(
      programDayExerciseId: f.rowIds[0],
      replacementExerciseId: f.c,
      scope: ProgramExerciseReplacementScope.thisAndFutureWaves,
    );

    expect(await blueprint(f.rowIds), [f.c, f.c, f.c, other]);
  });

  test('an accepted adaptation of a later session follows the swap', () async {
    final f = await slotless();
    final scheduleId = await db
        .into(db.scheduledWorkouts)
        .insert(
          ScheduledWorkoutsCompanion.insert(
            dateIso: '2026-10-21',
            programDayId: f.dayIds[1],
            programId: Value(f.programId),
          ),
        );
    final proposalId = await db
        .into(db.adaptationProposals)
        .insert(
          AdaptationProposalsCompanion.insert(
            programId: f.programId,
            weekStartIso: '2026-10-19',
            trigger: AdaptationTrigger.lowRecovery.name,
            reason: 'test',
            inputFingerprint: 'fp',
            proposalJson: '{}',
          ),
        );
    await db
        .into(db.adaptationOverrides)
        .insert(
          AdaptationOverridesCompanion.insert(
            proposalId: proposalId,
            scheduleId: scheduleId,
            planJson: jsonEncode({
              'exercises': [
                {'exerciseId': f.a, 'sets': <Object>[]},
              ],
            }),
          ),
        );

    await programs.replaceProgramExerciseSlot(
      programDayExerciseId: f.rowIds[0],
      replacementExerciseId: f.c,
      scope: ProgramExerciseReplacementScope.thisAndFutureWaves,
    );

    final override = await db.select(db.adaptationOverrides).getSingle();
    final exercises =
        (jsonDecode(override.planJson) as Map<String, dynamic>)['exercises']
            as List;
    expect((exercises.single as Map)['exerciseId'], f.c);
  });

  test('an already-swapped exercise still finds its program row', () async {
    final f = await slotless();
    final workouts = WorkoutsRepository(db, _Clock());
    final sessionId = await workouts.startSession();
    await db
        .into(db.scheduledWorkouts)
        .insert(
          ScheduledWorkoutsCompanion.insert(
            dateIso: '2026-10-14',
            programDayId: f.dayIds[0],
            completedSessionId: Value(sessionId),
          ),
        );
    final we = await db
        .into(db.workoutExercises)
        .insert(
          WorkoutExercisesCompanion.insert(
            sessionId: sessionId,
            exerciseId: f.c,
            orderIndex: 0,
          ),
        );

    final source = await programs.programSourceForWorkoutExercise(we);

    expect(source?.programDayExerciseId, f.rowIds[0]);
  });

  group('declining a post-workout adaptation', () {
    Future<(int scheduleId, int proposalId)> proposal({
      required AdaptationTrigger trigger,
      required String status,
      int? completedSessionId,
    }) async {
      final f = await slotless();
      final scheduleId = await db
          .into(db.scheduledWorkouts)
          .insert(
            ScheduledWorkoutsCompanion.insert(
              dateIso: '2026-10-14',
              programDayId: f.dayIds[0],
              programId: Value(f.programId),
              status: Value(status),
              completedSessionId: Value(completedSessionId),
            ),
          );
      final proposalId = await db
          .into(db.adaptationProposals)
          .insert(
            AdaptationProposalsCompanion.insert(
              programId: f.programId,
              sourceScheduleId: Value(scheduleId),
              weekStartIso: '2026-10-12',
              trigger: trigger.name,
              reason: 'test',
              inputFingerprint: 'fp',
              proposalJson: '{}',
            ),
          );
      return (scheduleId, proposalId);
    }

    Future<String> statusOf(int id) async => (await (db.select(
      db.scheduledWorkouts,
    )..where((r) => r.id.equals(id))).getSingle()).status;

    test('keeps a trained session done', () async {
      final sessionId = await WorkoutsRepository(db, _Clock()).startSession();
      final (scheduleId, proposalId) = await proposal(
        trigger: AdaptationTrigger.incompleteWorkout,
        status: ScheduleStatus.done,
        completedSessionId: sessionId,
      );

      await WeeklyAdaptationRepository(
        db,
        _Clock(),
      ).decline(proposalId, skipSource: true);

      expect(await statusOf(scheduleId), ScheduleStatus.done);
    });

    test('still skips a session the user chose to skip', () async {
      final (scheduleId, proposalId) = await proposal(
        trigger: AdaptationTrigger.skippedWorkout,
        status: ScheduleStatus.planned,
      );

      await WeeklyAdaptationRepository(
        db,
        _Clock(),
      ).decline(proposalId, skipSource: true);

      expect(await statusOf(scheduleId), ScheduleStatus.skipped);
    });
  });

  test('completion ratio', () {
    expect(SessionCompletion.ratio(completed: 7, planned: 10), 0.7);
    expect(SessionCompletion.ratio(completed: 3, planned: 0), 1);
    expect(SessionCompletion.isPartial(0.7), isTrue);
    expect(SessionCompletion.isPartial(0.96), isFalse);
    expect(SessionCompletion.isPartial(null), isFalse);
    expect(SessionCompletion.label(0.7), '70 %');
  });
}
