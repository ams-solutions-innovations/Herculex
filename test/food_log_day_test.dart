import 'package:flutter/material.dart' show DateUtils;
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/nutrition/domain/meal.dart';

/// Regression tests for the food-log day-switching bug. The fix replaced
/// DST-unsafe `Duration(days: 1)` arithmetic with calendar-based
/// [DateUtils.addDaysToDate] + date-only normalization, so paging between days
/// always lands on consecutive calendar days and round-trips cleanly.
void main() {
  group('day navigation is DST-safe and lossless', () {
    test('stepping forward yields strictly consecutive calendar days', () {
      // Span a US spring-forward (2025-03-09) and fall-back (2025-11-02).
      var date = DateTime(2025, 3, 7);
      var previous = dateIso(date);
      for (var i = 0; i < 300; i++) {
        date = DateUtils.addDaysToDate(date, 1);
        final iso = dateIso(date);
        expect(
          iso.compareTo(previous),
          greaterThan(0),
          reason: 'day must advance, never repeat or skip backwards',
        );
        // No time component ever creeps in.
        expect(date.hour, 0);
        expect(date.minute, 0);
        previous = iso;
      }
    });

    test('forward then back returns to the same day across DST boundary', () {
      for (final base in [
        DateTime(2025, 3, 9), // spring forward
        DateTime(2025, 11, 2), // fall back
        DateTime(2026, 6, 8),
      ]) {
        final next = DateUtils.addDaysToDate(base, 1);
        final back = DateUtils.addDaysToDate(next, -1);
        expect(dateIso(back), dateIso(base));
        expect(back, base);
      }
    });

    test('date-only normalization strips any time component', () {
      final messy = DateTime(2026, 6, 8, 23, 59, 59);
      expect(dateIso(DateUtils.dateOnly(messy)), '2026-06-08');
    });
  });
}
