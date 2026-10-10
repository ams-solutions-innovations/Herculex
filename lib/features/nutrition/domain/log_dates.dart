/// The dates a new diary entry is written to when the user picks "Add to
/// multiple days", optionally repeated over several weeks.
///
/// Every chosen day (the [base] date plus [extraDays]) is repeated once per
/// week for [weeks] weeks, so `weeks: 1` is the plain one-week behaviour. The
/// result is date-only, de-duplicated and sorted.
List<DateTime> expandLogDates({
  required DateTime base,
  Set<DateTime> extraDays = const {},
  int weeks = 1,
}) {
  final count = weeks < 1 ? 1 : weeks;
  final dates = <DateTime>{};
  for (final day in {base, ...extraDays}) {
    for (var week = 0; week < count; week++) {
      // Calendar arithmetic, not Duration: adding 7 * 24h would drift an hour
      // across a DST change and land on the wrong day.
      dates.add(DateTime(day.year, day.month, day.day + 7 * week));
    }
  }
  return dates.toList()..sort();
}

/// Week counts offered by the "repeat" control, and the default.
const List<int> kRepeatWeekOptions = [2, 4, 8, 12];
const int kDefaultRepeatWeeks = 4;
