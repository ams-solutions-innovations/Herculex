/// Pure bitmask + wall-clock-time math for [FastingSchedules] rows, kept
/// dependency-free so it's trivially unit-testable without a database.
/// Weekday bits follow Dart's `DateTime.weekday` (Mon=1..Sun=7): bit
/// `weekday - 1`, so Monday is bit 0 and Sunday is bit 6.
library;

import 'fasting_plan.dart';

const List<String> kWeekdayAbbrev = [
  'Mon',
  'Tue',
  'Wed',
  'Thu',
  'Fri',
  'Sat',
  'Sun',
];

const int kAllWeekdays = 0x7F;
const int kWeekdayBits = 0x1F; // Mon-Fri: bits 0-4
const int kWeekendBits = 0x60; // Sat-Sun: bits 5-6

int weekdayBit(int weekday) => 1 << (weekday - 1);

bool hasWeekday(int daysOfWeek, int weekday) =>
    daysOfWeek & weekdayBit(weekday) != 0;

int toggleWeekday(int daysOfWeek, int weekday) =>
    daysOfWeek ^ weekdayBit(weekday);

/// The next wall-clock instant on/after [from] that matches [daysOfWeek] at
/// [startTimeMinutes] (minutes since midnight). Scans at most 8 calendar
/// days — enough to always land on a match when at least one bit is set,
/// since day 7 revisits `from`'s own weekday. Returns null when
/// [daysOfWeek] is 0 (no days selected).
DateTime? nextOccurrence({
  required int daysOfWeek,
  required int startTimeMinutes,
  required DateTime from,
}) {
  if (daysOfWeek == 0) return null;
  final hour = startTimeMinutes ~/ 60;
  final minute = startTimeMinutes % 60;

  for (var offset = 0; offset <= 7; offset++) {
    final day = DateTime(from.year, from.month, from.day + offset);
    if (!hasWeekday(daysOfWeek, day.weekday)) continue;
    final candidate = DateTime(day.year, day.month, day.day, hour, minute);
    if (candidate.isBefore(from)) continue;
    return candidate;
  }
  return null; // unreachable while daysOfWeek != 0
}

/// The next [count] occurrences on/after [from], for schedule-editor
/// previews. Each result seeds the next search one minute later so a
/// same-minute match is never returned twice.
List<DateTime> nextOccurrences({
  required int daysOfWeek,
  required int startTimeMinutes,
  required DateTime from,
  int count = 3,
}) {
  final result = <DateTime>[];
  var cursor = from;
  for (var i = 0; i < count; i++) {
    final next = nextOccurrence(
      daysOfWeek: daysOfWeek,
      startTimeMinutes: startTimeMinutes,
      from: cursor,
    );
    if (next == null) break;
    result.add(next);
    cursor = next.add(const Duration(minutes: 1));
  }
  return result;
}

String formatStartTime(int startTimeMinutes) {
  final hour = (startTimeMinutes ~/ 60) % 24;
  final minute = startTimeMinutes % 60;
  return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}

/// Compact display for a set of selected weekdays, e.g. "Weekdays",
/// "Weekends", "Every day", or "Mon · Wed · Fri".
String formatDaysOfWeek(int daysOfWeek) {
  if (daysOfWeek == 0) return 'Never';
  if (daysOfWeek == kAllWeekdays) return 'Every day';
  if (daysOfWeek == kWeekdayBits) return 'Weekdays';
  if (daysOfWeek == kWeekendBits) return 'Weekends';
  return [
    for (var weekday = 1; weekday <= 7; weekday++)
      if (hasWeekday(daysOfWeek, weekday)) kWeekdayAbbrev[weekday - 1],
  ].join(' · ');
}

/// Resolves a stored `planName` (a [FastingPlan] enum name) back to its
/// plan, falling back to 16:8 for corrupted/unknown data rather than
/// throwing — a schedule row surviving with a slightly wrong plan is far
/// better than one that crashes the list page.
FastingPlan resolveSchedulePlan(String planName) {
  return FastingPlan.values.firstWhere(
    (p) => p.name == planName,
    orElse: () => FastingPlan.h16,
  );
}

/// Resolves a schedule's actual target duration: the plan's own target,
/// or [customTargetSeconds] when the plan is [FastingPlan.custom].
int resolveScheduleTargetSeconds(String planName, int? customTargetSeconds) {
  final plan = resolveSchedulePlan(planName);
  if (plan == FastingPlan.custom) {
    return customTargetSeconds ?? FastingPlan.h16.targetSeconds;
  }
  return plan.targetSeconds;
}
