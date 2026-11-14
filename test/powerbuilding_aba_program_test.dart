import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/data/local/exercise_importer.dart';
import 'package:herculex/features/programs/data/program_csv_io.dart';
import 'package:herculex/features/programs/data/programs_repository.dart';
import 'package:herculex/features/programs/domain/program_csv.dart';

import 'support/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late ProgramCsvIo io;
  late ProgramsRepository repo;
  late String csv;

  setUp(() async {
    db = await openTestDatabase();
    await ExerciseImporter.runFromJson(
      db,
      File('assets/data/exercises.json').readAsStringSync(),
    );
    io = ProgramCsvIo(db);
    repo = ProgramsRepository(db);
    csv = File('assets/programs/powerbuilding_aba.csv').readAsStringSync();
  });

  tearDown(() async {
    await db.close();
  });

  test('decodes with A/B/A then B/A/B rotation and max-effort rows', () {
    final doc = ProgramCsv.decode(csv);
    expect(doc.name, 'Powerbuilding A/B/A Conjugate');
    expect(doc.weeks, 12);
    expect(doc.periodizationModel, 'concurrent');

    List<String> seq(int week) =>
        (doc.rows.where((r) => r.weekIndex == week).toList()
              ..sort((a, b) => a.dayOfWeek.compareTo(b.dayOfWeek)))
            .map((r) => '${r.dayOfWeek}:${r.dayName}')
            .toSet()
            .toList();
    expect(seq(0), ['1:Workout A', '3:Workout B', '5:Workout A']);
    expect(seq(1), ['1:Workout B', '3:Workout A', '5:Workout B']);

    final top = doc.rows.first;
    expect(top.exerciseName, 'Paused Bench Press');
    expect(top.sets, 1);
    expect(top.repsMax, 1);
    expect(top.rpe, 9);
    expect(top.slotRole, 'main');
  });

  test('imports, keeps supersets and schedules 36 sessions', () async {
    final id = await io.importProgram(csv, createdByUser: false);
    final weeks = await repo.getProgramWeeks(id);
    expect(weeks, hasLength(12));
    final days = await repo.getProgramDaysForWeek(weeks[0].id);
    expect(days, hasLength(3));
    final rows = await repo.getExercisesForDay(days.first.id);
    expect(rows[0].exerciseId, rows[1].exerciseId); // top single + back-downs
    expect(rows[2].supersetGroup, rows[3].supersetGroup);
    expect(rows[2].supersetGroup, isNotNull);

    await repo.materializeProgram(id, DateTime(2026, 8, 24));
    expect(await db.select(db.scheduledWorkouts).get(), hasLength(36));
  });
}
