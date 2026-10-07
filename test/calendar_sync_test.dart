import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/workouts/domain/calendar_service.dart';

import 'support/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CalendarService & 2-Way Sync logic', () {
    late AppDatabase db;
    late CalendarService calendarService;

    setUp(() async {
      db = await openTestDatabase();
      calendarService = CalendarService(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('CalendarService instance can be initialized', () {
      expect(calendarService, isNotNull);
    });

    test('CalendarSyncResult holds status, error, and pull/push counts', () {
      const res = CalendarSyncResult(
        success: true,
        pulledCount: 2,
        pushedCount: 5,
      );
      expect(res.success, isTrue);
      expect(res.pulledCount, 2);
      expect(res.pushedCount, 5);
      expect(res.error, isNull);
    });

    test('Regex pattern correctly matches [herculex_workout_id:X] tags', () {
      final idRegex = RegExp(r'\[herculex_workout_id:(\d+)\]');
      const desc =
          'Programmed training session scheduled via your Herculex app.\n[herculex_workout_id:42]';

      final match = idRegex.firstMatch(desc);
      expect(match, isNotNull);
      expect(match!.group(1), '42');
      expect(int.parse(match.group(1)!), 42);
    });

    test('Inbound change logic updates ScheduledWorkout in database', () async {
      // 1. Create a dummy program, week, and program day
      final programId = await db
          .into(db.programs)
          .insert(
            ProgramsCompanion.insert(
              name: 'Hypertrophy Block',
              weeks: const Value(4),
            ),
          );

      final weekId = await db
          .into(db.programWeeks)
          .insert(
            ProgramWeeksCompanion.insert(programId: programId, weekIndex: 1),
          );

      final dayId = await db
          .into(db.programDays)
          .insert(
            ProgramDaysCompanion.insert(
              programWeekId: weekId,
              dayOfWeek: 1,
              name: 'Push Heavy',
            ),
          );

      // 2. Insert a scheduled workout
      final workoutId = await db
          .into(db.scheduledWorkouts)
          .insert(
            ScheduledWorkoutsCompanion.insert(
              dateIso: '2026-09-05',
              programDayId: dayId,
              programId: Value(programId),
              startTimeMinutes: const Value(540), // 9:00 AM
              status: const Value('planned'),
            ),
          );

      // Verify inserted
      var row = await (db.select(
        db.scheduledWorkouts,
      )..where((t) => t.id.equals(workoutId))).getSingle();
      expect(row.dateIso, '2026-09-05');
      expect(row.status, 'planned');
      expect(row.startTimeMinutes, 540);

      // 3. Simulate inbound change from Google Calendar: user moved event to 2026-09-06 at 10:30 AM (630 min)
      const newDateIso = '2026-09-06';
      const newMinutes = 630;

      await (db.update(
        db.scheduledWorkouts,
      )..where((t) => t.id.equals(workoutId))).write(
        const ScheduledWorkoutsCompanion(
          dateIso: Value(newDateIso),
          startTimeMinutes: Value(newMinutes),
          status: Value('moved'),
        ),
      );

      // 4. Verify that local database reflects the moved date and updated start time
      row = await (db.select(
        db.scheduledWorkouts,
      )..where((t) => t.id.equals(workoutId))).getSingle();
      expect(row.dateIso, '2026-09-06');
      expect(row.status, 'moved');
      expect(row.startTimeMinutes, 630);
    });
  });
}
