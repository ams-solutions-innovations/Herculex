import 'dart:convert';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/programs/data/programs_repository.dart';
import 'package:herculex/features/training_coaching/data/training_coaching_repository.dart';
import 'package:herculex/features/workout_report/domain/workout_report.dart';
import 'package:herculex/features/workouts/data/planned_session_resolver.dart';
import 'package:herculex/features/workouts/data/scheduled_workout_service.dart';
import 'package:herculex/features/workouts/data/templates_repository.dart';
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

  test(
    'concurrent dashboard and finish refreshes do not duplicate proposals',
    () async {
      for (var i = 0; i < 4; i++) {
        await f.train(DateTime(2026, 10, 7 + 7 * i, 12));
      }
      f.clock.set(DateTime(2026, 10, 28, 18));
      await Future.wait([for (var i = 0; i < 6; i++) repo.refresh()]);
      expect((await db.select(db.trainingCoachingProposals).get()).length, 1);
    },
  );
  test(
    'concurrent finish captures preserve a single immutable baseline',
    () async {
      final session = await f.train(DateTime(2026, 10, 28, 12));
      await db.delete(db.workoutBehaviorSnapshots).go();
      await Future.wait([
        for (var i = 0; i < 6; i++) repo.behavior.capture(session),
      ]);
      final snapshots = await db.select(db.workoutBehaviorSnapshots).get();
      expect(snapshots.length, 1);
      expect(
        (jsonDecode(snapshots.single.snapshotJson) as Map)['known'],
        isTrue,
      );
    },
  );
  Future<int> habit() async {
    var source = 0;
    for (var i = 0; i < 4; i++) {
      source = await f.train(DateTime(2026, 10, 7 + 7 * i, 12));
    }
    f.clock.set(DateTime(2026, 10, 28, 18));
    await repo.refresh();
    return source;
  }

  Future<TrainingCoachingProposalData> proposal() => (db.select(
    db.trainingCoachingProposals,
  )..where((p) => p.kind.equals('reduceSets'))).getSingle();
  Future<ScheduledWorkoutData> schedule(int id) => (db.select(
    db.scheduledWorkouts,
  )..where((s) => s.id.equals(id))).getSingle();
  int count(PlannedSessionSnapshot p) => p.exercises.fold(
    0,
    (n, e) => n + e.sets.where((s) => !s.isWarmup).length,
  );

  test('the captured original survives cleanup of unfinished sets', () async {
    final session = await f.train(DateTime(2026, 10, 28, 12));
    final snap = await (db.select(
      db.workoutBehaviorSnapshots,
    )..where((s) => s.sessionId.equals(session))).getSingle();
    final json = jsonDecode(snap.snapshotJson) as Map;
    expect(json['known'], isTrue);
    expect((json['original'] as List).single['planned'], 4);
    expect((json['actual'] as List).single['completed'], 2);
    expect((json['original'] as List).single['row'], isA<String>());
  });
  test(
    'preview is read-only; accepting changes exactly two occurrences',
    () async {
      await habit();
      final first = await f.schedule(DateTime(2026, 11, 2, 17));
      final second = await f.schedule(DateTime(2026, 11, 9, 17));
      final third = await f.schedule(DateTime(2026, 11, 16, 17));
      final p = await proposal();
      final preview = await repo.preview(p.id);
      expect(preview.changes.length, 2);
      expect(await db.select(db.trainingCoachingOverrides).get(), isEmpty);
      expect(
        (await db.select(db.programDayExercises).get()).single.targetSets,
        4,
      );
      await repo.accept(preview);
      final resolver = PlannedSessionResolver(db, clock: f.clock);
      expect(
        count(await resolver.resolveScheduledWorkout(await schedule(first))),
        2,
      );
      expect(
        count(await resolver.resolveScheduledWorkout(await schedule(second))),
        2,
      );
      expect(
        count(await resolver.resolveScheduledWorkout(await schedule(third))),
        4,
      );
      expect(
        (await db.select(db.programDayExercises).get()).single.targetSets,
        4,
      );
      await expectLater(repo.accept(preview), throwsStateError);
      expect((await db.select(db.trainingCoachingOverrides).get()).length, 2);
    },
  );
  test('edits to a program invalidate a reviewed preview', () async {
    await habit();
    await f.schedule(DateTime(2026, 11, 2, 17));
    final preview = await repo.preview((await proposal()).id);
    await (db.update(db.programDayExercises)
          ..where((e) => e.programDayId.equals(f.dayId)))
        .write(const ProgramDayExercisesCompanion(targetSets: Value(5)));
    await expectLater(repo.accept(preview), throwsStateError);
    expect(await db.select(db.trainingCoachingOverrides).get(), isEmpty);
  });
  test(
    'starting an affected workout invalidates the reviewed preview',
    () async {
      await habit();
      final id = await f.schedule(DateTime(2026, 11, 2, 17));
      final preview = await repo.preview((await proposal()).id);
      await (db.update(
        db.scheduledWorkouts,
      )..where((s) => s.id.equals(id))).write(
        const ScheduledWorkoutsCompanion(status: Value('in_progress')),
      );
      await expectLater(repo.accept(preview), throwsStateError);
    },
  );
  test(
    'cancelling returns unstarted occurrences to the original plan',
    () async {
      await habit();
      final id = await f.schedule(DateTime(2026, 11, 2, 17));
      final p = await proposal();
      await repo.accept(await repo.preview(p.id));
      await repo.cancelTrial(p.id);
      expect(
        count(
          await PlannedSessionResolver(
            db,
            clock: f.clock,
          ).resolveScheduledWorkout(await schedule(id)),
        ),
        4,
      );
      expect((await proposal()).status, 'cancelled');
    },
  );
  test(
    'an expired trial is inconclusive and does not change the base program',
    () async {
      await habit();
      await f.schedule(DateTime(2026, 11, 2, 17));
      final p = await proposal();
      await repo.accept(await repo.preview(p.id));
      f.clock.advance(const Duration(days: 29));
      await repo.refresh();
      final reviewed = await proposal();
      expect(reviewed.status, 'review');
      expect(
        (jsonDecode(reviewed.payloadJson) as Map)['result']['conclusion'],
        'insufficient',
      );
      expect(
        (await db.select(db.programDayExercises).get()).single.targetSets,
        4,
      );
    },
  );
  test(
    'confirmed time constraint can create a one-time plan with no program day',
    () async {
      final session = await f.train(DateTime(2026, 10, 28, 12));
      await repo.behavior.saveReason(session, ReportReason.time);
      f.clock.set(DateTime(2026, 10, 28, 18));
      await repo.refresh();
      final p = await (db.select(
        db.trainingCoachingProposals,
      )..where((p) => p.kind.equals('catchUp'))).getSingle();
      final preview = await repo.preview(
        p.id,
        extraAt: DateTime(2026, 10, 30, 17),
      );
      expect(preview.changes.single.scheduleId, isNull);
      expect(count(preview.changes.single.after), 2);
      await repo.accept(preview);
      final extra = await (db.select(
        db.scheduledWorkouts,
      )..where((s) => s.oneOffPlanJson.isNotNull())).getSingle();
      expect(extra.programDayId, isNull);
      expect(
        count(
          await PlannedSessionResolver(
            db,
            clock: f.clock,
          ).resolveScheduledWorkout(extra),
        ),
        2,
      );
      final rows = await ProgramsRepository(
        db,
      ).watchScheduleRange(fromIso: '2026-10-30', toIso: '2026-10-30').first;
      expect(rows.single.title, 'Optional lower body');
      expect(rows.single.exerciseCount, 1);
      final programs = ProgramsRepository(db);
      final service = ScheduledWorkoutService(
        db,
        f.clock,
        programs,
        TemplatesRepository(db),
      );
      expect((await service.workoutForSchedule(extra.id))!.programDay, isNull);
      await programs.setScheduleStatus(extra.id, 'skipped');
      await repo.refresh();
      expect((await db.select(db.trainingCoachingProposals).get()).length, 1);
    },
  );
  test(
    'pain and fatigue do not generate catch-up and private details remain local',
    () async {
      final session = await f.train(DateTime(2026, 10, 28, 12));
      await repo.behavior.saveReason(session, ReportReason.pain);
      await repo.refresh();
      expect(await db.select(db.trainingCoachingProposals).get(), isEmpty);
      final snapshot = (await db.select(db.workoutBehaviorSnapshots).get())
          .single
          .snapshotJson;
      expect(snapshot, contains('do_not_catch_up'));
      expect(snapshot, isNot(contains('"pain"')));
      expect(snapshot, isNot(contains('unusualFatigue')));
    },
  );
  test('an explicit decline and snooze persist across refreshes', () async {
    await habit();
    final p = await proposal();
    await repo.snooze(p.id);
    expect(
      (await proposal()).snoozedUntil,
      f.clock.now().add(const Duration(days: 14)),
    );
    await repo.decline(p.id);
    await repo.refresh();
    expect((await proposal()).status, 'declined');
  });
}
