import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/data/local/exercise_importer.dart';
import 'package:herculex/features/programs/data/program_csv_io.dart';
import 'package:herculex/features/programs/data/programs_repository.dart';
import 'package:herculex/features/programs/domain/program_csv.dart';
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

  test('Natural Superman preset decodes from CSV file and validates', () {
    final csv = File('assets/programs/natural_superman.csv').readAsStringSync();
    final doc = ProgramCsv.decode(csv);

    expect(doc.name, 'Natural Superman');
    expect(doc.weeks, 12);
    expect(doc.periodizationModel, 'linear');

    // 12 weeks, 4 days per week (Upper, Lower, Full Body, Active Recovery)
    expect(doc.rows, isNotEmpty);

    final week0Rows = doc.rows.where((r) => r.weekIndex == 0).toList();
    final days = week0Rows.map((r) => r.dayOfWeek).toSet();
    expect(days, containsAll([1, 3, 5, 7])); // Mon, Wed, Fri, Sun

    final dayNames = week0Rows.map((r) => r.dayName).toSet();
    expect(
      dayNames,
      containsAll(['Upper Body', 'Lower Body', 'Full Body', 'Active Recovery']),
    );
  });

  test(
    'Natural Superman imports into database cleanly with all periodization and exercises',
    () async {
      final csv = File(
        'assets/programs/natural_superman.csv',
      ).readAsStringSync();
      final programId = await io.importProgram(
        csv,
        createdByUser: false,
        description: "Natural Hypertrophy's Superman program",
      );

      final program = await programsRepo.getProgram(programId);
      expect(program, isNotNull);
      expect(program!.name, 'Natural Superman');
      expect(program.weeks, 12);
      expect(program.periodizationModel, 'linear');

      final weeks = await programsRepo.getProgramWeeks(programId);
      expect(weeks, hasLength(12));

      // Linear periodization deloads every 4th week — so weeks 4, 8 and 12
      // (indices 3, 7, 11) each ease off relative to the week before them.
      for (final deloadIndex in [3, 7, 11]) {
        expect(
          weeks[deloadIndex].intensityFactor,
          lessThan(weeks[deloadIndex - 1].intensityFactor),
          reason: 'week ${deloadIndex + 1} should be a deload',
        );
      }

      // Check days for week 0
      final week0Days = await programsRepo.getProgramDaysForWeek(weeks[0].id);
      expect(week0Days, hasLength(4));

      final upperDay = week0Days.firstWhere((d) => d.dayOfWeek == 1);
      final upperExercises = await programsRepo.resolveDayExercises(
        upperDay.id,
      );
      expect(upperExercises, hasLength(8));

      // Monday exercises check
      final catalog = await db.select(db.exerciseCatalog).get();
      final byId = {for (final e in catalog) e.id: e.name};
      final exerciseNames = upperExercises
          .map((e) => byId[e.exerciseId])
          .toList();

      expect(
        exerciseNames,
        containsAll([
          'Barbell Bench Press',
          'Single-Arm Dumbbell Row',
          'Overhead Press',
          'EZ Bar Curl',
          'Decline Crunch',
          'Cable Fly (High to Low)',
          'Upright Row (Barbell)',
          'Hammer Curl',
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
}
