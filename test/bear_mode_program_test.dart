import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/data/local/exercise_importer.dart';
import 'package:herculex/features/programs/data/program_csv_io.dart';
import 'package:herculex/features/programs/data/programs_repository.dart';
import 'package:herculex/features/programs/domain/program_csv.dart';
import 'package:herculex/features/workouts/data/planned_session_resolver.dart';
import 'package:herculex/features/programs/domain/schedule_status.dart';

import 'support/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late ProgramCsvIo io;
  late ProgramsRepository programsRepo;

  setUp(() async {
    db = await openTestDatabase();
    final raw = File('assets/data/exercises.json').readAsStringSync();
    await ExerciseImporter.runFromJson(db, raw);
    io = ProgramCsvIo(db);
    programsRepo = ProgramsRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('Bear Mode preset decodes from CSV file and validates', () {
    final csv = File(
      'assets/programs/bear_mode_conjugate.csv',
    ).readAsStringSync();
    final doc = ProgramCsv.decode(csv);

    expect(doc.name, 'Bear Mode 12-Week Conjugate');
    expect(doc.weeks, 12);
    expect(doc.periodizationModel, 'concurrent');

    // 12 weeks, 4 days per week (Upper, Lower, Full Body, Arm Day)
    expect(doc.rows, isNotEmpty);

    final week0Rows = doc.rows.where((r) => r.weekIndex == 0).toList();
    final days = week0Rows.map((r) => r.dayOfWeek).toSet();
    expect(days, containsAll([1, 2, 4, 6])); // Mon, Tue, Thu, Sat

    final dayNames = week0Rows.map((r) => r.dayName).toSet();
    expect(dayNames, containsAll(['Upper', 'Lower', 'Full Body', 'Arm Day']));
  });

  test(
    'Bear Mode 12-Week Conjugate imports into database cleanly with all periodization and exercises',
    () async {
      final csv = File(
        'assets/programs/bear_mode_conjugate.csv',
      ).readAsStringSync();
      final programId = await io.importProgram(
        csv,
        createdByUser: false,
        description: "Bear Mode conjugate program",
      );

      final program = await programsRepo.getProgram(programId);
      expect(program, isNotNull);
      expect(program!.name, 'Bear Mode 12-Week Conjugate');
      expect(program.weeks, 12);
      expect(program.periodizationModel, 'concurrent');

      final weeks = await programsRepo.getProgramWeeks(programId);
      expect(weeks, hasLength(12));

      // Check days for week 0
      final week0Days = await programsRepo.getProgramDaysForWeek(weeks[0].id);
      expect(week0Days, hasLength(4));

      final upperDay = week0Days.firstWhere((d) => d.dayOfWeek == 1);
      final upperExercises = await programsRepo.resolveDayExercises(
        upperDay.id,
      );
      expect(upperExercises, hasLength(10));

      // Monday exercises check
      final catalog = await db.select(db.exerciseCatalog).get();
      final byId = {for (final e in catalog) e.id: e.name};
      final exerciseNames = upperExercises
          .map((e) => byId[e.exerciseId])
          .toList();

      expect(
        exerciseNames,
        containsAll([
          'Incline Barbell Bench Press',
          'Seal Row',
          'Larsen Press',
          'Pull-Up (Super Wide)',
          'Lu Raise',
          'Face Pull',
        ]),
      );

      // Check materialization over schedule
      final startDate = DateTime(2026, 8, 24); // A Monday
      await programsRepo.materializeProgram(programId, startDate);

      final scheduled = await db.select(db.scheduledWorkouts).get();
      // 12 weeks * 4 days = 48 scheduled sessions
      expect(scheduled, hasLength(48));
      expect(
        scheduled.every((s) => s.status == ScheduleStatus.planned),
        isTrue,
      );
    },
  );

  test('advanced columns survive import, resolve and CSV export', () async {
    final csv = File(
      'assets/programs/bear_mode_conjugate.csv',
    ).readAsStringSync();
    final doc = ProgramCsv.decode(csv);
    final first = doc.rows.first;
    expect(first.exerciseName, 'Incline Barbell Bench Press');
    expect(first.supersetGroup, 1);
    expect(first.restSeconds, 120);
    expect(first.rir, 1);
    expect(first.slotRole, 'main');
    expect(first.trainingMethod, 'double_progression');
    expect(first.notes, contains('Low incline'));
    expect(
      doc.rows.any(
        (r) => r.exerciseName == 'Seated Smith Machine Overhead Press',
      ),
      isTrue,
    );

    final programId = await io.importProgram(csv, createdByUser: false);
    final weeks = await programsRepo.getProgramWeeks(programId);
    final days = await programsRepo.getProgramDaysForWeek(weeks[0].id);
    final upper = days.firstWhere((d) => d.dayOfWeek == 1);
    final rows = await programsRepo.getExercisesForDay(upper.id);
    expect(rows.first.supersetGroup, 1);
    expect(rows[1].supersetGroup, 1);
    expect(rows.first.restSeconds, 120);
    expect(rows.first.targetRir, 1);
    expect(rows.first.slotRole, 'main');
    expect(rows.first.prescriptionWhy, contains('Low incline'));

    final exported = await io.exportProgram(programId);
    final again = ProgramCsv.decode(exported);
    expect(again.rows, hasLength(doc.rows.length));
    expect(again.rows.first.supersetGroup, 1);
    expect(again.rows.first.notes, first.notes);
  });

  test('optional gear is parsed and can be switched off and on', () async {
    final csv = File(
      'assets/programs/bear_mode_conjugate.csv',
    ).readAsStringSync();
    final doc = ProgramCsv.decode(csv);
    final chained = doc.rows.firstWhere(
      (r) =>
          r.weekIndex == 6 && r.exerciseName == 'Incline Barbell Bench Press',
    );
    expect(chained.gear, ['chains']);
    expect({
      for (final r in doc.rows) ...r.gear,
    }, containsAll(['chains', 'board', 'straps', 'fat_grips', 'bands']));

    Future<List<String>> gearAtWeek6(int programId) async {
      final weeks = await programsRepo.getProgramWeeks(programId);
      final days = await programsRepo.getProgramDaysForWeek(weeks[6].id);
      final upper = days.firstWhere((d) => d.dayOfWeek == 1);
      final first = (await programsRepo.getExercisesForDay(upper.id)).first;
      final cfg = first.variantConfigJson;
      if (cfg == null) return [];
      return List<String>.from(jsonDecode(cfg)['gear'] as List);
    }

    final off = await io.importProgram(csv, enabledGear: {'straps'});
    expect(await gearAtWeek6(off), isEmpty);

    await io.setProgramGear(off, {'chains', 'straps'});
    expect(await gearAtWeek6(off), ['chains']);
    expect(
      ProgramCsv.decode(await io.exportProgram(off)).rows
          .firstWhere(
            (r) =>
                r.weekIndex == 6 &&
                r.exerciseName == 'Incline Barbell Bench Press',
          )
          .gear,
      ['chains'],
    );

    final on = await io.importProgram(csv);
    expect(await gearAtWeek6(on), ['chains']);
  });

  test('warm-up flag and tempo columns are detected', () async {
    final csv = File(
      'assets/programs/bear_mode_conjugate.csv',
    ).readAsStringSync();
    final doc = ProgramCsv.decode(csv);
    expect(doc.rows.first.autoWarmups, isTrue);
    final chained = doc.rows.firstWhere(
      (r) =>
          r.weekIndex == 6 && r.exerciseName == 'Incline Barbell Bench Press',
    );
    expect(chained.tempo, '3-2-1');
    final id = await io.importProgram(csv);
    final weeks = await programsRepo.getProgramWeeks(id);
    final days = await programsRepo.getProgramDaysForWeek(weeks[0].id);
    final upper = days.firstWhere((d) => d.dayOfWeek == 1);
    final plan = await PlannedSessionResolver(db).resolveProgramDay(upper.id);
    expect(plan.exercises.first.sets.any((s) => s.isWarmup), isTrue);
  });
}
