import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/programs/application/programs_providers.dart';
import 'package:herculex/features/programs/domain/schedule_status.dart';
import 'package:herculex/features/programs/domain/scheduled_workout_row.dart';
import 'package:herculex/features/programs/presentation/widgets/month_calendar.dart';

import '../support/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  final anchor = DateTime(2026, 9, 14);
  final iso = '2026-09-14';

  setUp(() async {
    db = await openTestDatabase();
  });

  tearDown(() => db.close());

  Future<ScheduledWorkoutRow> createTestRow({required int scheduleId}) async {
    final programId = await db
        .into(db.programs)
        .insert(ProgramsCompanion.insert(name: '4-Week Hypertrophy'));
    final weekId = await db
        .into(db.programWeeks)
        .insert(
          ProgramWeeksCompanion.insert(programId: programId, weekIndex: 0),
        );
    final dayId = await db
        .into(db.programDays)
        .insert(
          ProgramDaysCompanion.insert(
            programWeekId: weekId,
            dayOfWeek: 1,
            name: 'Upper Body A',
          ),
        );

    final program = await (db.select(
      db.programs,
    )..where((t) => t.id.equals(programId))).getSingle();
    final week = await (db.select(
      db.programWeeks,
    )..where((t) => t.id.equals(weekId))).getSingle();
    final day = await (db.select(
      db.programDays,
    )..where((t) => t.id.equals(dayId))).getSingle();

    return ScheduledWorkoutRow(
      schedule: ScheduledWorkoutData(
        id: scheduleId,
        programDayId: dayId,
        dateIso: iso,
        orderIndex: 0,
        occurrenceIndex: 0,
        status: ScheduleStatus.planned,
      ),
      day: day,
      week: week,
      program: program,
      exerciseCount: 4,
    );
  }

  testWidgets(
    'Tapping the month grid day cell invokes onSelect(date) with no scheduleId',
    (tester) async {
      final row = await createTestRow(scheduleId: 101);
      final range = ScheduleRange.monthGrid(anchor, programId: row.program.id);

      DateTime? capturedDate;
      int? capturedScheduleId;
      var wasCalledWithNamedArg = false;

      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          scheduleByDateProvider(range).overrideWith(
            (ref) => Stream.value({
              iso: [row],
            }),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: MonthCalendar(
                  anchor: anchor,
                  programId: row.program.id,
                  selected: anchor,
                  onSelect: (date, {scheduleId}) {
                    capturedDate = date;
                    capturedScheduleId = scheduleId;
                    wasCalledWithNamedArg = true;
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap the whole-cell day widget (the day-of-month text for `anchor`).
      await tester.tap(find.text('${anchor.day}').first);
      await tester.pumpAndSettle();

      expect(wasCalledWithNamedArg, isTrue);
      expect(capturedDate, isNotNull);
      expect(
        capturedDate!.year == anchor.year &&
            capturedDate!.month == anchor.month &&
            capturedDate!.day == anchor.day,
        isTrue,
      );
      expect(capturedScheduleId, isNull);
    },
  );

  testWidgets(
    'Tapping a SessionTile in the selected-day list invokes onSelect(date, scheduleId: row.id)',
    (tester) async {
      final row = await createTestRow(scheduleId: 202);
      final range = ScheduleRange.monthGrid(anchor, programId: row.program.id);

      DateTime? capturedDate;
      int? capturedScheduleId;

      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          scheduleByDateProvider(range).overrideWith(
            (ref) => Stream.value({
              iso: [row],
            }),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: MonthCalendar(
                  anchor: anchor,
                  programId: row.program.id,
                  selected: anchor,
                  onSelect: (date, {scheduleId}) {
                    capturedDate = date;
                    capturedScheduleId = scheduleId;
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap the session tile in the selected-day list, identified by its title.
      await tester.ensureVisible(find.text(row.title));
      await tester.pumpAndSettle();
      await tester.tap(find.text(row.title));
      await tester.pumpAndSettle();

      expect(capturedDate, isNotNull);
      expect(
        capturedDate!.year == anchor.year &&
            capturedDate!.month == anchor.month &&
            capturedDate!.day == anchor.day,
        isTrue,
      );
      expect(capturedScheduleId, row.id);
    },
  );
}
