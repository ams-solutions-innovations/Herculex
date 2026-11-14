import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/data/local/exercise_importer.dart';
import 'package:herculex/features/programs/data/program_csv_io.dart';
import 'package:herculex/features/programs/data/programs_repository.dart';
import 'package:herculex/features/programs/domain/program_csv.dart';
import 'package:herculex/features/workouts/data/planned_session_resolver.dart';
import 'package:herculex/features/workouts/domain/set_prescription_metadata.dart';

import 'support/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late String csv;

  setUp(() async {
    db = await openTestDatabase();
    await ExerciseImporter.runFromJson(
      db,
      File('assets/data/exercises.json').readAsStringSync(),
    );
    csv = File('assets/programs/hybrid_fatloss.csv').readAsStringSync();
  });

  tearDown(() async {
    await db.close();
  });

  test('decodes Mon/Tue/Thu/Fri with two full-body and two GPP days', () {
    final doc = ProgramCsv.decode(csv);
    expect(doc.name, 'Hybrid 2x Full Body + 2x GPP Fat Loss');
    expect(doc.weeks, 12);
    final week0 = doc.rows.where((r) => r.weekIndex == 0);
    expect({for (final r in week0) r.dayOfWeek}, {1, 2, 4, 5});
    expect(
      {for (final r in week0) r.dayName},
      {'Full Body A', 'GPP 1', 'Full Body B', 'GPP 2'},
    );
    // Second half swaps the calisthenics circuit for low-impact conditioning.
    expect(
      doc.rows.any(
        (r) => r.weekIndex == 0 && r.exerciseName == 'Close Grip Push-Up',
      ),
      isTrue,
    );
    expect(
      doc.rows.any(
        (r) => r.weekIndex == 6 && r.exerciseName == 'Close Grip Push-Up',
      ),
      isFalse,
    );
    // No axial barbell squats or deadlifts in the plan.
    const banned = {
      'Barbell Back Squat',
      'Conventional Deadlift',
      'High-Bar Back Squat',
    };
    expect(doc.rows.any((r) => banned.contains(r.exerciseName)), isFalse);
  });

  test(
    'imports, keeps the Simple 6 giant set and schedules 48 sessions',
    () async {
      final io = ProgramCsvIo(db);
      final repo = ProgramsRepository(db);
      final id = await io.importProgram(csv, createdByUser: false);
      final weeks = await repo.getProgramWeeks(id);
      expect(weeks, hasLength(12));
      final days = await repo.getProgramDaysForWeek(weeks[0].id);
      expect(days, hasLength(4));
      final gpp = days.firstWhere((d) => d.name == 'GPP 1');
      final rows = await repo.getExercisesForDay(gpp.id);
      expect(rows.where((r) => r.supersetGroup == 1), hasLength(6));

      await repo.materializeProgram(id, DateTime(2026, 8, 24));
      expect(await db.select(db.scheduledWorkouts).get(), hasLength(48));
    },
  );

  test(
    'down sets, time targets and warm-ups reach the planned workout',
    () async {
      final io = ProgramCsvIo(db);
      final repo = ProgramsRepository(db);
      final id = await io.importProgram(csv, createdByUser: false);
      final weeks = await repo.getProgramWeeks(id);

      Future<PlannedSessionSnapshot> plan(int week, String dayName) async {
        final days = await repo.getProgramDaysForWeek(weeks[week].id);
        final day = days.firstWhere((d) => d.name == dayName);
        return PlannedSessionResolver(db).resolveProgramDay(day.id);
      }

      // Week 3 GPP 1 is the 20-down push-up protocol: 20, 19, ... 1.
      final down = await plan(2, 'GPP 1');
      final pushUps = down.exercises.firstWhere(
        (e) => e.sets.any((s) => s.setType == 'down_sets'),
      );
      final working = pushUps.sets.where((s) => !s.isWarmup).toList();
      expect(working, hasLength(20));
      expect(working.first.repsMin, 20);
      expect(working[1].repsMin, 19);
      expect(working.last.repsMin, 1);
      expect(pushUps.why, contains('Down sets'));

      // Week 7 GPP 2: the treadmill walk carries a 40 minute time target.
      final gpp2 = await plan(6, 'GPP 2');
      final walk = gpp2.exercises.firstWhere(
        (e) => e.sets.any(
          (s) =>
              SetPrescriptionMetadata.decode(
                s.setTypeMetaJson,
              )['targetDurationSeconds'] ==
              2400,
        ),
      );
      expect(walk.sets, isNotEmpty);

      // Week 7 GPP 1: sled drag carries a distance target.
      final gpp1 = await plan(6, 'GPP 1');
      expect(
        gpp1.exercises.any(
          (e) => e.sets.any(
            (s) =>
                SetPrescriptionMetadata.decode(
                  s.setTypeMetaJson,
                )['targetDistanceM'] ==
                20,
          ),
        ),
        isTrue,
      );
    },
  );

  test('time, distance, down set and warm-up columns round-trip', () {
    final doc = ProgramCsv.decode(csv);
    final dd = doc.rows.firstWhere((r) => r.setType == 'down_sets');
    expect(dd.setMeta['startReps'], 20);
    final hang = doc.rows.firstWhere((r) => r.exerciseName == 'Dead Hang');
    expect(hang.durationSeconds, 30);
    final again = ProgramCsv.decode(ProgramCsv.encode(doc));
    expect(
      again.rows.firstWhere((r) => r.setType == 'down_sets').setMeta,
      dd.setMeta,
    );
    expect(
      again.rows
          .firstWhere((r) => r.exerciseName == 'Dead Hang')
          .durationSeconds,
      30,
    );
  });
}
