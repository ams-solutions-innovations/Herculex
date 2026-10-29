import 'dart:convert';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/workout_report/data/workout_report_repository.dart';
import 'package:herculex/features/workouts/data/exercise_history_repository.dart';
import 'package:herculex/features/workouts/data/workouts_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../support/test_database.dart';
import 'coaching_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late CoachingFixture fixture;
  late ExerciseHistoryRepository repo;
  late int target;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = await openTestDatabase();
    fixture = CoachingFixture(db);
    await fixture.init();
    repo = ExerciseHistoryRepository(db, fixture.clock);
    target = await db
        .into(db.exerciseCatalog)
        .insert(
          ExerciseCatalogCompanion.insert(
            name: 'Correct RDL',
            primaryMuscle: 'Hamstrings',
            equipment: 'Barbell',
            mechanics: 'compound',
            force: 'pull',
            plane: 'sagittal',
            modality: const Value('barbell'),
            isCustom: const Value(true),
          ),
        );
  });
  tearDown(() => db.close());

  test(
    'a transfer can be undone on a device with different local IDs',
    () async {
      await fixture.train(DateTime(2026, 10, 21, 12));
      final entry = (await repo.entries(fixture.exerciseId)).single;
      final transfer = await repo.transfer(
        await repo.preview(
          sourceId: fixture.exerciseId,
          targetId: target,
          entryIds: {entry.exercise.id},
        ),
      );
      final audit = await (db.select(
        db.exerciseHistoryTransfers,
      )..where((a) => a.id.equals(transfer))).getSingle();
      final moved = await (db.select(
        db.workoutExercises,
      )..where((e) => e.id.equals(entry.exercise.id))).getSingle();
      final sets = await (db.select(
        db.setEntries,
      )..where((s) => s.workoutExerciseId.equals(moved.id))).get();
      final other = await openTestDatabase();
      addTearDown(other.close);
      await other
          .into(other.workoutSessions)
          .insert(WorkoutSessionsCompanion.insert(startedAt: DateTime(2020)));
      final newSession = await other
          .into(other.workoutSessions)
          .insert(
            entry.session.toCompanion(false).copyWith(id: const Value.absent()),
          );
      await other
          .into(other.exerciseCatalog)
          .insert(
            ExerciseCatalogCompanion.insert(
              name: 'Other local row',
              primaryMuscle: 'Abs',
              equipment: 'Barbell',
              mechanics: 'compound',
              force: 'pull',
              plane: 'sagittal',
              isCustom: const Value(true),
            ),
          );
      final sourceCatalog = await (db.select(
        db.exerciseCatalog,
      )..where((e) => e.id.equals(fixture.exerciseId))).getSingle();
      final targetCatalog = await (db.select(
        db.exerciseCatalog,
      )..where((e) => e.id.equals(target))).getSingle();
      final newSource = await other
          .into(other.exerciseCatalog)
          .insert(
            sourceCatalog.toCompanion(false).copyWith(id: const Value.absent()),
          );
      final newTarget = await other
          .into(other.exerciseCatalog)
          .insert(
            targetCatalog.toCompanion(false).copyWith(id: const Value.absent()),
          );
      final newExercise = await other
          .into(other.workoutExercises)
          .insert(
            moved
                .toCompanion(false)
                .copyWith(
                  id: const Value.absent(),
                  sessionId: Value(newSession),
                  exerciseId: Value(newTarget),
                ),
          );
      for (final set in sets) {
        await other
            .into(other.setEntries)
            .insert(
              set
                  .toCompanion(false)
                  .copyWith(
                    id: const Value.absent(),
                    workoutExerciseId: Value(newExercise),
                  ),
            );
      }
      final newAudit = await other
          .into(other.exerciseHistoryTransfers)
          .insert(audit.toCompanion(false).copyWith(id: const Value.absent()));
      await ExerciseHistoryRepository(other, fixture.clock).undo(newAudit);
      expect(
        (await other.select(other.workoutExercises).get()).single.exerciseId,
        newSource,
      );
      expect(newSource, isNot(fixture.exerciseId));
    },
  );

  test(
    'deleting history removes coaching and undo data even without foreign keys',
    () async {
      await db.customStatement('PRAGMA foreign_keys = OFF');
      final session = await fixture.train(DateTime(2026, 10, 21, 12));
      final entry = (await repo.entries(fixture.exerciseId)).single;
      await repo.transfer(
        await repo.preview(
          sourceId: fixture.exerciseId,
          targetId: target,
          entryIds: {entry.exercise.id},
        ),
      );
      final proposal = await db
          .into(db.trainingCoachingProposals)
          .insert(
            TrainingCoachingProposalsCompanion.insert(
              sourceSessionId: Value(session),
              programId: Value(fixture.programId),
              kind: 'reduceSets',
              proposalKey: 'delete-test',
              payloadJson: '{}',
              createdAt: fixture.clock.now(),
            ),
          );
      final schedule = await fixture.schedule(DateTime(2026, 11, 2, 17));
      await db
          .into(db.trainingCoachingOverrides)
          .insert(
            TrainingCoachingOverridesCompanion.insert(
              proposalId: proposal,
              scheduleId: schedule,
              planJson: '{}',
              originalPlanJson: '{}',
            ),
          );
      await WorkoutsRepository(db, fixture.clock).deleteSession(session);
      expect(await db.select(db.workoutBehaviorSnapshots).get(), isEmpty);
      expect(await db.select(db.exerciseHistoryTransfers).get(), isEmpty);
      expect(await db.select(db.trainingCoachingProposals).get(), isEmpty);
      expect(await db.select(db.trainingCoachingOverrides).get(), isEmpty);
    },
  );

  test(
    'partial transfer preserves sets and program and can be undone',
    () async {
      await fixture.train(DateTime(2026, 10, 14, 12));
      await fixture.train(DateTime(2026, 10, 21, 12));
      final entries = await repo.entries(fixture.exerciseId);
      final chosen = entries.first;
      final sets = await (db.select(
        db.setEntries,
      )..where((s) => s.workoutExerciseId.equals(chosen.exercise.id))).get();
      final preview = await repo.preview(
        sourceId: fixture.exerciseId,
        targetId: target,
        entryIds: {chosen.exercise.id},
      );
      final id = await repo.transfer(preview);
      expect((await repo.entries(fixture.exerciseId)).length, 1);
      expect((await repo.entries(target)).length, 1);
      final moved = await (db.select(
        db.setEntries,
      )..where((s) => s.workoutExerciseId.equals(chosen.exercise.id))).get();
      expect(
        moved.map((s) => s.toJson()).toList(),
        sets.map((s) => s.toJson()).toList(),
      );
      expect(
        (await db.select(db.programDayExercises).get()).single.exerciseId,
        fixture.exerciseId,
      );
      final snap = await (db.select(
        db.workoutBehaviorSnapshots,
      )..where((s) => s.sessionId.equals(chosen.session.id))).getSingle();
      expect((jsonDecode(snap.snapshotJson) as Map)['corrected'], isTrue);
      await repo.undo(id);
      expect((await repo.entries(fixture.exerciseId)).length, 2);
      expect(await repo.entries(target), isEmpty);
    },
  );
  test('a changed entry invalidates the preview before any write', () async {
    await fixture.train(DateTime(2026, 10, 21, 12));
    final e = (await repo.entries(fixture.exerciseId)).single;
    final preview = await repo.preview(
      sourceId: fixture.exerciseId,
      targetId: target,
      entryIds: {e.exercise.id},
    );
    await (db.update(db.setEntries)
          ..where((s) => s.workoutExerciseId.equals(e.exercise.id)))
        .write(const SetEntriesCompanion(reps: Value(9)));
    await expectLater(repo.transfer(preview), throwsStateError);
    expect(await repo.entries(target), isEmpty);
    expect(await db.select(db.exerciseHistoryTransfers).get(), isEmpty);
  });
  test('undo refuses edits to any transferred set', () async {
    await fixture.train(DateTime(2026, 10, 21, 12));
    final e = (await repo.entries(fixture.exerciseId)).single;
    final id = await repo.transfer(
      await repo.preview(
        sourceId: fixture.exerciseId,
        targetId: target,
        entryIds: {e.exercise.id},
      ),
    );
    await (db.update(db.setEntries)
          ..where((s) => s.workoutExerciseId.equals(e.exercise.id)))
        .write(const SetEntriesCompanion(weightKg: Value(90)));
    await expectLater(repo.undo(id), throwsStateError);
    expect((await repo.entries(target)).length, 1);
  });
  test('different measurement types fail without data conversion', () async {
    await fixture.train(DateTime(2026, 10, 21, 12));
    final timed = await db
        .into(db.exerciseCatalog)
        .insert(
          ExerciseCatalogCompanion.insert(
            name: 'Hold',
            primaryMuscle: 'Abs',
            equipment: 'Bodyweight',
            mechanics: 'isolation',
            force: 'static',
            plane: 'sagittal',
            loggingMetric: const Value('time'),
            isCustom: const Value(true),
          ),
        );
    final e = (await repo.entries(fixture.exerciseId)).single;
    await expectLater(
      repo.preview(
        sourceId: fixture.exerciseId,
        targetId: timed,
        entryIds: {e.exercise.id},
        equipment: 'barbell',
      ),
      throwsStateError,
    );
  });
  test(
    'target already in the same workout retains independent entries',
    () async {
      final session = await fixture.train(DateTime(2026, 10, 21, 12));
      final existing = await db
          .into(db.workoutExercises)
          .insert(
            WorkoutExercisesCompanion.insert(
              sessionId: session,
              exerciseId: target,
              orderIndex: 1,
            ),
          );
      await db
          .into(db.setEntries)
          .insert(
            SetEntriesCompanion.insert(
              workoutExerciseId: existing,
              setIndex: 0,
              weightKg: 40,
              reps: 8,
              isCompleted: const Value(true),
            ),
          );
      final e = (await repo.entries(fixture.exerciseId)).single;
      await repo.transfer(
        await repo.preview(
          sourceId: fixture.exerciseId,
          targetId: target,
          entryIds: {e.exercise.id},
        ),
      );
      expect((await repo.entries(target)).length, 2);
    },
  );
  test(
    'report treats an identity correction separately from adding an exercise',
    () async {
      final session = await fixture.train(
        DateTime(2026, 10, 21, 12),
        completed: 4,
      );
      final e = (await repo.entries(fixture.exerciseId)).single;
      final id = await repo.transfer(
        await repo.preview(
          sourceId: fixture.exerciseId,
          targetId: target,
          entryIds: {e.exercise.id},
        ),
      );
      final report = await WorkoutReportRepository(
        db,
        fixture.clock,
      ).generate(session);
      expect(report!.changes, contains(contains('history corrected')));
      expect(report.muscleChanges.values.every((v) => v == 0), isTrue);
      await repo.undo(id);
      final restored = await WorkoutReportRepository(
        db,
        fixture.clock,
      ).generate(session);
      expect(
        restored!.changes.where((s) => s.contains('history corrected')),
        isEmpty,
      );
    },
  );
}
