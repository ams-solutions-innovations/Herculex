/// ISO 8601 week identity for the weekly report (D-04, D-05, D-09, RPT-01).
///
/// An [IsoWeek] is the key of the persisted report row and the window every
/// calculator reads. Year boundaries and DST are the two ways this goes wrong,
/// so:
///
/// * the ISO year and week come from the Thursday rule (the Thursday of a
///   date's week decides the ISO year), so 2026-12-31 and 2027-01-01 are both
///   2026-W53 and 2024-12-30 is 2025-W01;
/// * day differences are taken between UTC-normalised dates, never between two
///   local `DateTime`s (a DST change makes `inDays` off by one);
/// * window boundaries are built with the `DateTime(y, m, d + n)` constructor,
///   never `Duration` arithmetic, so local midnight cannot drift.
///
/// Pure Dart. Never reads the wall clock: every time-dependent method takes the
/// instant as a parameter, per the Clock rule.
library;

/// One ISO 8601 week, identified by `(isoYear, isoWeek)`.
class IsoWeek implements Comparable<IsoWeek> {
  const IsoWeek(this.isoYear, this.isoWeek);

  /// The ISO week containing [d] (its calendar date; time of day is ignored).
  factory IsoWeek.fromDate(DateTime d) {
    // Thursday of d's week decides the ISO year.
    final thursday = DateTime(
      d.year,
      d.month,
      d.day + (DateTime.thursday - d.weekday),
    );
    final dayOfYear =
        _utcDays(thursday) - _utcDays(DateTime(thursday.year, 1, 1));
    return IsoWeek(thursday.year, dayOfYear ~/ 7 + 1);
  }

  /// Returns the week, or null when it cannot exist (week 0, week 53 in a
  /// 52-week year, year outside 2000..2100). Router and deep-link input is
  /// untrusted, so callers use this rather than the constructor.
  static IsoWeek? tryCreate(int isoYear, int isoWeek) {
    if (isoYear < 2000 || isoYear > 2100) return null;
    if (isoWeek < 1 || isoWeek > weeksInYear(isoYear)) return null;
    return IsoWeek(isoYear, isoWeek);
  }

  /// 52 or 53: the ISO week number of 28 December is always the last week.
  static int weeksInYear(int isoYear) =>
      IsoWeek.fromDate(DateTime(isoYear, 12, 28)).isoWeek;

  final int isoYear;
  final int isoWeek;

  /// Monday 00:00 local.
  DateTime get start {
    final jan4 = DateTime(isoYear, 1, 4);
    final week1Monday = 4 - (jan4.weekday - DateTime.monday);
    return DateTime(isoYear, 1, week1Monday + (isoWeek - 1) * 7);
  }

  /// Next Monday 00:00 local; the window is `[start, endExclusive)`.
  DateTime get endExclusive {
    final s = start;
    return DateTime(s.year, s.month, s.day + 7);
  }

  /// Monday as `yyyy-MM-dd`.
  String get startIso => _dateIso(start);

  /// Sunday as `yyyy-MM-dd`.
  String get endIso {
    final s = start;
    return _dateIso(DateTime(s.year, s.month, s.day + 6));
  }

  IsoWeek get previous {
    final s = start;
    return IsoWeek.fromDate(DateTime(s.year, s.month, s.day - 7));
  }

  /// The effective end of the data window: [now] while the week is running,
  /// [endExclusive] once it is over.
  DateTime windowEnd(DateTime now) {
    final end = endExclusive;
    return now.isBefore(end) ? now : end;
  }

  bool isAfter(IsoWeek other) => compareTo(other) > 0;

  /// Whether a report for this week may be frozen at [now] (RPT-04).
  ///
  /// True once the week has ended, or on its Sunday at/after [timeHHMM] (the
  /// weekly-report time; malformed input falls back to 18:00). False for a
  /// future week and for any earlier moment of the running week, so a mid-week
  /// open never freezes a partial week.
  bool isSnapshotDue(DateTime now, String timeHHMM) {
    if (!now.isBefore(endExclusive)) return true;
    if (start.isAfter(now)) return false;
    if (now.weekday != DateTime.sunday) return false;
    final (hour, minute) = _parseHHMM(timeHHMM);
    final due = DateTime(now.year, now.month, now.day, hour, minute);
    return !now.isBefore(due);
  }

  /// The week a weekly-report notification tap should open (D-05, D-09).
  ///
  /// The notification is a repeating `dayOfWeekAndTime` one, so its payload is
  /// static and cannot name a week. This is therefore the only place the
  /// target week is decided: the ISO week containing the most recent
  /// Sunday-at-[timeHHMM] instant that is `<= now`. A malformed or
  /// out-of-range time falls back to 18:00.
  static IsoWeek forNotificationTap(DateTime now, String timeHHMM) {
    final (hour, minute) = _parseHHMM(timeHHMM);
    // Sunday has weekday 7; walk back to the nearest Sunday on or before today.
    final daysBack = now.weekday % 7;
    var trigger = DateTime(
      now.year,
      now.month,
      now.day - daysBack,
      hour,
      minute,
    );
    if (trigger.isAfter(now)) {
      trigger = DateTime(
        trigger.year,
        trigger.month,
        trigger.day - 7,
        hour,
        minute,
      );
    }
    return IsoWeek.fromDate(trigger);
  }

  @override
  int compareTo(IsoWeek other) {
    final byYear = isoYear.compareTo(other.isoYear);
    return byYear != 0 ? byYear : isoWeek.compareTo(other.isoWeek);
  }

  @override
  bool operator ==(Object other) =>
      other is IsoWeek && other.isoYear == isoYear && other.isoWeek == isoWeek;

  @override
  int get hashCode => Object.hash(isoYear, isoWeek);

  @override
  String toString() => '$isoYear-W${isoWeek.toString().padLeft(2, '0')}';
}

const _defaultTime = (18, 0);

(int, int) _parseHHMM(String s) {
  final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(s.trim());
  if (m == null) return _defaultTime;
  final h = int.parse(m.group(1)!);
  final min = int.parse(m.group(2)!);
  if (h > 23 || min > 59) return _defaultTime;
  return (h, min);
}

/// Whole days since the epoch for the calendar date of [d], DST-proof.
int _utcDays(DateTime d) =>
    DateTime.utc(d.year, d.month, d.day).millisecondsSinceEpoch ~/
    Duration.millisecondsPerDay;

String _dateIso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';
