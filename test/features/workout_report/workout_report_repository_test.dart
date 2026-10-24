import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/core/utils/clock.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/data/local/local_data_wipe.dart';
import 'package:herculex/data/local/migrations/sync_backfill.dart';
import 'package:herculex/features/programs/data/weekly_adaptation_repository.dart';
import 'package:herculex/features/programs/domain/weekly_adaptation_engine.dart';
import 'package:herculex/features/sleep/data/sleep_repository.dart';
import 'package:herculex/features/workout_report/data/workout_report_journal.dart';
import 'package:herculex/features/workout_report/data/workout_report_plan_actions.dart';
import 'package:herculex/features/workout_report/data/workout_report_repository.dart';
import 'package:herculex/features/workout_report/domain/workout_report.dart';
import 'package:herculex/features/workouts/data/workouts_repository.dart';

import '../../support/test_database.dart';

class _Clock implements Clock {
  @override
  DateTime now() => DateTime(2026, 10, 14, 18);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late WorkoutsRepository workouts;
  late WorkoutReportRepository reports;
  late int exercise;
  setUp(() async {
    db = await openTestDatabase();
    workouts = WorkoutsRepository(db, _Clock());
    reports = WorkoutReportRepository(db, _Clock());
    exercise = await db
        .into(db.exerciseCatalog)
        .insert(
          ExerciseCatalogCompanion.insert(
            name: 'Report Bench',
            primaryMuscle: 'Chest',
            equipment: 'Barbell',
            mechanics: 'compound',
            force: 'push',
            plane: 'horizontal',
          ),
        );
  });
  tearDown(() => db.close());
  Future<(int, int)> session({int count = 3}) async {
    final id = await workouts.startSession();
    final row = await workouts.addExerciseToSession(
      sessionId: id,
      exerciseId: exercise,
      targetSets: count,
      targetReps: 10,
    );
    await WorkoutReportJournal(db, _Clock()).capture(id, prescribed: true);
    return (id, row);
  }

  Future<void> complete(int row, {int count = 2}) async {
    final sets = await (db.select(
      db.setEntries,
    )..where((s) => s.workoutExerciseId.equals(row))).get();
    for (final s in sets.take(count)) {
      await workouts.updateSet(
        setId: s.id,
        reps: 10,
        weightKg: 50,
        rpeX10: 80,
        isCompleted: true,
      );
    }
  }

  test('preserves omitted plan before end-session cleanup', () async {
    final (id, row) = await session();
    await complete(row);
    await workouts.endSession(id);
    final report = await reports.generate(id);
    expect(report!.plannedSets, 3);
    expect(report.completedSets, 2);
    expect(report.findings.any((f) => f.ruleId == 'PLAN-PARTIAL'), isTrue);
    expect(
      await (db.select(
        db.setEntries,
      )..where((s) => s.workoutExerciseId.equals(row))).get(),
      hasLength(2),
    );
  });
  test(
    'duplicate finish keeps omitted sets and does not revise same report',
    () async {
      final (id, row) = await session();
      await complete(row);
      await workouts.endSession(id);
      final first = await reports.row(id);
      await workouts.endSession(id);
      final next = await reports.generate(id);
      expect(next!.plannedSets, 3);
      expect(next.revision, first!.revision);
    },
  );
  test('removed set changes adjusted plan and creates a trace', () async {
    final (id, row) = await session();
    final sets = await (db.select(
      db.setEntries,
    )..where((s) => s.workoutExerciseId.equals(row))).get();
    await workouts.deleteSet(sets.last.id);
    await complete(row);
    await workouts.endSession(id);
    final report = await reports.generate(id);
    expect(report!.originalSets, 3);
    expect(report.plannedSets, 2);
    expect(
      report.findings.any((f) => f.title == 'Adjusted workout completed'),
      isTrue,
    );
    expect(report.changes, hasLength(1));
  });
  test('substitution after a completed set preserves its identity', () async {
    final (id, row) = await session();
    await complete(row, count: 1);
    final replacement = await db
        .into(db.exerciseCatalog)
        .insert(
          ExerciseCatalogCompanion.insert(
            name: 'Report Press',
            primaryMuscle: 'Chest',
            equipment: 'Machine',
            mechanics: 'compound',
            force: 'push',
            plane: 'horizontal',
          ),
        );
    await workouts.substituteExercise(
      workoutExerciseId: row,
      newExerciseId: replacement,
    );
    final rows = await (db.select(
      db.workoutExercises,
    )..where((e) => e.sessionId.equals(id))).get();
    expect(rows, hasLength(2));
    expect(rows.singleWhere((r) => r.id == row).exerciseId, exercise);
    final oldSets = await (db.select(
      db.setEntries,
    )..where((s) => s.workoutExerciseId.equals(row))).get();
    expect(oldSets, hasLength(1));
    expect(oldSets.single.isCompleted, isTrue);
    final newSets =
        await (db.select(db.setEntries)..where(
              (s) => s.workoutExerciseId.equals(
                rows.singleWhere((r) => r.id != row).id,
              ),
            ))
            .get();
    expect(newSets, hasLength(2));
    expect(newSets.every((s) => !s.isCompleted), isTrue);
  });
  test(
    'editing completed work updates revision and preserves context',
    () async {
      final (id, row) = await session();
      await complete(row);
      await workouts.endSession(id);
      await reports.saveContext(id, const ReportContext(stressed: true));
      final previous = (await reports.row(id))!;
      final sets = await (db.select(
        db.setEntries,
      )..where((s) => s.workoutExerciseId.equals(row))).get();
      await workouts.updateSet(setId: sets.first.id, reps: 12);
      final revised = await reports.generate(id);
      expect(revised!.revision, previous.revision + 1);
      expect((await reports.contextFor(id)).stressed, isTrue);
      expect((await reports.row(id))!.fingerprint, hasLength(64));
    },
  );
  test(
    'reports are local-only and deleted with session even without FKs',
    () async {
      final (id, row) = await session();
      await complete(row);
      await workouts.endSession(id);
      expect(syncedTableNames, isNot(contains('workout_reports')));
      await db.customStatement('PRAGMA foreign_keys = OFF');
      await workouts.deleteSession(id);
      expect(await reports.row(id), isNull);
      expect(await db.select(db.workoutReportPlans).get(), isEmpty);
    },
  );
  test('deleting sleep removes saved health-derived reports', () async {
    final (id, row) = await session();
    await complete(row);
    final sleep = SleepRepository(db, _Clock());
    await sleep.saveManualSleep(dateIso: '2026-10-14', totalHours: 5);
    await workouts.endSession(id);
    expect(
      (await reports.generate(
        id,
      ))!.findings.any((f) => f.ruleId == 'CONTEXT-SLEEP'),
      isTrue,
    );
    await sleep.deleteSleepForDate('2026-10-14');
    expect(await reports.row(id), isNull);
    expect(
      (await reports.generate(
        id,
      ))!.findings.any((f) => f.ruleId == 'CONTEXT-SLEEP'),
      isFalse,
    );
  });
  test('account wipe removes every private report table', () async {
    final (id, row) = await session();
    await complete(row);
    await workouts.endSession(id);
    await wipeAllLocalUserData(db);
    expect(await db.select(db.workoutReports).get(), isEmpty);
    expect(await db.select(db.workoutReportEvents).get(), isEmpty);
    expect(await db.select(db.workoutReportPlans).get(), isEmpty);
  });
  test(
    'an overlapping session ending later is not prior performance',
    () async {
      final future = await db
          .into(db.workoutSessions)
          .insert(
            WorkoutSessionsCompanion.insert(
              startedAt: DateTime(2026, 10, 14, 17),
              endedAt: Value(DateTime(2026, 10, 14, 19)),
            ),
          );
      final old = await workouts.addExerciseToSession(
        sessionId: future,
        exerciseId: exercise,
        targetSets: 1,
      );
      final oldSet = await (db.select(
        db.setEntries,
      )..where((s) => s.workoutExerciseId.equals(old))).getSingle();
      await workouts.updateSet(
        setId: oldSet.id,
        weightKg: 50,
        reps: 12,
        rpeX10: 80,
        isCompleted: true,
      );
      final (id, row) = await session();
      await complete(row);
      await workouts.endSession(id);
      final report = await reports.generate(id);
      expect(
        report!.findings.any((f) => f.ruleId == 'PERFORMANCE-DOWN'),
        isFalse,
      );
      expect(
        report.findings.any((f) => f.ruleId == 'DATA-NO-BASELINE'),
        isTrue,
      );
    },
  );
  test('catalog corrections invalidate stored exercise explanations', () async {
    final (id, row) = await session();
    await complete(row);
    await workouts.endSession(id);
    final before = (await reports.row(id))!;
    await (db.update(db.exerciseCatalog)..where((e) => e.id.equals(exercise)))
        .write(const ExerciseCatalogCompanion(name: Value('Renamed Bench')));
    final report = await reports.generate(id);
    expect(report!.revision, before.revision + 1);
    expect(
      report.findings.any((f) => f.exerciseName == 'Renamed Bench'),
      isTrue,
    );
  });
  test(
    'a changed report rejects an old program preview without mutations',
    () async {
      final (id, row) = await session();
      await complete(row);
      await workouts.endSession(id);
      final prior = (await reports.row(id))!;
      final proposal = StoredAdaptationProposal(
        id: 999,
        sourceScheduleId: 0,
        proposal: AdaptationProposal(
          trigger: AdaptationTrigger.lowRecovery,
          weekStart: DateTime(2026, 10, 12),
          reason: 'Example',
          changes: const [],
          uncoveredVolume: const {},
          inputFingerprint: 'example',
        ),
      );
      final preview = ReportPlanPreview(
        proposal,
        const {},
        id,
        prior.fingerprint,
        const {},
        const {},
        const {},
      );
      await reports.saveContext(id, const ReportContext(stressed: true));
      final actions = WorkoutReportPlanActions(
        db,
        _Clock(),
        WeeklyAdaptationRepository(db, _Clock()),
      );
      await expectLater(actions.accept(preview), throwsStateError);
      expect(await db.select(db.adaptationOverrides).get(), isEmpty);
    },
  );
  test('no linked future program creates no automatic adjustment', () async {
    final (id, row) = await session();
    await complete(row);
    await workouts.endSession(id);
    await reports.saveContext(
      id,
      const ReportContext(reason: ReportReason.time),
    );
    final actions = WorkoutReportPlanActions(
      db,
      _Clock(),
      WeeklyAdaptationRepository(db, _Clock()),
    );
    expect(await actions.preview(id), isNull);
    expect(await db.select(db.adaptationOverrides).get(), isEmpty);
  });
}
