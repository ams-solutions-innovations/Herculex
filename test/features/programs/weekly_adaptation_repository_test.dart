import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/core/utils/clock.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/programs/data/programs_repository.dart';
import 'package:herculex/features/programs/data/weekly_adaptation_repository.dart';
import 'package:herculex/features/programs/domain/schedule_status.dart';
import 'package:herculex/features/programs/domain/slot_role.dart';
import 'package:herculex/features/workout_report/data/workout_report_repository.dart';
import 'package:herculex/features/workouts/data/planned_session_resolver.dart';
import 'package:herculex/features/workouts/data/scheduled_workout_service.dart';
import 'package:herculex/features/workouts/data/templates_repository.dart';
import 'package:herculex/features/workouts/data/workouts_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../support/test_database.dart';

class _FixedClock implements Clock {
  const _FixedClock(this.time);

  final DateTime time;

  @override
  DateTime now() => time;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  late AppDatabase db;

  setUp(() async => db = await openTestDatabase());
  tearDown(() => db.close());

  test(
    'low-recovery adaptation caps compound work and removes a real accessory set',
    () async {
      final compoundId = await db
          .into(db.exerciseCatalog)
          .insert(
            ExerciseCatalogCompanion.insert(
              name: 'Adapted Squat',
              primaryMuscle: 'Quads',
              equipment: 'Barbell',
              mechanics: 'compound',
              force: 'push',
              plane: 'axial',
            ),
          );
      final isolationId = await db
          .into(db.exerciseCatalog)
          .insert(
            ExerciseCatalogCompanion.insert(
              name: 'Adapted Leg Extension',
              primaryMuscle: 'Quads',
              equipment: 'Machine',
              mechanics: 'isolation',
              force: 'push',
              plane: 'sagittal',
            ),
          );
      final programId = await db
          .into(db.programs)
          .insert(ProgramsCompanion.insert(name: 'Recovery adaptation test'));
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
              name: 'Lower',
            ),
          );
      await db.batch((batch) {
        batch.insertAll(db.programDayExercises, [
          ProgramDayExercisesCompanion.insert(
            programDayId: dayId,
            exerciseId: compoundId,
            orderIndex: 0,
            slotRole: Value(SlotRole.main.id),
            targetSets: const Value(4),
          ),
          ProgramDayExercisesCompanion.insert(
            programDayId: dayId,
            exerciseId: isolationId,
            orderIndex: 1,
            slotRole: Value(SlotRole.isolation.id),
            targetSets: const Value(3),
          ),
        ]);
      });
      final scheduleId = await db
          .into(db.scheduledWorkouts)
          .insert(
            ScheduledWorkoutsCompanion.insert(
              programId: Value(programId),
              programDayId: dayId,
              dateIso: '2026-10-14',
              orderIndex: const Value(0),
              status: const Value(ScheduleStatus.planned),
            ),
          );

      final repository = WeeklyAdaptationRepository(
        db,
        _FixedClock(DateTime(2026, 10, 14, 8)),
      );
      final proposal = await repository.proposeForLowRecovery(
        scheduleId,
        volumeFactor: 0.8,
        reason: 'Elevated CNS fatigue.',
      );

      expect(proposal, isNotNull);
      final exercises = proposal!.proposal.changes.single.plan.exercises;
      expect(exercises[0].workingSetCount, 2);
      expect(exercises[1].workingSetCount, 2);

      final replacementId = await db
          .into(db.exerciseCatalog)
          .insert(
            ExerciseCatalogCompanion.insert(
              name: 'Replacement Extension',
              primaryMuscle: 'Quads',
              equipment: 'Machine',
              mechanics: 'isolation',
              force: 'push',
              plane: 'sagittal',
            ),
          );
      await (db.update(db.programDayExercises)..where(
            (e) =>
                e.programDayId.equals(dayId) & e.exerciseId.equals(isolationId),
          ))
          .write(
            ProgramDayExercisesCompanion(exerciseId: Value(replacementId)),
          );
      final refreshed = await repository.proposeForLowRecovery(
        scheduleId,
        volumeFactor: 0.8,
        reason: 'Elevated CNS fatigue.',
      );
      expect(
        refreshed!.id,
        isNot(proposal.id),
        reason: 'Changed plans need a new review identity.',
      );
      await expectLater(
        repository.accept(proposal.id),
        throwsA(isA<AdaptationStaleException>()),
      );
      expect(
        refreshed.proposal.changes.single.plan.exercises.last.exerciseId,
        replacementId,
      );
      expect(await db.select(db.adaptationOverrides).get(), isEmpty);
      await (db.update(db.programDayExercises)..where(
            (e) =>
                e.programDayId.equals(dayId) &
                e.exerciseId.equals(replacementId),
          ))
          .write(ProgramDayExercisesCompanion(exerciseId: Value(isolationId)));
      final restored = await repository.proposeForLowRecovery(
        scheduleId,
        volumeFactor: 0.8,
        reason: 'Elevated CNS fatigue.',
      );

      await repository.accept(restored!.id);
      expect(
        await repository.proposeForLowRecovery(
          scheduleId,
          volumeFactor: 0.8,
          reason: 'Elevated CNS fatigue.',
        ),
        isNull,
        reason:
            'Reopening the launcher must not reduce the accepted plan again.',
      );
      final schedule = await (db.select(
        db.scheduledWorkouts,
      )..where((row) => row.id.equals(scheduleId))).getSingle();
      final materializedPlan = await PlannedSessionResolver(
        db,
      ).resolveScheduledWorkout(schedule);
      expect(
        materializedPlan.exercises[0].sets.where((set) => !set.isWarmup),
        hasLength(2),
      );
      expect(
        materializedPlan.exercises[1].sets.where((set) => !set.isWarmup),
        hasLength(2),
      );
      final clock = _FixedClock(DateTime(2026, 10, 14, 8));
      final service = ScheduledWorkoutService(
        db,
        clock,
        ProgramsRepository(db),
        TemplatesRepository(db),
      );
      final sessionId = await service.startScheduledWorkoutById(scheduleId);
      final sessionExercises = await (db.select(
        db.workoutExercises,
      )..where((e) => e.sessionId.equals(sessionId))).get();
      final sets =
          await (db.select(db.setEntries)..where(
                (s) =>
                    s.workoutExerciseId.isIn(sessionExercises.map((e) => e.id)),
              ))
              .get();
      final workouts = WorkoutsRepository(db, clock);
      for (final set in sets.where((s) => !s.isWarmup)) {
        await workouts.updateSet(
          setId: set.id,
          weightKg: 50,
          reps: 10,
          rpeX10: 80,
          isCompleted: true,
        );
      }
      await workouts.endSession(sessionId);
      final report = await WorkoutReportRepository(
        db,
        clock,
      ).generate(sessionId);
      // The unadapted resolver prescribes three main + three isolation sets.
      expect(report!.originalSets, 6);
      expect(report.plannedSets, 4);
      expect(report.completedSets, 4);
      expect(
        report.findings.any((f) => f.title == 'Adjusted workout completed'),
        isTrue,
      );
    },
  );
}
