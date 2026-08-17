import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/fasting/domain/fasting_plan.dart';
import 'package:herculex/features/fasting/domain/fasting_schedule_occurrence.dart';

void main() {
  group('weekday bitmask helpers', () {
    test('weekdayBit matches DateTime.weekday (Mon=1..Sun=7)', () {
      expect(weekdayBit(DateTime.monday), 1 << 0);
      expect(weekdayBit(DateTime.sunday), 1 << 6);
    });

    test('hasWeekday reads the right bit', () {
      const mask = 0x05; // Mon + Wed
      expect(hasWeekday(mask, DateTime.monday), isTrue);
      expect(hasWeekday(mask, DateTime.tuesday), isFalse);
      expect(hasWeekday(mask, DateTime.wednesday), isTrue);
    });

    test('toggleWeekday flips only the target bit', () {
      var mask = 0;
      mask = toggleWeekday(mask, DateTime.friday);
      expect(hasWeekday(mask, DateTime.friday), isTrue);
      expect(mask, weekdayBit(DateTime.friday));
      mask = toggleWeekday(mask, DateTime.friday);
      expect(mask, 0);
    });
  });

  group('nextOccurrence', () {
    test('returns null when no days are selected', () {
      final result = nextOccurrence(
        daysOfWeek: 0,
        startTimeMinutes: 20 * 60,
        from: DateTime(2026, 8, 14),
      );
      expect(result, isNull);
    });

    test('same-day match when the time has not passed yet', () {
      // 2026-08-14 is a Friday.
      final from = DateTime(2026, 8, 14, 9, 0);
      final result = nextOccurrence(
        daysOfWeek: weekdayBit(DateTime.friday),
        startTimeMinutes: 20 * 60,
        from: from,
      );
      expect(result, DateTime(2026, 8, 14, 20, 0));
    });

    test('rolls to next week when the same-day time already passed', () {
      final from = DateTime(2026, 8, 14, 21, 0); // Friday, after 20:00
      final result = nextOccurrence(
        daysOfWeek: weekdayBit(DateTime.friday),
        startTimeMinutes: 20 * 60,
        from: from,
      );
      expect(result, DateTime(2026, 8, 21, 20, 0));
    });

    test('picks the nearest of several selected days', () {
      // Friday 2026-08-14; Mon+Wed selected -> next is Monday 2026-08-17.
      final from = DateTime(2026, 8, 14, 9, 0);
      final result = nextOccurrence(
        daysOfWeek: weekdayBit(DateTime.monday) | weekdayBit(DateTime.wednesday),
        startTimeMinutes: 7 * 60,
        from: from,
      );
      expect(result, DateTime(2026, 8, 17, 7, 0));
    });

    test('crosses a year boundary correctly', () {
      // 2026-12-30 is a Wednesday; next Friday lands in January 2027.
      final from = DateTime(2026, 12, 30, 9, 0);
      final result = nextOccurrence(
        daysOfWeek: weekdayBit(DateTime.friday),
        startTimeMinutes: 8 * 60,
        from: from,
      );
      expect(result, DateTime(2027, 1, 1, 8, 0));
    });
  });

  group('nextOccurrences', () {
    test('returns count consecutive matches, each a week apart for a single day', () {
      final from = DateTime(2026, 8, 14, 9, 0); // Friday
      final results = nextOccurrences(
        daysOfWeek: weekdayBit(DateTime.friday),
        startTimeMinutes: 20 * 60,
        from: from,
        count: 3,
      );
      expect(results, [
        DateTime(2026, 8, 14, 20, 0),
        DateTime(2026, 8, 21, 20, 0),
        DateTime(2026, 8, 28, 20, 0),
      ]);
    });

    test('returns an empty list when no days are selected', () {
      final results = nextOccurrences(
        daysOfWeek: 0,
        startTimeMinutes: 20 * 60,
        from: DateTime(2026, 8, 14),
      );
      expect(results, isEmpty);
    });
  });

  group('formatting', () {
    test('formatStartTime pads hour and minute', () {
      expect(formatStartTime(5 * 60 + 3), '05:03');
      expect(formatStartTime(20 * 60), '20:00');
    });

    test('formatDaysOfWeek recognizes the named presets', () {
      expect(formatDaysOfWeek(0), 'Never');
      expect(formatDaysOfWeek(kAllWeekdays), 'Every day');
      expect(formatDaysOfWeek(kWeekdayBits), 'Weekdays');
      expect(formatDaysOfWeek(kWeekendBits), 'Weekends');
    });

    test('formatDaysOfWeek lists an arbitrary combination in Mon..Sun order', () {
      final mask = weekdayBit(DateTime.friday) | weekdayBit(DateTime.monday);
      expect(formatDaysOfWeek(mask), 'Mon · Fri');
    });
  });

  group('plan resolution', () {
    test('resolveSchedulePlan round-trips every real plan name', () {
      for (final plan in FastingPlan.values) {
        expect(resolveSchedulePlan(plan.name), plan);
      }
    });

    test('resolveSchedulePlan falls back to 16:8 for unknown data', () {
      expect(resolveSchedulePlan('not_a_real_plan'), FastingPlan.h16);
    });

    test('resolveScheduleTargetSeconds uses the plan target for presets', () {
      expect(
        resolveScheduleTargetSeconds(FastingPlan.h18.name, null),
        FastingPlan.h18.targetSeconds,
      );
    });

    test('resolveScheduleTargetSeconds uses customTargetSeconds for custom', () {
      expect(
        resolveScheduleTargetSeconds(FastingPlan.custom.name, 20 * 3600),
        20 * 3600,
      );
    });

    test('resolveScheduleTargetSeconds falls back to 16h when custom has no value', () {
      expect(
        resolveScheduleTargetSeconds(FastingPlan.custom.name, null),
        16 * 3600,
      );
    });
  });
}
