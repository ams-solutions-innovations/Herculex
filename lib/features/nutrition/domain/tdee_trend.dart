/// One bodyweight measurement.
class WeightLog {
  const WeightLog(this.date, this.kg);

  /// Only the calendar date is used; the time of day is ignored.
  final DateTime date;
  final double kg;
}

/// Exponentially smoothed bodyweight on a daily grid.
///
/// Gaps between weigh-ins are filled by linear interpolation before smoothing,
/// so a week without a weigh-in is not treated as a one-day jump (RESEARCH
/// Pitfall 2). One EWMA step runs per calendar day, starting from the first
/// log's weight.
///
/// Plain Dart: no wall clock, no Flutter. Dates are compared as whole calendar
/// days via [dayNumber], which is immune to DST shifts.
class TrendSeries {
  TrendSeries._(this._firstDay, this._values);

  /// Smoothing factor: the weight of the newest daily value. Written once,
  /// here; `TdeeTuning.ewmaAlpha` points at it.
  static const double defaultEwmaAlpha = 0.1;

  static const int _msPerDay = 86400000;

  /// Days since the epoch for the calendar date of [date] (time ignored).
  static int dayNumber(DateTime date) =>
      DateTime.utc(date.year, date.month, date.day).millisecondsSinceEpoch ~/
      _msPerDay;

  /// Builds the series. Later logs win over earlier ones on the same date. An
  /// empty (or all-non-finite) list yields an empty series.
  factory TrendSeries.fromLogs(
    List<WeightLog> logs, {
    double alpha = defaultEwmaAlpha,
  }) {
    // Order by full timestamp (input position breaks ties, since List.sort is
    // not stable) so the later measurement on a date replaces the earlier one.
    final indexed =
        [
          for (var i = 0; i < logs.length; i++)
            if (logs[i].kg.isFinite) (i, logs[i]),
        ]..sort((a, b) {
          final byDate = a.$2.date.compareTo(b.$2.date);
          return byDate != 0 ? byDate : a.$1.compareTo(b.$1);
        });
    final byDay = <int, double>{
      for (final (_, log) in indexed) dayNumber(log.date): log.kg,
    };
    if (byDay.isEmpty) return TrendSeries._(0, const []);

    final days = byDay.keys.toList()..sort();
    final firstDay = days.first;
    final values = <double>[];
    var trend = byDay[firstDay]!;
    values.add(trend);
    for (var i = 1; i < days.length; i++) {
      final d0 = days[i - 1];
      final d1 = days[i];
      final w0 = byDay[d0]!;
      final w1 = byDay[d1]!;
      final gap = d1 - d0;
      for (var step = 1; step <= gap; step++) {
        final interpolated = w0 + (w1 - w0) * step / gap;
        trend = trend + alpha * (interpolated - trend);
        values.add(trend);
      }
    }
    return TrendSeries._(firstDay, values);
  }

  final int _firstDay;
  final List<double> _values;

  bool get isEmpty => _values.isEmpty;

  /// Date of the first log. Only meaningful when not [isEmpty].
  DateTime get firstDate => _dateFromDay(_firstDay);

  /// Date of the last log. Only meaningful when not [isEmpty].
  DateTime get lastDate => _dateFromDay(_firstDay + _values.length - 1);

  /// Smoothed weight on [date]; flat before the first and after the last log.
  /// Callers must check [isEmpty] first.
  double valueOn(DateTime date) {
    final index = dayNumber(date) - _firstDay;
    if (index <= 0) return _values.first;
    if (index >= _values.length) return _values.last;
    return _values[index];
  }

  static DateTime _dateFromDay(int day) {
    final utc = DateTime.fromMillisecondsSinceEpoch(
      day * _msPerDay,
      isUtc: true,
    );
    return DateTime(utc.year, utc.month, utc.day);
  }
}
