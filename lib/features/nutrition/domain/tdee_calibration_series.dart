import 'package:herculex/features/nutrition/domain/tdee_trend.dart';

/// One point on a calibration chart: [x] is the day offset from the series
/// start.
class CalibrationPoint {
  const CalibrationPoint(this.x, this.y);
  final double x;
  final double y;
}

/// The weigh-ins, smoothed trend and daily intake over the span an estimate
/// was worked out from, laid out on a shared day axis for the page's charts.
///
/// Plain Dart. The trend is the same [TrendSeries] the estimator uses, built
/// from all supplied logs so the line matches what the estimate saw.
class CalibrationSeries {
  const CalibrationSeries({
    required this.start,
    required this.days,
    required this.weighIns,
    required this.trend,
    required this.intake,
    required this.meanIntake,
  });

  /// First calendar day on the axis.
  final DateTime start;

  /// Number of days on the axis (x runs 0..days-1).
  final int days;

  final List<CalibrationPoint> weighIns;
  final List<CalibrationPoint> trend;
  final List<CalibrationPoint> intake;

  /// Mean of [intake], or null with no logged days.
  final double? meanIntake;

  bool get hasWeight => weighIns.isNotEmpty;
  bool get hasIntake => intake.isNotEmpty;

  DateTime dateAt(double x) =>
      DateTime(start.year, start.month, start.day + x.round());

  factory CalibrationSeries.build({
    required DateTime asOf,
    required int days,
    required List<WeightLog> weightLogs,
    required Map<String, double> dailyKcalByDate,
  }) {
    final start = DateTime(asOf.year, asOf.month, asOf.day - (days - 1));
    final startDay = TrendSeries.dayNumber(start);
    final endDay = startDay + days - 1;

    final series = TrendSeries.fromLogs(weightLogs);

    // One weigh-in per day; logs arrive ascending, so the later one wins.
    final byDay = <int, double>{
      for (final l in weightLogs)
        if (l.kg.isFinite) TrendSeries.dayNumber(l.date): l.kg,
    };
    final weighIns = <CalibrationPoint>[
      for (var d = startDay; d <= endDay; d++)
        if (byDay[d] != null)
          CalibrationPoint((d - startDay).toDouble(), byDay[d]!),
    ];

    final trend = <CalibrationPoint>[];
    if (!series.isEmpty) {
      final first = TrendSeries.dayNumber(series.firstDate);
      final last = TrendSeries.dayNumber(series.lastDate);
      for (var d = startDay; d <= endDay; d++) {
        if (d < first || d > last) continue;
        final date = DateTime(
          start.year,
          start.month,
          start.day + (d - startDay),
        );
        trend.add(
          CalibrationPoint((d - startDay).toDouble(), series.valueOn(date)),
        );
      }
    }

    final intake = <CalibrationPoint>[];
    var sum = 0.0;
    for (var i = 0; i < days; i++) {
      final day = DateTime(start.year, start.month, start.day + i);
      final kcal = dailyKcalByDate[_iso(day)];
      if (kcal == null) continue;
      intake.add(CalibrationPoint(i.toDouble(), kcal));
      sum += kcal;
    }

    return CalibrationSeries(
      start: start,
      days: days,
      weighIns: weighIns,
      trend: trend,
      intake: intake,
      meanIntake: intake.isEmpty ? null : sum / intake.length,
    );
  }

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
