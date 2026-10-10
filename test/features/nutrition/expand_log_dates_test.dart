import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/nutrition/domain/log_dates.dart';

void main() {
  group('expandLogDates', () {
    test('one week is the base day plus the extra days', () {
      final dates = expandLogDates(
        base: DateTime(2026, 10, 7),
        extraDays: {DateTime(2026, 10, 9)},
      );
      expect(dates, [DateTime(2026, 10, 7), DateTime(2026, 10, 9)]);
    });

    test('no extra days and one week is just the base day', () {
      expect(expandLogDates(base: DateTime(2026, 10, 7)), [
        DateTime(2026, 10, 7),
      ]);
    });

    test('repeats every chosen day once per week', () {
      final dates = expandLogDates(
        base: DateTime(2026, 10, 5),
        extraDays: {DateTime(2026, 10, 7)},
        weeks: 4,
      );
      expect(dates, hasLength(8));
      expect(dates.first, DateTime(2026, 10, 5));
      expect(dates.last, DateTime(2026, 10, 28));
      expect(dates.every((d) => d.weekday == 1 || d.weekday == 3), isTrue);
    });

    test('keeps the weekday across a month and year boundary', () {
      final dates = expandLogDates(base: DateTime(2026, 12, 28), weeks: 3);
      expect(dates, [
        DateTime(2026, 12, 28),
        DateTime(2027, 1, 4),
        DateTime(2027, 1, 11),
      ]);
    });

    test('keeps the calendar day across a DST change', () {
      // Europe/Ljubljana moves clocks on 2026-10-25; a Duration-based +7 days
      // would turn midnight into 23:00 of the previous day.
      final dates = expandLogDates(base: DateTime(2026, 10, 24), weeks: 2);
      expect(dates, [DateTime(2026, 10, 24), DateTime(2026, 10, 31)]);
    });

    test('drops duplicates and ignores a time of day', () {
      final dates = expandLogDates(
        base: DateTime(2026, 10, 7, 18, 30),
        extraDays: {DateTime(2026, 10, 7), DateTime(2026, 10, 14)},
        weeks: 2,
      );
      expect(dates, [
        DateTime(2026, 10, 7),
        DateTime(2026, 10, 14),
        DateTime(2026, 10, 21),
      ]);
    });

    test('a non-positive week count behaves like one week', () {
      expect(expandLogDates(base: DateTime(2026, 10, 7), weeks: 0), [
        DateTime(2026, 10, 7),
      ]);
    });
  });
}
