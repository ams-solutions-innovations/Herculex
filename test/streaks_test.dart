import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/dashboard/domain/streaks.dart';

void main() {
  // Wednesday.
  final today = DateTime(2026, 7, 29, 14, 30);

  DateTime daysAgo(int n) => today.subtract(Duration(days: n));

  group('StreakCalculator.daily', () {
    test('no activity yields the zero streak', () {
      expect(StreakCalculator.daily(const [], today).current, 0);
      expect(StreakCalculator.daily(const [], today).activeToday, isFalse);
    });

    test('counts consecutive days ending today', () {
      final s = StreakCalculator.daily(
          [daysAgo(0), daysAgo(1), daysAgo(2)], today);
      expect(s.current, 3);
      expect(s.activeToday, isTrue);
    });

    test('a run ending yesterday is still current but not active today', () {
      final s = StreakCalculator.daily([daysAgo(1), daysAgo(2)], today);
      expect(s.current, 2);
      expect(s.activeToday, isFalse);
    });

    test('a gap of two days breaks the run', () {
      final s = StreakCalculator.daily([daysAgo(3), daysAgo(4)], today);
      expect(s.current, 0);
    });

    test('ignores time-of-day when bucketing into days', () {
      final s = StreakCalculator.daily([
        DateTime(2026, 7, 29, 0, 5),
        DateTime(2026, 7, 29, 23, 55),
        DateTime(2026, 7, 28, 12),
      ], today);
      expect(s.current, 2);
    });

    test('best tracks the longest run even after it is broken', () {
      final s = StreakCalculator.daily([
        daysAgo(0),
        // 4-day run further back.
        daysAgo(5), daysAgo(6), daysAgo(7), daysAgo(8),
      ], today);
      expect(s.current, 1);
      expect(s.best, 4);
    });
  });

  group('StreakCalculator.weekly', () {
    test('a rest day does not break the run', () {
      // One session this week (Mon) and one last week — no session yesterday.
      final s = StreakCalculator.weekly(
          [DateTime(2026, 7, 27), DateTime(2026, 7, 21)], today);
      expect(s.current, 2);
      expect(s.activeToday, isTrue);
    });

    test('multiple sessions in one week count once', () {
      final s = StreakCalculator.weekly(
          [DateTime(2026, 7, 27), DateTime(2026, 7, 28), DateTime(2026, 7, 29)],
          today);
      expect(s.current, 1);
    });

    test('a run ending last week is still current', () {
      final s = StreakCalculator.weekly(
          [DateTime(2026, 7, 21), DateTime(2026, 7, 14)], today);
      expect(s.current, 2);
      expect(s.activeToday, isFalse);
    });

    test('skipping a whole week breaks the run', () {
      final s = StreakCalculator.weekly(
          [DateTime(2026, 7, 14), DateTime(2026, 7, 7)], today);
      expect(s.current, 0);
      expect(s.best, 2);
    });
  });
}
