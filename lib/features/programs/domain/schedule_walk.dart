/// Turns a program's day slots into concrete calendar offsets.
///
/// Pure Dart — no Flutter, no drift. `ProgramsRepository.materializeProgram`
/// feeds the result straight into `ScheduledWorkouts` rows.
library;

import 'split_template.dart';

/// One materialized occurrence of a program day.
class PlannedOccurrence {
  const PlannedOccurrence({
    required this.dayIndex,
    required this.dayOffset,
    required this.weekIndex,
    required this.occurrenceIndex,
  });

  /// The `SplitDaySpec.index` / `ProgramDays` slot this came from — `dayOfWeek
  /// - 1` for weekly programs, `cycleDayIndex` for cycle ones.
  final int dayIndex;

  /// Days after the program's start date.
  final int dayOffset;

  /// Calendar week this offset falls in, clamped to the program's length. Used
  /// to pick the `ProgramWeeks` row, so periodization stays anchored to weeks
  /// even when the rotation is not 7 days long.
  final int weekIndex;

  /// Which repetition of this day produced the occurrence: the week number for
  /// weekly programs, the cycle number for rotating ones. Together with the
  /// program day it forms the identity key that lets re-materializing skip rows
  /// the user has already touched.
  final int occurrenceIndex;

  @override
  String toString() =>
      'PlannedOccurrence(day: $dayIndex, +$dayOffset d, week: $weekIndex, '
      'occ: $occurrenceIndex)';
}

abstract final class ScheduleWalker {
  /// Expands [dayIndices] over [totalWeeks] calendar weeks.
  ///
  /// Weekly mode aligns week 0 to the Monday of the start date's week, then
  /// drops any occurrence that would land before the start date — so starting a
  /// Mon/Wed/Fri program on a Wednesday gives you Wed and Fri in week 0 rather
  /// than silently shifting the whole plan off its weekdays.
  ///
  /// Cycle mode ignores [startWeekday] entirely: the rotation begins on the
  /// start date and repeats every [cycleLength] days.
  static List<PlannedOccurrence> walk({
    required ScheduleMode mode,
    required List<int> dayIndices,
    required int totalWeeks,
    int cycleLength = 7,
    int startWeekday = DateTime.monday,
  }) {
    if (dayIndices.isEmpty || totalWeeks < 1) return const [];
    final sorted = dayIndices.toList()..sort();
    final horizon = totalWeeks * 7;
    final out = <PlannedOccurrence>[];

    if (mode == ScheduleMode.weekly) {
      // Offset from the start date back to the Monday of its week.
      final mondayShift = startWeekday - DateTime.monday;
      for (var w = 0; w < totalWeeks; w++) {
        for (final d in sorted) {
          final offset = w * 7 + d - mondayShift;
          if (offset < 0 || offset >= horizon) continue;
          out.add(
            PlannedOccurrence(
              dayIndex: d,
              dayOffset: offset,
              weekIndex: w,
              occurrenceIndex: w,
            ),
          );
        }
      }
    } else {
      final length = cycleLength < 1 ? 1 : cycleLength;
      for (var c = 0; c * length < horizon; c++) {
        for (final d in sorted) {
          final offset = c * length + d;
          if (offset >= horizon) continue;
          out.add(
            PlannedOccurrence(
              dayIndex: d,
              dayOffset: offset,
              weekIndex: (offset ~/ 7).clamp(0, totalWeeks - 1),
              occurrenceIndex: c,
            ),
          );
        }
      }
    }

    out.sort((a, b) {
      final byOffset = a.dayOffset.compareTo(b.dayOffset);
      return byOffset != 0 ? byOffset : a.dayIndex.compareTo(b.dayIndex);
    });
    return out;
  }
}
