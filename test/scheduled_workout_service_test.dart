import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/core/utils/clock.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/programs/data/programs_repository.dart';
import 'package:herculex/features/programs/domain/schedule_status.dart';
import 'package:herculex/features/programs/domain/slot_role.dart';
import 'package:herculex/features/workouts/data/scheduled_workout_service.dart';
import 'package:herculex/features/workouts/data/templates_repository.dart';

import 'support/test_database.dart';

class _FixedClock implements Clock {
  _FixedClock(this.fixedTime);
  final DateTime fixedTime;
  @override
  DateTime now() => fixedTime;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  final testDate = DateTime(2026, 9, 14, 9, 30);
  final clock = _FixedClock(testDate);

  setUp(() async => db = await openTestDatabase());
  tearDown(() => db.close());

  test(
    'same-day scheduled workouts resolve strictly by scheduleId and resume idempotently',
    () async {
      final programsRepo = ProgramsRepository(db);
      final templatesRepo = TemplatesRepository(db);
      final service = ScheduledWorkoutService(db, clock, programsRepo, templatesRepo);

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
          .insert(ProgramWeeksCompanion.insert(programId: programId, weekIndex: 0));

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
              programDayId: dayAId,
              dateIso: '2026-09-14',
              orderIndex: const Value(0),
              status: const Value(ScheduleStatus.planned),
            ),
          );

      final scheduleBId = await db
          .into(db.scheduledWorkouts)
          .insert(
            ScheduledWorkoutsCompanion.insert(
              programDayId: dayBId,
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
      final resumedSessionIdB = await service.startScheduledWorkoutById(scheduleBId);
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
}
