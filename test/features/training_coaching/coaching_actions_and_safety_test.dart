import 'dart:convert';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/programs/data/programs_repository.dart';
import 'package:herculex/features/training_coaching/data/training_coaching_repository.dart';
import 'package:herculex/features/workout_report/domain/workout_report.dart';
import 'package:herculex/features/workouts/data/planned_session_resolver.dart';
import 'package:herculex/features/workouts/data/portable_workout_plan.dart';
import 'package:herculex/features/workouts/data/scheduled_workout_service.dart';
import 'package:herculex/features/workouts/data/templates_repository.dart';
import 'package:herculex/features/workouts/data/workouts_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../support/test_database.dart';
import 'coaching_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late CoachingFixture f;
  late TrainingCoachingRepository repo;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = await openTestDatabase();
    f = CoachingFixture(db);
    await f.init();
    repo = TrainingCoachingRepository(db, f.clock);
  });
  tearDown(() => db.close());
  Future<int> habit() async {
    for (var i = 0; i < 4; i++) {
      await f.train(DateTime(2026, 10, 7 + 7 * i, 12));
    }
    f.clock.set(DateTime(2026, 10, 28, 18));
    await repo.refresh();
    return (await db.select(db.trainingCoachingProposals).get()).single.id;
  }

  Future<int> timeConstraint() async {
    final session = await f.train(DateTime(2026, 10, 28, 12));
    await repo.behavior.saveReason(session, ReportReason.time);
    f.clock.set(DateTime(2026, 10, 28, 18));
    await repo.refresh();
    return (await db.select(db.trainingCoachingProposals).get()).single.id;
  }

  test(
    'revising a trial creates a draft and requires another confirmation',
    () async {
      final id = await habit();
      await f.schedule(DateTime(2026, 11, 2, 17));
      await repo.accept(await repo.preview(id));
      f.clock.advance(const Duration(days: 29));
      await repo.refresh();
      final first = await f.schedule(DateTime(2026, 11, 30, 17));
      await f.schedule(DateTime(2026, 12, 7, 17));
      final draft = await repo.adjustTrial(id, targetSets: 1);
      await repo.refresh();
      final row = await (db.select(
        db.trainingCoachingProposals,
      )..where((p) => p.id.equals(draft))).getSingle();
      expect(row.status, 'proposed');
      final preview = await repo.preview(draft);
      expect(preview.changes.first.after.exercises.single.sets.length, 1);
      expect(
        (await db.select(db.programDayExercises).get()).single.targetSets,
        4,
      );
      await repo.accept(preview);
      final previous = await (db.select(
        db.trainingCoachingProposals,
      )..where((p) => p.id.equals(id))).getSingle();
      expect(previous.status, 'cancelled');
      final schedule = await (db.select(
        db.scheduledWorkouts,
      )..where((s) => s.id.equals(first))).getSingle();
      expect(
        (await PlannedSessionResolver(
          db,
          clock: f.clock,
        ).resolveScheduledWorkout(schedule)).exercises.single.sets.length,
        1,
      );
    },
  );

  Future<void> finish(int scheduleId, DateTime at) async {
    f.clock.set(at);
    final service = ScheduledWorkoutService(
      db,
      f.clock,
      ProgramsRepository(db),
      TemplatesRepository(db),
    );
    final session = await service.startScheduledWorkoutById(scheduleId);
    final exercises = await (db.select(
      db.workoutExercises,
    )..where((e) => e.sessionId.equals(session))).get();
    final sets =
        await (db.select(db.setEntries)..where(
              (s) => s.workoutExerciseId.isIn(exercises.map((e) => e.id)),
            ))
            .get();
    for (final set in sets) {
      await (db.update(db.setEntries)..where((s) => s.id.equals(set.id))).write(
        SetEntriesCompanion(
          weightKg: const Value(80),
          reps: const Value(10),
          rpeX10: const Value(80),
          isCompleted: const Value(true),
          completedAt: Value(at.add(Duration(minutes: set.setIndex + 1))),
        ),
      );
    }
    f.clock.advance(const Duration(minutes: 20));
    await WorkoutsRepository(db, f.clock).endSession(session);
  }

  test(
    'trial results require a second explicit permanent confirmation',
    () async {
      final id = await habit();
      final first = await f.schedule(DateTime(2026, 11, 2, 17));
      final second = await f.schedule(DateTime(2026, 11, 9, 17));
      final third = await f.schedule(DateTime(2026, 11, 16, 17));
      await repo.accept(await repo.preview(id));
      await finish(first, DateTime(2026, 11, 2, 17));
      await finish(second, DateTime(2026, 11, 9, 17));
      await repo.refresh();
      final row = await (db.select(
        db.trainingCoachingProposals,
      )..where((p) => p.id.equals(id))).getSingle();
      expect(row.status, 'review');
      await repo.saveFeedback(id, tiring: false);
      expect((await repo.feedback(id))!.fatigueAfter, isFalse);
      final publicState = await (db.select(
        db.trainingCoachingProposals,
      )..where((p) => p.id.equals(id))).getSingle();
      expect(publicState.payloadJson, isNot(contains('unusualFatigue')));
      expect(publicState.payloadJson, isNot(contains('"pain"')));

      expect((jsonDecode(row.payloadJson) as Map)['result']['targetMet'], 2);
      expect(
        (await db.select(db.programDayExercises).get()).single.targetSets,
        4,
      );
      final permanent = await repo.permanentPreview(id);
      expect(permanent.permanent, isTrue);
      expect(permanent.changes.map((c) => c.scheduleId), [third]);
      await repo.accept(permanent);
      expect(
        (await db.select(db.programDayExercises).get()).single.targetSets,
        2,
      );
      final completed = await (db.select(
        db.scheduledWorkouts,
      )..where((s) => s.id.equals(first))).getSingle();
      final originalSession =
          await (db.select(db.workoutExercises)..where(
                (e) => e.sessionId.equals(completed.completedSessionId!),
              ))
              .getSingle();
      expect(
        (await (db.select(
                  db.setEntries,
                )..where((s) => s.workoutExerciseId.equals(originalSession.id)))
                .get())
            .length,
        2,
      );
    },
  );

  test(
    'a newly flagged joint invalidates an extra-work preview at acceptance',
    () async {
      final id = await timeConstraint();
      final preview = await repo.preview(
        id,
        extraAt: DateTime(2026, 10, 30, 17),
      );
      await db
          .into(db.jointPainLogs)
          .insert(
            JointPainLogsCompanion.insert(
              dateIso: '2026-10-28',
              joint: 'Knee',
              severity: const Value(2),
              loggedAt: Value(f.clock.now()),
            ),
          );
      await expectLater(repo.accept(preview), throwsStateError);
      expect(await db.select(db.trainingCoachingOverrides).get(), isEmpty);
      expect(
        await (db.select(
          db.scheduledWorkouts,
        )..where((s) => s.oneOffPlanJson.isNotNull())).get(),
        isEmpty,
      );
    },
  );

  test(
    'an untimed overlapping workout prevents guessing a safe same-day slot',
    () async {
      final id = await timeConstraint();
      await db
          .into(db.scheduledWorkouts)
          .insert(
            ScheduledWorkoutsCompanion.insert(
              dateIso: '2026-10-30',
              programDayId: Value(f.dayId),
              programId: Value(f.programId),
            ),
          );
      await expectLater(
        repo.preview(id, extraAt: DateTime(2026, 10, 30, 17)),
        throwsStateError,
      );
    },
  );

  test(
    'indirect muscle credit blocks added work around a flagged elbow',
    () async {
      final id = await timeConstraint();
      await db
          .into(db.exerciseMuscles)
          .insert(
            ExerciseMusclesCompanion.insert(
              exerciseId: f.exerciseId,
              muscle: 'Biceps',
              role: 'secondary',
              contribution: const Value(1),
            ),
          );
      await db
          .into(db.jointPainLogs)
          .insert(
            JointPainLogsCompanion.insert(
              dateIso: '2026-10-28',
              joint: 'Elbow',
              severity: const Value(2),
              loggedAt: Value(f.clock.now()),
            ),
          );
      await expectLater(
        repo.preview(id, extraAt: DateTime(2026, 10, 30, 17)),
        throwsStateError,
      );
    },
  );

  test(
    'portable plans resolve by UUID when local exercise IDs differ',
    () async {
      final plan = await PlannedSessionResolver(
        db,
        clock: f.clock,
      ).resolveProgramDay(f.dayId);
      final encoded = await PortableWorkoutPlan(db).encode(plan);
      final original = await (db.select(
        db.exerciseCatalog,
      )..where((e) => e.id.equals(f.exerciseId))).getSingle();
      final other = await openTestDatabase();
      addTearDown(other.close);
      await other
          .into(other.exerciseCatalog)
          .insert(
            ExerciseCatalogCompanion.insert(
              name: 'Unrelated local row',
              primaryMuscle: 'Chest',
              equipment: 'Barbell',
              mechanics: 'compound',
              force: 'push',
              plane: 'sagittal',
              isCustom: const Value(true),
            ),
          );
      final newId = await other
          .into(other.exerciseCatalog)
          .insert(
            original.toCompanion(false).copyWith(id: const Value.absent()),
          );
      final decoded = await PortableWorkoutPlan(other).decode(encoded);
      expect(decoded.exercises.single.exerciseId, newId);
      expect(newId, isNot(f.exerciseId));
      expect(
        decoded.exercises.single.sets.length,
        plan.exercises.single.sets.length,
      );
      expect(encoded, isNot(contains('exerciseId')));
    },
  );

  test(
    'timed targets survive portable storage and workout materialization',
    () async {
      final plan = await PlannedSessionResolver(
        db,
        clock: f.clock,
      ).resolveProgramDay(f.dayId);
      final timed = PlannedSessionSnapshot(
        name: 'Timed trial',
        exercises: [
          copyPlannedExercise(
            plan.exercises.single,
            sets: [
              const PlannedSetSnapshot(
                index: 1,
                repsMin: null,
                repsMax: null,
                isWarmup: false,
                setType: 'standard',
                intent: 'technical',
                setTypeMetaJson:
                    '{"setPrescription":{"version":1,"targetDurationSeconds":45}}',
              ),
            ],
          ),
        ],
      );
      final decoded = await PortableWorkoutPlan(
        db,
      ).decode(await PortableWorkoutPlan(db).encode(timed));
      final session = await PlannedSessionResolver(
        db,
        clock: f.clock,
      ).materialize(decoded, startedAt: f.clock.now());
      final e = await (db.select(
        db.workoutExercises,
      )..where((e) => e.sessionId.equals(session))).getSingle();
      final set = await (db.select(
        db.setEntries,
      )..where((s) => s.workoutExerciseId.equals(e.id))).getSingle();
      expect(set.durationSeconds, 45);
      expect(set.isCompleted, isFalse);
    },
  );

  test(
    'an unstarted arms superset transfers as one optional workout',
    () async {
      for (final muscle in ['Biceps', 'Triceps']) {
        final id = await db
            .into(db.exerciseCatalog)
            .insert(
              ExerciseCatalogCompanion.insert(
                name: 'Optional $muscle',
                primaryMuscle: muscle,
                equipment: 'Cable',
                mechanics: 'isolation',
                force: 'pull',
                plane: 'sagittal',
                modality: const Value('cable'),
                isCustom: const Value(true),
                recoveryImpact: const Value(1),
              ),
            );
        await db
            .into(db.programDayExercises)
            .insert(
              ProgramDayExercisesCompanion.insert(
                programDayId: f.dayId,
                exerciseId: id,
                orderIndex: muscle == 'Biceps' ? 1 : 2,
                targetSets: const Value(3),
                targetRepsMin: const Value(8),
                targetRepsMax: const Value(12),
                slotRole: const Value('accessory'),
                trainingMethod: const Value('straight_sets'),
                supersetGroup: const Value(1),
              ),
            );
      }
      final at = DateTime(2026, 10, 28, 12);
      f.clock.set(at);
      final resolver = PlannedSessionResolver(db, clock: f.clock);
      final session = await resolver.materialize(
        await resolver.resolveProgramDay(f.dayId),
        startedAt: at,
      );
      await db
          .into(db.scheduledWorkouts)
          .insert(
            ScheduledWorkoutsCompanion.insert(
              dateIso: '2026-10-28',
              programDayId: Value(f.dayId),
              programId: Value(f.programId),
              completedSessionId: Value(session),
            ),
          );
      final main =
          await (db.select(db.workoutExercises)..where(
                (e) =>
                    e.sessionId.equals(session) &
                    e.exerciseId.equals(f.exerciseId),
              ))
              .getSingle();
      await (db.update(
        db.setEntries,
      )..where((s) => s.workoutExerciseId.equals(main.id))).write(
        SetEntriesCompanion(
          isCompleted: const Value(true),
          completedAt: Value(at),
          weightKg: const Value(50),
          reps: const Value(10),
          rpeX10: const Value(80),
        ),
      );
      f.clock.advance(const Duration(minutes: 45));
      await WorkoutsRepository(db, f.clock).endSession(session);
      await repo.behavior.saveReason(session, ReportReason.time);
      await repo.refresh();
      final p = (await db.select(db.trainingCoachingProposals).get()).single;
      final preview = await repo.preview(
        p.id,
        extraAt: DateTime(2026, 10, 30, 17),
      );
      expect(preview.changes.single.after.name, 'Optional arms');
      final exercises = preview.changes.single.after.exercises;
      expect(exercises.length, 2);
      expect(exercises.map((e) => e.supersetGroup).toSet(), hasLength(1));
      expect(exercises.first.supersetGroup, isNotNull);
      expect(exercises.every((e) => e.sets.length == 3), isTrue);
    },
  );
}
