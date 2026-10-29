import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/programs/domain/schedule_status.dart';
import 'package:herculex/features/programs/domain/scheduled_workout_row.dart';
import 'package:herculex/features/programs/presentation/widgets/upcoming_workouts_panel.dart';

import '../support/test_database.dart';

/// Which sessions the "coming up" panel lists: the ones still to train, from
/// today on, in date order.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final today = DateTime(2026, 10, 27);

  late AppDatabase db;
  late ProgramData program;
  late ProgramWeekData week;

  setUp(() async {
    db = await openTestDatabase();
    final programId = await db
        .into(db.programs)
        .insert(ProgramsCompanion.insert(name: '4-Week Hypertrophy'));
    final weekId = await db
        .into(db.programWeeks)
        .insert(
          ProgramWeeksCompanion.insert(programId: programId, weekIndex: 0),
        );
    program = await (db.select(
      db.programs,
    )..where((t) => t.id.equals(programId))).getSingle();
    week = await (db.select(
      db.programWeeks,
    )..where((t) => t.id.equals(weekId))).getSingle();
  });

  tearDown(() => db.close());

  Future<ScheduledWorkoutRow> row({
    required int id,
    required String date,
    String status = ScheduleStatus.planned,
    bool rest = false,
    int? startMinutes,
  }) async {
    final dayId = await db
        .into(db.programDays)
        .insert(
          ProgramDaysCompanion.insert(
            programWeekId: week.id,
            dayOfWeek: 1,
            name: 'Day $id',
            isRest: Value(rest),
          ),
        );
    final day = await (db.select(
      db.programDays,
    )..where((t) => t.id.equals(dayId))).getSingle();
    return ScheduledWorkoutRow(
      schedule: ScheduledWorkoutData(
        id: id,
        programDayId: dayId,
        dateIso: date,
        orderIndex: 0,
        occurrenceIndex: 0,
        status: status,
        startTimeMinutes: startMinutes,
      ),
      day: day,
      week: week,
      program: program,
    );
  }

  Map<String, List<ScheduledWorkoutRow>> bucket(
    List<ScheduledWorkoutRow> rows,
  ) {
    final map = <String, List<ScheduledWorkoutRow>>{};
    for (final r in rows) {
      (map[r.dateIso] ??= []).add(r);
    }
    return map;
  }

  test('lists open sessions in date order and drops past days', () async {
    final days = UpcomingWorkoutsPanel.upcomingDays(
      bucket([
        await row(id: 1, date: '2026-10-30'),
        await row(id: 2, date: '2026-10-26'),
        await row(id: 3, date: '2026-10-28'),
      ]),
      today: today,
    );

    expect(days.map((d) => d.rows.single.id), [3, 1]);
  });

  test('leaves out rest days, skipped sessions and finished ones', () async {
    final days = UpcomingWorkoutsPanel.upcomingDays(
      bucket([
        await row(id: 1, date: '2026-10-28', rest: true),
        await row(id: 2, date: '2026-10-29', status: ScheduleStatus.skipped),
        await row(id: 3, date: '2026-10-30', status: ScheduleStatus.done),
        await row(id: 4, date: '2026-10-31', status: ScheduleStatus.moved),
      ]),
      today: today,
    );

    expect(days.map((d) => d.rows.single.id), [4]);
  });

  test(
    'keeps a session already finished today, so the day is not empty',
    () async {
      final days = UpcomingWorkoutsPanel.upcomingDays(
        bucket([
          await row(id: 1, date: '2026-10-27', status: ScheduleStatus.done),
        ]),
        today: today,
      );

      expect(days, hasLength(1));
      expect(days.single.rows.single.isDone, isTrue);
    },
  );

  test('orders a day by start time, untimed sessions last', () async {
    final days = UpcomingWorkoutsPanel.upcomingDays(
      bucket([
        await row(id: 1, date: '2026-10-28'),
        await row(id: 2, date: '2026-10-28', startMinutes: 18 * 60),
        await row(id: 3, date: '2026-10-28', startMinutes: 7 * 60),
      ]),
      today: today,
    );

    expect(days.single.rows.map((r) => r.id), [3, 2, 1]);
  });

  test('is empty when nothing is planned', () async {
    expect(UpcomingWorkoutsPanel.upcomingDays({}, today: today), isEmpty);
  });
}
