import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/programs/domain/schedule_walk.dart';
import 'package:herculex/features/programs/domain/split_template.dart';

void main() {
  group('SplitTemplates.generate — weekly', () {
    test('PPL over 6 days repeats the slots round-robin', () {
      final plan = SplitTemplates.generate(
        type: SplitType.ppl,
        daysPerWeek: 6,
      );

      expect(plan.mode, ScheduleMode.weekly);
      expect(plan.cycleLength, 7);
      expect(plan.days.map((d) => d.label), [
        'Push',
        'Pull',
        'Legs',
        'Push',
        'Pull',
        'Legs',
      ]);
      // Mon–Sat, Sunday off.
      expect(plan.days.map((d) => d.dayOfWeek), [1, 2, 3, 4, 5, 6]);
      // Both Push days share slot 0, so they can share one template.
      expect(plan.days.map((d) => d.slotIndex), [0, 1, 2, 0, 1, 2]);
      expect(plan.slotSummary.map((s) => s.label), ['Push', 'Pull', 'Legs']);
    });

    test('Upper/Lower over 4 days spaces onto Mon, Tue, Thu, Fri', () {
      final plan = SplitTemplates.generate(
        type: SplitType.upperLower,
        daysPerWeek: 4,
      );

      expect(plan.days.map((d) => d.dayOfWeek), [1, 2, 4, 5]);
      expect(plan.days.map((d) => d.label), [
        'Upper',
        'Lower',
        'Upper',
        'Lower',
      ]);
    });

    test('bro split over 5 days uses five distinct slots', () {
      final plan = SplitTemplates.generate(
        type: SplitType.broSplit,
        daysPerWeek: 5,
      );

      expect(plan.days.map((d) => d.label), [
        'Chest',
        'Back',
        'Legs',
        'Shoulders',
        'Arms',
      ]);
      expect(plan.slotSummary, hasLength(5));
    });

    test('preferred weekdays override the spacing table', () {
      final plan = SplitTemplates.generate(
        type: SplitType.fullBody,
        daysPerWeek: 3,
        preferredWeekdays: [2, 6, 7],
      );

      expect(plan.days.map((d) => d.dayOfWeek), [2, 6, 7]);
    });

    test('custom with no slots supplied numbers the days', () {
      final plan = SplitTemplates.generate(
        type: SplitType.custom,
        daysPerWeek: 3,
      );

      expect(plan.days.map((d) => d.label), ['Day 1', 'Day 2', 'Day 3']);
    });

    test('custom slots are used verbatim and cycle round-robin', () {
      final plan = SplitTemplates.generate(
        type: SplitType.custom,
        daysPerWeek: 4,
        customSlots: ['Strength', 'Conditioning'],
      );

      expect(plan.days.map((d) => d.label), [
        'Strength',
        'Conditioning',
        'Strength',
        'Conditioning',
      ]);
    });

    test('weekly plans emit training days only', () {
      final plan = SplitTemplates.generate(
        type: SplitType.ppl,
        daysPerWeek: 3,
      );

      expect(plan.days.any((d) => d.isRest), isFalse);
      expect(plan.trainingDayCount, 3);
    });
  });

  group('SplitTemplates.generate — cycle', () {
    test('A/B alternating is a two-day cycle with no rest', () {
      final plan = SplitTemplates.generate(
        type: SplitType.ab,
        daysPerWeek: 2,
        mode: ScheduleMode.cycle,
        cycleLength: 2,
      );

      expect(plan.cycleLength, 2);
      expect(plan.days.map((d) => d.label), ['A', 'B']);
      expect(plan.days.any((d) => d.isRest), isFalse);
    });

    test('PPL x2 on 6-on-1-off fills a 7-day cycle with one rest slot', () {
      final plan = SplitTemplates.generate(
        type: SplitType.ppl,
        daysPerWeek: 6,
        mode: ScheduleMode.cycle,
        cycleLength: 7,
      );

      expect(plan.days, hasLength(7));
      expect(plan.trainingDayCount, 6);
      expect(plan.days.last.isRest, isTrue);
      expect(plan.days.last.slotIndex, -1);
      expect(plan.trainingDays.map((d) => d.label), [
        'Push',
        'Pull',
        'Legs',
        'Push',
        'Pull',
        'Legs',
      ]);
    });

    test('cycle length defaults to one trailing rest day', () {
      final plan = SplitTemplates.generate(
        type: SplitType.ppl,
        daysPerWeek: 3,
        mode: ScheduleMode.cycle,
      );

      expect(plan.cycleLength, 4);
      expect(plan.days.where((d) => d.isRest), hasLength(1));
    });

    test('a cycle length below the training days is ignored', () {
      final plan = SplitTemplates.generate(
        type: SplitType.ppl,
        daysPerWeek: 5,
        mode: ScheduleMode.cycle,
        cycleLength: 2,
      );

      expect(plan.cycleLength, 6);
      expect(plan.trainingDayCount, 5);
    });
  });

  group('ScheduleWalker — weekly', () {
    test('expands a 3-day week over 4 weeks onto the right offsets', () {
      final plan = SplitTemplates.generate(
        type: SplitType.ppl,
        daysPerWeek: 3,
      );
      final occ = ScheduleWalker.walk(
        mode: ScheduleMode.weekly,
        dayIndices: plan.days.map((d) => d.index).toList(),
        totalWeeks: 4,
      );

      expect(occ, hasLength(12));
      // Starting on a Monday: Mon/Wed/Fri = offsets 0, 2, 4 then +7 each week.
      expect(occ.take(6).map((o) => o.dayOffset), [0, 2, 4, 7, 9, 11]);
      expect(occ.map((o) => o.weekIndex).toSet(), {0, 1, 2, 3});
      expect(occ.every((o) => o.weekIndex < 4), isTrue);
    });

    test('starting mid-week keeps weekdays and drops the past days', () {
      final plan = SplitTemplates.generate(
        type: SplitType.ppl,
        daysPerWeek: 3,
      );
      // Start on a Wednesday: Monday of week 0 is already behind us.
      final occ = ScheduleWalker.walk(
        mode: ScheduleMode.weekly,
        dayIndices: plan.days.map((d) => d.index).toList(),
        totalWeeks: 2,
        startWeekday: DateTime.wednesday,
      );

      // Week 0 contributes Wed (+0) and Fri (+2) only.
      expect(occ.take(2).map((o) => o.dayOffset), [0, 2]);
      expect(occ, hasLength(5));
      // Every offset still lands on the intended weekday.
      for (final o in occ) {
        final weekday =
            ((DateTime.wednesday - 1 + o.dayOffset) % 7) + 1;
        expect(weekday, o.dayIndex + 1);
      }
    });

    test('occurrence index is the repetition number of the day', () {
      final occ = ScheduleWalker.walk(
        mode: ScheduleMode.weekly,
        dayIndices: const [0],
        totalWeeks: 3,
      );

      expect(occ.map((o) => o.occurrenceIndex), [0, 1, 2]);
    });

    test('no occurrence escapes the program horizon', () {
      final occ = ScheduleWalker.walk(
        mode: ScheduleMode.weekly,
        dayIndices: const [0, 2, 4, 6],
        totalWeeks: 3,
        startWeekday: DateTime.sunday,
      );

      expect(occ.every((o) => o.dayOffset < 21), isTrue);
      expect(occ.every((o) => o.dayOffset >= 0), isTrue);
    });
  });

  group('ScheduleWalker — cycle', () {
    test('A/B alternates every day regardless of the weekday', () {
      final occ = ScheduleWalker.walk(
        mode: ScheduleMode.cycle,
        dayIndices: const [0, 1],
        cycleLength: 2,
        totalWeeks: 2,
        startWeekday: DateTime.thursday,
      );

      expect(occ, hasLength(14));
      expect(occ.map((o) => o.dayOffset), List.generate(14, (i) => i));
      // Even offsets are slot A, odd are slot B — no weekday involved.
      expect(occ.where((o) => o.dayIndex == 0).map((o) => o.dayOffset),
          [0, 2, 4, 6, 8, 10, 12]);
      expect(occ.map((o) => o.occurrenceIndex).toSet(), List.generate(7, (i) => i).toSet());
    });

    test('a 4-day cycle drifts the rest day across weekdays', () {
      // PPL + 1 rest = a 4-day rotation, which does NOT divide 7.
      final plan = SplitTemplates.generate(
        type: SplitType.ppl,
        daysPerWeek: 3,
        mode: ScheduleMode.cycle,
      );
      final occ = ScheduleWalker.walk(
        mode: ScheduleMode.cycle,
        dayIndices: plan.trainingDays.map((d) => d.index).toList(),
        cycleLength: plan.cycleLength,
        totalWeeks: 4,
        startWeekday: DateTime.wednesday,
      );

      // Training offsets are every 4 days minus the rest slot: 0,1,2, 4,5,6, ...
      expect(occ.take(6).map((o) => o.dayOffset), [0, 1, 2, 4, 5, 6]);

      // The weekday a given slot lands on must change over the rotation —
      // this is what proves cycle mode is not secretly weekly.
      final pushWeekdays = occ
          .where((o) => o.dayIndex == 0)
          .map((o) => ((DateTime.wednesday - 1 + o.dayOffset) % 7) + 1)
          .toSet();
      expect(pushWeekdays.length, greaterThan(1));
    });

    test('a 7-day cycle lines up with calendar weeks', () {
      final occ = ScheduleWalker.walk(
        mode: ScheduleMode.cycle,
        dayIndices: const [0, 1, 2, 3, 4, 5],
        cycleLength: 7,
        totalWeeks: 3,
        startWeekday: DateTime.wednesday,
      );

      final firstSlotWeekdays = occ
          .where((o) => o.dayIndex == 0)
          .map((o) => ((DateTime.wednesday - 1 + o.dayOffset) % 7) + 1)
          .toSet();
      expect(firstSlotWeekdays, hasLength(1));
    });

    test('week index is clamped to the program length', () {
      final occ = ScheduleWalker.walk(
        mode: ScheduleMode.cycle,
        dayIndices: const [0],
        cycleLength: 3,
        totalWeeks: 2,
      );

      expect(occ.every((o) => o.weekIndex >= 0 && o.weekIndex < 2), isTrue);
    });
  });
}
