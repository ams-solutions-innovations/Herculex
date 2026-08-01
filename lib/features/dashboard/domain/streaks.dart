/// Consecutive-activity counters shown on the dashboard (§18).
class Streak {
  /// Length of the current run, in [unit]s.
  final int current;

  /// Longest run ever recorded, for context under the headline number.
  final int best;

  /// True when the run includes today — a streak that ended yesterday is still
  /// alive (the day isn't over) but shouldn't show the "active" flame.
  final bool activeToday;

  const Streak({
    required this.current,
    required this.best,
    required this.activeToday,
  });

  static const zero = Streak(current: 0, best: 0, activeToday: false);
}

/// Builds day- and week-granularity streaks from a set of activity dates.
class StreakCalculator {
  /// Consecutive days ending today or yesterday. Counting a run that ended
  /// yesterday as still-current avoids a streak that appears to reset every
  /// morning before the user has logged anything.
  static Streak daily(Iterable<DateTime> activityDates, DateTime today) {
    final days = {
      for (final d in activityDates) DateTime(d.year, d.month, d.day),
    };
    if (days.isEmpty) return Streak.zero;

    final anchor = DateTime(today.year, today.month, today.day);
    final activeToday = days.contains(anchor);
    final yesterday = anchor.subtract(const Duration(days: 1));

    var current = 0;
    if (activeToday || days.contains(yesterday)) {
      var cursor = activeToday ? anchor : yesterday;
      while (days.contains(cursor)) {
        current++;
        cursor = cursor.subtract(const Duration(days: 1));
      }
    }

    return Streak(
      current: current,
      best: _longestRun(days, const Duration(days: 1)),
      activeToday: activeToday,
    );
  }

  /// Consecutive weeks (Mon–Sun) containing at least one activity, ending this
  /// week or last. Training is planned per week, so a rest day must not break
  /// a workout streak the way it would break a food-logging streak.
  static Streak weekly(Iterable<DateTime> activityDates, DateTime today) {
    final weeks = {for (final d in activityDates) _weekStart(d)};
    if (weeks.isEmpty) return Streak.zero;

    final thisWeek = _weekStart(today);
    final activeThisWeek = weeks.contains(thisWeek);
    final lastWeek = thisWeek.subtract(const Duration(days: 7));

    var current = 0;
    if (activeThisWeek || weeks.contains(lastWeek)) {
      var cursor = activeThisWeek ? thisWeek : lastWeek;
      while (weeks.contains(cursor)) {
        current++;
        cursor = cursor.subtract(const Duration(days: 7));
      }
    }

    return Streak(
      current: current,
      best: _longestRun(weeks, const Duration(days: 7)),
      activeToday: activeThisWeek,
    );
  }

  static DateTime _weekStart(DateTime d) {
    final monday = d.subtract(Duration(days: d.weekday - 1));
    return DateTime(monday.year, monday.month, monday.day);
  }

  /// Longest chain of [step]-spaced entries in [points].
  static int _longestRun(Set<DateTime> points, Duration step) {
    var best = 0;
    for (final p in points) {
      // Only start counting from the beginning of a run.
      if (points.contains(p.subtract(step))) continue;
      var run = 0;
      var cursor = p;
      while (points.contains(cursor)) {
        run++;
        cursor = cursor.add(step);
      }
      if (run > best) best = run;
    }
    return best;
  }
}
