import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/core/utils/clock.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/programs/data/programs_repository.dart';
import 'package:herculex/features/programs/domain/schedule_status.dart';
import 'package:herculex/features/programs/domain/slot_role.dart';
import 'package:herculex/features/workouts/data/scheduled_workout_service.dart';
import 'package:herculex/features/workouts/data/templates_repository.dart';
import 'package:herculex/features/workouts/data/workouts_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/test_database.dart';

class _FixedClock implements Clock {
  _FixedClock(this.fixedTime);
  final DateTime fixedTime;
  @override
  DateTime now() => fixedTime;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  late AppDatabase db;
  final testDate = DateTime(2026, 9, 14, 9, 30);
  final clock = _FixedClock(testDate);

  setUp(() async => db = await openTestDatabase());
  tearDown(() => db.close());

  for (final plannedDate in ['2026-09-15', '2026-09-13']) {
    test(
      'finishing a workout planned for $plannedDate completes its occurrence',
      () async {
        final programId = await db
            .into(db.programs)
            .insert(ProgramsCompanion.insert(name: 'Flexible schedule'));
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
                dayOfWeek: 2,
                name: 'Training',
              ),
            );
        final scheduleId = await db
            .into(db.scheduledWorkouts)
            .insert(
              ScheduledWorkoutsCompanion.insert(
                programDayId: Value(dayId),
                dateIso: plannedDate,
              ),
            );
        final otherId = await db
            .into(db.scheduledWorkouts)
            .insert(
              ScheduledWorkoutsCompanion.insert(
                programDayId: Value(dayId),
                dateIso: plannedDate,
              ),
            );
        final service = ScheduledWorkoutService(
          db,
          clock,
          ProgramsRepository(db),
          TemplatesRepository(db),
        );
        final sessionId = await service.startScheduledWorkoutById(scheduleId);
        expect(await service.startScheduledWorkoutById(scheduleId), sessionId);
        final started = await (db.select(
          db.scheduledWorkouts,
        )..where((t) => t.id.equals(scheduleId))).getSingle();
        expect(started.dateIso, plannedDate);
        expect(started.status, ScheduleStatus.inProgress);
        expect(started.completedSessionId, sessionId);

        await WorkoutsRepository(
          db,
          clock,
        ).endSession(sessionId, caloriesBurned: 0);

        final completed = await (db.select(
          db.scheduledWorkouts,
        )..where((t) => t.id.equals(scheduleId))).getSingle();
        final other = await (db.select(
          db.scheduledWorkouts,
        )..where((t) => t.id.equals(otherId))).getSingle();
        final session = await (db.select(
          db.workoutSessions,
        )..where((t) => t.id.equals(sessionId))).getSingle();
        expect(completed.dateIso, plannedDate);
        expect(completed.status, ScheduleStatus.done);
        expect(completed.completedSessionId, sessionId);
        expect(session.startedAt, testDate);
        expect(session.endedAt, isNotNull);
        expect(other.status, ScheduleStatus.planned);
        expect(other.completedSessionId, isNull);
      },
    );
  }

  test(
    'same-day scheduled workouts resolve strictly by scheduleId and resume idempotently',
    () async {
      final programsRepo = ProgramsRepository(db);
      final templatesRepo = TemplatesRepository(db);
      final service = ScheduledWorkoutService(
        db,
        clock,
        programsRepo,
        templatesRepo,
      );

      final exerciseId = await db
          .into(db.exerciseCatalog)
          .insert(
            ExerciseCatalogCompanion.insert(
              name: 'Barbell Squat Test',
              primaryMuscle: 'Quads',
              equipment: 'barbell',
              mechanics: 'compound',
              force: 'push',
              plane: 'axial',
            ),
          );

      final programId = await db
          .into(db.programs)
          .insert(ProgramsCompanion.insert(name: 'Double Split Test'));

      final weekId = await db
          .into(db.programWeeks)
          .insert(
            ProgramWeeksCompanion.insert(programId: programId, weekIndex: 0),
          );

      final dayAId = await db
          .into(db.programDays)
          .insert(
            ProgramDaysCompanion.insert(
              programWeekId: weekId,
              dayOfWeek: 1,
              name: 'Morning Strength',
            ),
          );

      final dayBId = await db
          .into(db.programDays)
          .insert(
            ProgramDaysCompanion.insert(
              programWeekId: weekId,
              dayOfWeek: 1,
              name: 'Evening Conditioning',
            ),
          );

      await db
          .into(db.programDayExercises)
          .insert(
            ProgramDayExercisesCompanion.insert(
              programDayId: dayAId,
              exerciseId: exerciseId,
              orderIndex: 0,
              slotRole: Value(SlotRole.main.id),
              targetSets: const Value(3),
            ),
          );

      await db
          .into(db.programDayExercises)
          .insert(
            ProgramDayExercisesCompanion.insert(
              programDayId: dayBId,
              exerciseId: exerciseId,
              orderIndex: 0,
              slotRole: Value(SlotRole.main.id),
              targetSets: const Value(2),
            ),
          );

      final scheduleAId = await db
          .into(db.scheduledWorkouts)
          .insert(
            ScheduledWorkoutsCompanion.insert(
              programDayId: Value(dayAId),
              dateIso: '2026-09-14',
              orderIndex: const Value(0),
              status: const Value(ScheduleStatus.planned),
            ),
          );

      final scheduleBId = await db
          .into(db.scheduledWorkouts)
          .insert(
            ScheduledWorkoutsCompanion.insert(
              programDayId: Value(dayBId),
              dateIso: '2026-09-14',
              orderIndex: const Value(1),
              status: const Value(ScheduleStatus.planned),
            ),
          );

      // Start the second same-day workout (scheduleBId)
      final sessionIdB = await service.startScheduledWorkoutById(scheduleBId);

      // Verify scheduleB was updated to in_progress with its session linked
      final updatedB = await (db.select(
        db.scheduledWorkouts,
      )..where((t) => t.id.equals(scheduleBId))).getSingle();
      expect(updatedB.status, ScheduleStatus.inProgress);
      expect(updatedB.completedSessionId, sessionIdB);

      // Verify scheduleA remains untouched as planned
      final updatedA = await (db.select(
        db.scheduledWorkouts,
      )..where((t) => t.id.equals(scheduleAId))).getSingle();
      expect(updatedA.status, ScheduleStatus.planned);
      expect(updatedA.completedSessionId, isNull);

      final allSessionsBeforeResume = await db.select(db.workoutSessions).get();
      expect(allSessionsBeforeResume, hasLength(1));

      // Resume scheduleB: must return same sessionId without inserting duplicate rows
      final resumedSessionIdB = await service.startScheduledWorkoutById(
        scheduleBId,
      );
      expect(resumedSessionIdB, sessionIdB);

      final allSessionsAfterResume = await db.select(db.workoutSessions).get();
      expect(allSessionsAfterResume, hasLength(1));

      // Preview scheduleA: must be read-only and never create workout session rows
      final previewA = await service.previewScheduledWorkout(scheduleAId);
      expect(previewA, isNotNull);
      expect(previewA!.name, 'Morning Strength');
      expect(previewA.exercises, hasLength(1));

      final allSessionsAfterPreview = await db.select(db.workoutSessions).get();
      expect(allSessionsAfterPreview, hasLength(1));
    },
  );

  test(
    'historical drifted planned rows do not trigger infinite loop, while future drifted rows self-heal once',
    () async {
      final programsRepo = ProgramsRepository(db);
      final templatesRepo = TemplatesRepository(db);
      final service = ScheduledWorkoutService(
        db,
        clock,
        programsRepo,
        templatesRepo,
      );

      final exerciseId = await db
          .into(db.exerciseCatalog)
          .insert(
            ExerciseCatalogCompanion.insert(
              name: 'Bench Press Drift Test',
              primaryMuscle: 'Chest',
              equipment: 'barbell',
              mechanics: 'compound',
              force: 'push',
              plane: 'horizontal',
            ),
          );

      // testDate is 2026-09-14 (Monday, weekday 1).
      final programId = await db
          .into(db.programs)
          .insert(
            ProgramsCompanion.insert(
              name: 'Weekly Drift Program',
              isActive: const Value(true),
              scheduleMode: const Value('weekly'),
              startDateIso: const Value('2026-09-07'),
            ),
          );

      final weekId = await db
          .into(db.programWeeks)
          .insert(
            ProgramWeeksCompanion.insert(programId: programId, weekIndex: 0),
          );

      // Expected Monday (dayOfWeek = 1)
      final mondayDayId = await db
          .into(db.programDays)
          .insert(
            ProgramDaysCompanion.insert(
              programWeekId: weekId,
              dayOfWeek: 1,
              name: 'Monday Push',
            ),
          );

      await db
          .into(db.programDayExercises)
          .insert(
            ProgramDayExercisesCompanion.insert(
              programDayId: mondayDayId,
              exerciseId: exerciseId,
              orderIndex: 0,
              slotRole: Value(SlotRole.main.id),
              targetSets: const Value(3),
            ),
          );

      // Historical uncompleted planned row on a drifted Tuesday ('2026-09-08' -> weekday 2 != 1).
      // Previously this remained untouched by materializeProgram (from: today) and caused an infinite loop!
      final pastScheduleId = await db
          .into(db.scheduledWorkouts)
          .insert(
            ScheduledWorkoutsCompanion.insert(
              programId: Value(programId),
              programDayId: Value(mondayDayId),
              dateIso: '2026-09-08',
              status: const Value(ScheduleStatus.planned),
            ),
          );

      // Future drifted planned row on Tuesday ('2026-09-15' -> weekday 2 != 1).
      await db
          .into(db.scheduledWorkouts)
          .insert(
            ScheduledWorkoutsCompanion.insert(
              programId: Value(programId),
              programDayId: Value(mondayDayId),
              dateIso: '2026-09-15',
              status: const Value(ScheduleStatus.planned),
            ),
          );

      final emissions = <TodaysScheduledWorkout?>[];
      final sub = service.watchNextWorkout(testDate).listen(emissions.add);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      await sub.cancel();

      // Must settle cleanly (not spin infinitely) and resolve Monday 2026-09-14!
      expect(emissions, isNotEmpty);
      expect(emissions.length, lessThanOrEqualTo(3));
      expect(emissions.last?.schedule.dateIso, '2026-09-14');

      // Past row was left intact and did not re-trigger repair.
      final pastRow = await (db.select(
        db.scheduledWorkouts,
      )..where((t) => t.id.equals(pastScheduleId))).getSingle();
      expect(pastRow.dateIso, '2026-09-08');

      // Future drifted 2026-09-15 planned row was repaired to Monday dates >= 2026-09-14.
      final driftedFuture =
          await (db.select(db.scheduledWorkouts)..where(
                (t) => t.dateIso.equals('2026-09-15') & t.deletedAt.isNull(),
              ))
              .get();
      expect(driftedFuture, isEmpty);
    },
  );
}
