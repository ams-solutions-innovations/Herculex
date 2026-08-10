import 'package:drift/drift.dart' show OrderingTerm;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/core/clock.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/programs/data/program_csv_io.dart';
import 'package:herculex/features/programs/data/programs_repository.dart';
import 'package:herculex/features/programs/data/rotations_repository.dart';
import 'package:herculex/features/programs/domain/exercise_rotation.dart';
import 'package:herculex/features/programs/domain/periodization.dart';
import 'package:herculex/features/programs/domain/program_csv.dart';
import 'package:herculex/features/programs/domain/schedule_status.dart';
import 'package:herculex/features/programs/domain/split_template.dart';
import 'package:herculex/features/workouts/data/micro_workouts_repository.dart';

class _FixedClock implements Clock {
  DateTime fixed;
  _FixedClock(this.fixed);
  @override
  DateTime now() => fixed;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Periodization', () {
    test('linear ramps intensity and deloads every 4th week', () {
      final plan = Periodization.plan(PeriodizationModel.linear, 8);
      expect(plan, hasLength(8));
      expect(plan[1].intensityFactor, greaterThan(plan[0].intensityFactor));
      expect(plan[3].isDeload, isTrue);
      expect(plan[7].isDeload, isTrue);
      expect(plan[3].volumeFactor, lessThan(plan[0].volumeFactor));
    });

    test('block splits accumulation → transmutation → realization', () {
      final plan = Periodization.plan(PeriodizationModel.block, 10);
      expect(plan.first.blockPhase, 'accumulation');
      expect(plan.last.blockPhase, 'realization');
      expect(plan.map((w) => w.blockPhase).toSet(),
          {'accumulation', 'transmutation', 'realization'});
      // Accumulation: more volume, less intensity than realization.
      expect(plan.first.volumeFactor, greaterThan(plan.last.volumeFactor));
      expect(plan.first.intensityFactor, lessThan(plan.last.intensityFactor));
    });

    test('max effort holds top intensity and protects CNS every 4th week', () {
      final plan = Periodization.plan(PeriodizationModel.maxEffort, 8);
      expect(plan[0].intensityFactor, 1.0);
      expect(plan[3].isDeload, isTrue);
    });

    test('none is flat', () {
      final plan = Periodization.plan(PeriodizationModel.none, 4);
      expect(plan.every((w) => w.intensityFactor == 1 && w.volumeFactor == 1),
          isTrue);
    });
  });

  group('ExerciseRotation', () {
    test('rotates every N weeks and wraps around the pool', () {
      // 3 exercises, rotate every 2 weeks, 8-week program:
      expect(
        ExerciseRotation.assignments(
            weeks: 8, memberCount: 3, rotateEveryWeeks: 2),
        [0, 0, 1, 1, 2, 2, 0, 0],
      );
    });

    test('weekly rotation with 2 members alternates', () {
      expect(
        ExerciseRotation.assignments(
            weeks: 4, memberCount: 2, rotateEveryWeeks: 1),
        [0, 1, 0, 1],
      );
    });
  });

  group('ProgramCsv codec', () {
    test('encode → decode round-trips', () {
      const doc = ProgramCsvDocument(
        name: 'PPL, Heavy',
        weeks: 4,
        periodizationModel: 'linear',
        rows: [
          ProgramCsvRow(
            weekIndex: 0,
            dayOfWeek: 1,
            dayName: 'Push',
            exerciseName: 'Bench Press',
            sets: 3,
            repsMin: 8,
            repsMax: 12,
            rpe: 8,
            setType: 'standard',
            percentOf1Rm: 75,
            equipmentVariant: 'barbell',
          ),
        ],
      );
      final decoded = ProgramCsv.decode(ProgramCsv.encode(doc));
      expect(decoded.name, 'PPL, Heavy'); // comma survives quoting
      expect(decoded.weeks, 4);
      expect(decoded.periodizationModel, 'linear');
      expect(decoded.rows.single.exerciseName, 'Bench Press');
      expect(decoded.rows.single.percentOf1Rm, 75);
      expect(decoded.rows.single.equipmentVariant, 'barbell');
    });

    test('rejects malformed input with readable errors', () {
      expect(() => ProgramCsv.decode(''), throwsA(isA<ProgramCsvFormatException>()));
      expect(() => ProgramCsv.decode('nonsense,row'),
          throwsA(isA<ProgramCsvFormatException>()));
      expect(
        () => ProgramCsv.decode('program,X,4,linear\n0,9,Push,Bench,3'),
        throwsA(isA<ProgramCsvFormatException>()), // dayOfWeek out of range
      );
    });
  });

  group('Database-backed Phase 4', () {
    late AppDatabase db;
    late _FixedClock clock;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      await db.customStatement('PRAGMA foreign_keys = ON');
      clock = _FixedClock(DateTime(2026, 6, 12, 9));
    });

    tearDown(() => db.close());

    Future<int> exerciseIdByName(String name) async {
      final row = await (db.select(db.exerciseCatalog)
            ..where((t) => t.name.equals(name))
            ..limit(1))
          .getSingleOrNull();
      if (row != null) return row.id;
      return db.into(db.exerciseCatalog).insert(
            ExerciseCatalogCompanion.insert(
              name: name,
              primaryMuscle: 'Chest',
              equipment: 'Barbell',
              mechanics: 'compound',
              force: 'push',
              plane: 'horizontal',
            ),
          );
    }

    test('rotation resolves the active exercise per program week', () async {
      final repo = RotationsRepository(db);
      final a = await exerciseIdByName('Test Close-Grip Bench');
      final b = await exerciseIdByName('Test Floor Press');
      final c = await exerciseIdByName('Test Paused OHP');
      final rotationId = await repo.createRotation(
        name: 'ME Press',
        rotateEveryWeeks: 1,
        exerciseIds: [a, b, c],
      );

      final week0 =
          await repo.activeExerciseFor(rotationId: rotationId, weekIndex: 0);
      final week1 =
          await repo.activeExerciseFor(rotationId: rotationId, weekIndex: 1);
      final week3 =
          await repo.activeExerciseFor(rotationId: rotationId, weekIndex: 3);
      expect(week0!.id, a);
      expect(week1!.id, b);
      expect(week3!.id, a); // wrapped around
    });

    test('micro workout completion writes a real session + completed set',
        () async {
      final repo = MicroWorkoutsRepository(db, clock);
      final pushups = await exerciseIdByName('Test Pushup');
      final id = await repo.create(
          name: '50 Pushups', exerciseId: pushups, targetReps: 50, timesPerDay: 3);
      final micro = await (db.select(db.microWorkouts)
            ..where((t) => t.id.equals(id)))
          .getSingle();

      await repo.logCompletion(micro, bodyweightKg: 80);
      clock.fixed = clock.fixed.add(const Duration(hours: 3));
      await repo.logCompletion(micro, reps: 40);

      final sessions = await (db.select(db.workoutSessions)
            ..where((t) => t.microWorkoutId.equals(id)))
          .get();
      expect(sessions, hasLength(2));
      expect(sessions.every((s) => s.endedAt != null), isTrue);

      final sets = await db.select(db.setEntries).get();
      expect(sets, hasLength(2));
      expect(sets.first.reps, 50);
      expect(sets.first.bodyweightKg, 80);
      expect(sets.last.reps, 40);
      expect(sets.every((s) => s.isCompleted), isTrue);

      final counts = await repo.completionsOn(clock.now());
      expect(counts[id], 2);
    });

    test('CSV import creates program with periodized weeks; export round-trips',
        () async {
      await exerciseIdByName('Test Bench Press');
      await exerciseIdByName('Test Squat');
      final io = ProgramCsvIo(db);

      const csv = '''
program,Test Block,4,block
week,dayOfWeek,dayName,exercise,sets,repsMin,repsMax,rpe,setType,percent1Rm,equipment
0,1,Upper,Test Bench Press,4,6,8,8,standard,75,barbell
0,3,Lower,Test Squat,5,5,5,9,pause,80,barbell
1,1,Upper,Test Bench Press,4,6,8,8,standard,77.5,barbell
''';
      final programId = await io.importProgram(csv);

      final program = await (db.select(db.programs)
            ..where((t) => t.id.equals(programId)))
          .getSingle();
      expect(program.periodizationModel, 'block');
      expect(program.weeks, 4);

      final weeks = await (db.select(db.programWeeks)
            ..where((t) => t.programId.equals(programId)))
          .get();
      expect(weeks, hasLength(4));
      expect(weeks.first.blockPhase, 'accumulation');
      expect(weeks.last.blockPhase, 'realization');

      final exported = await io.exportProgram(programId);
      final reDecoded = ProgramCsv.decode(exported);
      expect(reDecoded.name, 'Test Block');
      expect(reDecoded.rows, hasLength(3));
      expect(
          reDecoded.rows.any((r) =>
              r.exerciseName == 'Test Squat' &&
              r.setType == 'pause' &&
              r.percentOf1Rm == 80),
          isTrue);
    });

    test('CSV import rejects unknown exercise names', () async {
      final io = ProgramCsvIo(db);
      const csv = '''
program,Bad,2,none
0,1,Day,Totally Unknown Exercise,3,8,12,,,,
''';
      expect(
        () => io.importProgram(csv),
        throwsA(predicate((e) =>
            e is ProgramCsvFormatException &&
            e.message.contains('Totally Unknown Exercise'))),
      );
    });
  });

  group('Materialize v21', () {
    late AppDatabase db;
    late ProgramsRepository repo;

    // A Monday, so the weekday-spacing table lands on predictable offsets.
    final start = DateTime(2026, 6, 1);

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      await db.customStatement('PRAGMA foreign_keys = ON');
      repo = ProgramsRepository(db);
    });

    tearDown(() => db.close());

    Future<int> exerciseId(String name, {String muscle = 'Chest'}) async {
      final row = await (db.select(db.exerciseCatalog)
            ..where((t) => t.name.equals(name))
            ..limit(1))
          .getSingleOrNull();
      if (row != null) return row.id;
      return db.into(db.exerciseCatalog).insert(
            ExerciseCatalogCompanion.insert(
              name: name,
              primaryMuscle: muscle,
              equipment: 'Barbell',
              mechanics: 'compound',
              force: 'push',
              plane: 'horizontal',
            ),
          );
    }

    /// A template with [exerciseNames] attached, in order.
    Future<int> makeTemplate(
      String name,
      List<String> exerciseNames, {
      String muscle = 'Chest',
    }) async {
      final templateId = await db
          .into(db.workoutTemplates)
          .insert(WorkoutTemplatesCompanion.insert(name: name));
      for (var i = 0; i < exerciseNames.length; i++) {
        await db.into(db.templateExercises).insert(
              TemplateExercisesCompanion.insert(
                templateId: templateId,
                exerciseId: await exerciseId(exerciseNames[i], muscle: muscle),
                orderIndex: i,
              ),
            );
      }
      return templateId;
    }

    Future<int> makeBlock({
      String name = 'Block',
      SplitType type = SplitType.ppl,
      int daysPerWeek = 3,
      int weeks = 4,
      ScheduleMode mode = ScheduleMode.weekly,
      int? cycleLength,
      Map<int, int?> templates = const {},
      bool activate = true,
      DateTime? startDate,
    }) {
      return repo.createProgramFromSplit(
        name: name,
        weeks: weeks,
        plan: SplitTemplates.generate(
          type: type,
          daysPerWeek: daysPerWeek,
          mode: mode,
          cycleLength: cycleLength,
        ),
        startDate: startDate ?? start,
        templateIdsBySlot: templates,
        activate: activate,
      );
    }

    Future<List<ScheduledWorkoutData>> schedulesFor(int programId) =>
        (db.select(db.scheduledWorkouts)
              ..where((t) => t.programId.equals(programId))
              ..orderBy([
                (t) => OrderingTerm(expression: t.dateIso),
                (t) => OrderingTerm(expression: t.orderIndex),
              ]))
            .get();

    test('a weekly 3-day split over 4 weeks lands on Mon/Wed/Fri', () async {
      final id = await makeBlock();
      final rows = await schedulesFor(id);

      expect(rows, hasLength(12));
      expect(rows.take(3).map((r) => r.dateIso),
          ['2026-06-01', '2026-06-03', '2026-06-05']);
      expect(rows.last.dateIso, '2026-06-26');
      // Every date is a Mon, Wed or Fri.
      expect(
        rows.every((r) => const [
              DateTime.monday,
              DateTime.wednesday,
              DateTime.friday,
            ].contains(DateTime.parse(r.dateIso).weekday)),
        isTrue,
      );
    });

    test('a 2-day cycle fills every day regardless of weekday', () async {
      final id = await makeBlock(
        type: SplitType.ab,
        daysPerWeek: 2,
        weeks: 2,
        mode: ScheduleMode.cycle,
        cycleLength: 2,
        // A Thursday — a weekly program would never produce 14 consecutive days.
        startDate: DateTime(2026, 6, 4),
      );
      final rows = await schedulesFor(id);

      expect(rows, hasLength(14));
      expect(rows.first.dateIso, '2026-06-04');
      expect(rows.last.dateIso, '2026-06-17');
      expect(rows.map((r) => r.dateIso).toSet(), hasLength(14));
    });

    test('re-materializing one program leaves other programs alone', () async {
      // The regression test for the old `materializeProgram`, which deleted
      // every planned row in the database rather than just this program's.
      final blockA = await makeBlock(name: 'Block A');
      final blockB = await makeBlock(name: 'Block B', weeks: 2);

      final beforeA = await schedulesFor(blockA);
      expect(beforeA, hasLength(12));

      await repo.materializeProgram(blockB, start);

      final afterA = await schedulesFor(blockA);
      expect(afterA, hasLength(12));
      expect(afterA.map((r) => r.id).toSet(), beforeA.map((r) => r.id).toSet());
    });

    test('touched sessions survive re-materialize and are not duplicated',
        () async {
      final id = await makeBlock();
      final rows = await schedulesFor(id);

      final done = rows.first;
      final skipped = rows[1];
      await repo.setScheduleStatus(done.id, ScheduleStatus.done);
      await repo.setScheduleStatus(skipped.id, ScheduleStatus.skipped);

      await repo.materializeProgram(id, start);
      final after = await schedulesFor(id);

      expect(after, hasLength(12), reason: 'no occurrence duplicated');
      expect(after.singleWhere((r) => r.id == done.id).status,
          ScheduleStatus.done);
      expect(after.singleWhere((r) => r.id == skipped.id).status,
          ScheduleStatus.skipped);
      // The identity key stays unique.
      final keys = after.map((r) => (r.programDayId, r.occurrenceIndex));
      expect(keys.toSet(), hasLength(12));
    });

    test('rematerialize with futureOnly keeps the past intact', () async {
      final id = await makeBlock();
      final before = await schedulesFor(id);
      final pastIds =
          before.where((r) => r.dateIso.compareTo('2026-06-15') < 0)
              .map((r) => r.id)
              .toSet();
      expect(pastIds, isNotEmpty);

      await repo.rematerializeProgram(id, today: DateTime(2026, 6, 15));

      final after = await schedulesFor(id);
      expect(after, hasLength(12));
      expect(after.map((r) => r.id).toSet().containsAll(pastIds), isTrue,
          reason: 'rows before the cutoff must keep their identity');
    });

    test('createProgramFromSplit attaches templates, so sessions are not empty',
        () async {
      // The headline bug: the old builder wrote a display string into the day
      // name and never attached content, so every block materialized empty.
      final push = await makeTemplate('Push Day', ['Bench', 'Overhead Press']);
      final pull = await makeTemplate('Pull Day', ['Row', 'Pulldown', 'Curl']);
      final legs = await makeTemplate('Leg Day', ['Squat']);

      final id = await makeBlock(templates: {0: push, 1: pull, 2: legs});

      final days = await (db.select(db.programDays)).get();
      expect(days.every((d) => d.templateId != null), isTrue);
      expect(days.map((d) => d.slotLabel).toSet(), {'Push', 'Pull', 'Legs'});

      final rows = await schedulesFor(id);
      for (final row in rows) {
        final count = await repo.countDayExercises(row.programDayId);
        expect(count, greaterThan(0));
      }
      // The Pull day resolves its three template exercises.
      final pullDay = days.firstWhere((d) => d.slotLabel == 'Pull');
      expect(await repo.countDayExercises(pullDay.id), 3);
    });

    test('a schedule template override wins over the program day link',
        () async {
      final push = await makeTemplate('Push Day', ['Bench']);
      final swap = await makeTemplate('Deload Push', ['Bench', 'Fly', 'Dip']);
      final id = await makeBlock(templates: {0: push, 1: push, 2: push});

      final row = (await schedulesFor(id)).first;
      expect(await repo.countDayExercises(row.programDayId), 1);

      await repo.setScheduleTemplateOverride(row.id, swap);
      expect(
        await repo.countDayExercises(row.programDayId, templateOverride: swap),
        3,
      );
    });

    test('watchScheduleRange resolves titles, templates and counts', () async {
      final push = await makeTemplate('Push Day', ['Bench', 'Overhead Press']);
      final id = await makeBlock(templates: {0: push});

      final rows = await repo
          .watchScheduleRange(
            fromIso: '2026-06-01',
            toIso: '2026-06-07',
            programId: id,
          )
          .first;

      expect(rows, hasLength(3));
      expect(rows.map((r) => r.title), ['Push', 'Pull', 'Legs']);
      final pushRow = rows.first;
      expect(pushRow.template?.name, 'Push Day');
      expect(pushRow.exerciseCount, 2);
      expect(pushRow.isTemplateBacked, isTrue);
      // Pull and Legs have no template and no inline exercises.
      expect(rows[1].isTemplateBacked, isFalse);
      expect(rows[1].exerciseCount, 0);
      expect(rows.every((r) => r.program.id == id), isTrue);
    });

    test('moveScheduledWorkout reindexes both dates and flips planned to moved',
        () async {
      final id = await makeBlock();
      final rows = await schedulesFor(id);
      final mon = rows.firstWhere((r) => r.dateIso == '2026-06-01');
      final wed = rows.firstWhere((r) => r.dateIso == '2026-06-03');

      await repo.moveScheduledWorkout(
        scheduleId: mon.id,
        newDate: DateTime(2026, 6, 3),
      );

      final after = await schedulesFor(id);
      final onWed = after.where((r) => r.dateIso == '2026-06-03').toList()
        ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
      expect(onWed, hasLength(2));
      expect(onWed.map((r) => r.orderIndex), [0, 1]);
      expect(after.where((r) => r.dateIso == '2026-06-01'), isEmpty);
      expect(after.singleWhere((r) => r.id == mon.id).status,
          ScheduleStatus.moved);
      expect(after.singleWhere((r) => r.id == wed.id).status,
          ScheduleStatus.planned);
    });

    test('moving a completed session does not overwrite its status', () async {
      final id = await makeBlock();
      final row = (await schedulesFor(id)).first;
      await repo.setScheduleStatus(row.id, ScheduleStatus.done);

      await repo.moveScheduledWorkout(
        scheduleId: row.id,
        newDate: DateTime(2026, 6, 2),
      );

      final after = await schedulesFor(id);
      expect(after.singleWhere((r) => r.id == row.id).status,
          ScheduleStatus.done);
      expect(after.singleWhere((r) => r.id == row.id).dateIso, '2026-06-02');
    });

    test('reorderScheduledOnDate rewrites dense indices', () async {
      final id = await makeBlock();
      final rows = await schedulesFor(id);
      // Stack three sessions onto one date.
      for (final r in rows.where((r) => r.dateIso != '2026-06-01').take(2)) {
        await repo.moveScheduledWorkout(
          scheduleId: r.id,
          newDate: DateTime(2026, 6, 1),
        );
      }

      final before = (await schedulesFor(id))
          .where((r) => r.dateIso == '2026-06-01')
          .toList()
        ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
      expect(before.map((r) => r.orderIndex), [0, 1, 2]);

      // Drag the first tile to the end — ReorderableListView reports newIndex
      // as the pre-removal position, which the repository must adjust for.
      await repo.reorderScheduledOnDate(
        dateIso: '2026-06-01',
        oldIndex: 0,
        newIndex: 3,
      );

      final after = (await schedulesFor(id))
          .where((r) => r.dateIso == '2026-06-01')
          .toList()
        ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
      expect(after.map((r) => r.orderIndex), [0, 1, 2]);
      expect(after.map((r) => r.id), [
        before[1].id,
        before[2].id,
        before[0].id,
      ]);
    });

    test('conflict detection sees template-linked days', () async {
      // Two back-to-back days both driven by templates hitting Chest. Reading
      // ProgramDayExercises alone would find nothing here.
      final chestA = await makeTemplate('Chest A', ['Bench'], muscle: 'Chest');
      final chestB = await makeTemplate('Chest B', ['Incline'], muscle: 'Chest');
      final id = await makeBlock(
        type: SplitType.custom,
        daysPerWeek: 7,
        weeks: 1,
        templates: {0: chestA, 1: chestB},
      );

      final conflicts = await repo.detectRecoveryConflicts(programId: id);
      expect(conflicts, isNotEmpty);
      expect(conflicts.first['muscles'], contains('Chest'));
    });

    test('conflict detection ignores days that share no muscle', () async {
      final chest = await makeTemplate('Chest', ['Bench'], muscle: 'Chest');
      final legs = await makeTemplate('Legs', ['Squat'], muscle: 'Quads');
      final id = await makeBlock(
        type: SplitType.custom,
        daysPerWeek: 2,
        weeks: 1,
        templates: {0: chest, 1: legs},
      );

      expect(await repo.detectRecoveryConflicts(programId: id), isEmpty);
    });

    test('only one program is active at a time', () async {
      final a = await makeBlock(name: 'A');
      final b = await makeBlock(name: 'B');

      var programs = await db.select(db.programs).get();
      expect(programs.where((p) => p.isActive).map((p) => p.id), [b]);

      await repo.setActiveProgram(a);
      programs = await db.select(db.programs).get();
      expect(programs.where((p) => p.isActive).map((p) => p.id), [a]);
    });

    test('archiving a block clears its active flag', () async {
      final id = await makeBlock();
      await repo.archiveProgram(id);

      final program = await repo.getProgram(id);
      expect(program!.archived, isTrue);
      expect(program.isActive, isFalse);
      expect(await repo.watchActiveProgram().first, isNull);
    });

    test('deleting a block cascades to its schedule', () async {
      final id = await makeBlock();
      expect(await schedulesFor(id), isNotEmpty);

      await repo.deleteProgram(id);

      expect(await db.select(db.scheduledWorkouts).get(), isEmpty);
      expect(await db.select(db.programDays).get(), isEmpty);
    });

    test('a vacation range skips planned sessions but not completed ones',
        () async {
      final id = await makeBlock();
      final rows = await schedulesFor(id);
      final inRange = rows.firstWhere((r) => r.dateIso == '2026-06-03');
      await repo.setScheduleStatus(inRange.id, ScheduleStatus.done);

      await repo.addExternalEvent(
        from: DateTime(2026, 6, 1),
        to: DateTime(2026, 6, 7),
        type: 'vacation',
      );

      final after = await schedulesFor(id);
      final week1 = after.where(
        (r) => r.dateIso.compareTo('2026-06-08') < 0,
      );
      expect(
        week1.where((r) => r.id != inRange.id).every(
              (r) => r.status == ScheduleStatus.skipped,
            ),
        isTrue,
      );
      expect(after.singleWhere((r) => r.id == inRange.id).status,
          ScheduleStatus.done);
    });
  });
}
