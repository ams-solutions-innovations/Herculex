import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/data/local/exercise_importer.dart';
import 'package:herculex/features/programs/data/program_csv_io.dart';
import 'package:herculex/features/programs/domain/periodization.dart';
import 'package:herculex/features/programs/domain/program_csv.dart';
import 'package:herculex/features/programs/domain/program_muscle_volume.dart';
import 'package:herculex/features/programs/domain/split_template.dart';

import 'support/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ProgramVolumeCalculator', () {
    test('computes weekly sets per muscle group from Natural Superman CSV', () {
      final csv = File(
        'assets/programs/natural_superman.csv',
      ).readAsStringSync();
      final doc = ProgramCsv.decode(csv);

      final breakdown = ProgramVolumeCalculator.computeFromCsv(doc);

      expect(breakdown.isNotEmpty, isTrue);
      expect(breakdown.weeks, hasLength(12));

      // Check average weekly volume
      final avgVolumes = {
        for (final e in breakdown.averageWeeklyVolumes) e.muscle: e.sets,
      };

      // Natural Superman focuses heavily on Chest, Back, Shoulders, Biceps, Traps, Neck, Abs, Quads
      expect(avgVolumes['Chest'], greaterThan(0));
      expect(avgVolumes['Back'], greaterThan(0));
      expect(avgVolumes['Shoulders'], greaterThan(0));
      expect(avgVolumes['Biceps'], greaterThan(0));
      expect(avgVolumes['Traps'], greaterThan(0));
      expect(avgVolumes['Neck'], greaterThan(0));
      expect(avgVolumes['Abs'], greaterThan(0));
      expect(avgVolumes['Quads'], greaterThan(0));
      expect(avgVolumes['Hamstrings'], greaterThan(0));
      expect(avgVolumes['Calves'], greaterThan(0));

      expect(breakdown.averageWeeklyTotalSets, greaterThan(20));
    });

    test('computes weekly volume accurately for custom CSV document', () {
      const csv = '''
# Herculex Program,name,weeks,periodization
program,Upper Lower Split,2,linear
week,dayOfWeek,dayName,exercise,sets,repsMin,repsMax,rpe,setType,percent1Rm,equipment
0,1,Upper,Barbell Bench Press,4,6,8,8,standard,,barbell
0,1,Upper,Barbell Row,4,6,8,8,standard,,barbell
0,1,Upper,Overhead Press,3,8,10,8,standard,,barbell
0,1,Upper,Barbell Bicep Curl,3,10,12,8,standard,,barbell
0,2,Lower,Barbell Back Squat,4,6,8,8,standard,,barbell
0,2,Lower,Romanian Deadlift,3,8,10,8,standard,,barbell
0,2,Lower,Standing Calf Raise,4,12,15,8,standard,,machine
1,1,Upper,Barbell Bench Press,4,6,8,8,standard,,barbell
1,1,Upper,Barbell Row,4,6,8,8,standard,,barbell
1,1,Upper,Overhead Press,3,8,10,8,standard,,barbell
1,1,Upper,Barbell Bicep Curl,3,10,12,8,standard,,barbell
1,2,Lower,Barbell Back Squat,4,6,8,8,standard,,barbell
1,2,Lower,Romanian Deadlift,3,8,10,8,standard,,barbell
1,2,Lower,Standing Calf Raise,4,12,15,8,standard,,machine
''';
      final doc = ProgramCsv.decode(csv);
      final breakdown = ProgramVolumeCalculator.computeFromCsv(doc);

      expect(breakdown.weeks, hasLength(2));
      final week0Volumes = {
        for (final e in breakdown.weeks[0].volumes) e.muscle: e.sets,
      };

      expect(week0Volumes['Chest'], 4.0);
      expect(week0Volumes['Back'], 4.0);
      expect(week0Volumes['Shoulders'], 3.0);
      expect(week0Volumes['Biceps'], 3.0);
      expect(week0Volumes['Quads'], 4.0);
      expect(week0Volumes['Hamstrings'], 3.0);
      expect(week0Volumes['Calves'], 4.0);
      expect(breakdown.weeks[0].totalSets, 25.0);
    });

    test('computes volume breakdown from database program', () async {
      final db = await openTestDatabase();
      final raw = File('assets/data/exercises.json').readAsStringSync();
      await ExerciseImporter.runFromJson(db, raw);

      final io = ProgramCsvIo(db);
      final csv = File(
        'assets/programs/natural_superman.csv',
      ).readAsStringSync();
      final programId = await io.importProgram(csv);

      final breakdown = await ProgramVolumeCalculator.computeFromDatabase(
        db,
        programId,
      );

      expect(breakdown.isNotEmpty, isTrue);
      expect(breakdown.weeks, hasLength(12));

      final avgMap = {
        for (final e in breakdown.averageWeeklyVolumes) e.muscle: e.sets,
      };
      expect(avgMap['Chest'], greaterThan(0));
      expect(avgMap['Back'], greaterThan(0));
      expect(avgMap['Shoulders'], greaterThan(0));
      expect(avgMap['Biceps'], greaterThan(0));
      expect(avgMap['Neck'], greaterThan(0));

      await db.close();
    });
  });
}
