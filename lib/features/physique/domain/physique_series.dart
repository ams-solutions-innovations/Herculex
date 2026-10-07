import 'package:herculex/features/nutrition/domain/diet_phase.dart';
import 'package:herculex/features/nutrition/domain/tdee_trend.dart';
import 'package:herculex/features/physique/domain/physique_tuning.dart';

/// Window selector for the physique charts (D-12).
enum ChartRange {
  month('1M', 30),
  quarter('3M', 90),
  all('All', null);

  const ChartRange(this.label, this.days);
  final String label;
  final int? days;

  /// Start of the window, by calendar arithmetic; null for [all].
  DateTime? windowStart(DateTime now) {
    final d = days;
    if (d == null) return null;
    return DateTime(now.year, now.month, now.day - d);
  }

  /// All when the goal is under 30 days old, otherwise 3M.
  static ChartRange defaultFor({
    required DateTime goalStartedAt,
    required DateTime now,
  }) {
    final age =
        TrendSeries.dayNumber(now) - TrendSeries.dayNumber(goalStartedAt);
    return age < 30 ? ChartRange.all : ChartRange.quarter;
  }

  bool includes(DateTime date, DateTime now) {
    final start = windowStart(now);
    if (start == null) return true;
    return TrendSeries.dayNumber(date) >= TrendSeries.dayNumber(start);
  }
}

class ChartPoint {
  const ChartPoint(this.date, this.value);
  final DateTime date;
  final double value;
}

/// One roadmap phase's target band over its planned span.
class PhaseBandSpan {
  const PhaseBandSpan({
    required this.phase,
    required this.start,
    required this.end,
    required this.startLowKg,
    required this.startHighKg,
    required this.endLowKg,
    required this.endHighKg,
  });

  final DietPhase phase;
  final DateTime start;
  final DateTime end;
  final double startLowKg;
  final double startHighKg;
  final double endLowKg;
  final double endHighKg;
}

/// Phase data the band needs, supplied by the repository layer.
class PhaseBandInput {
  const PhaseBandInput({
    required this.phase,
    required this.plannedWeeks,
    this.startedAt,
    this.startWeightKg,
    this.targetWeightKg,
  });

  final DietPhase phase;
  final DateTime? startedAt;
  final int plannedWeeks;
  final double? startWeightKg;
  final double? targetWeightKg;
}

class WeightChartData {
  const WeightChartData({
    required this.trend,
    required this.raw,
    required this.bands,
    required this.textSummary,
  });

  static const empty = WeightChartData(
    trend: [],
    raw: [],
    bands: [],
    textSummary: 'Not enough weigh-ins yet.',
  );

  final List<ChartPoint> trend;
  final List<ChartPoint> raw;
  final List<PhaseBandSpan> bands;
  final String textSummary;

  bool get isSparse => raw.length < 3;
}

abstract final class PhysiqueSeriesBuilder {
  static WeightChartData weight({
    required List<WeightLog> logs,
    required DateTime now,
    required ChartRange range,
    required DateTime goalStartedAt,
    required List<PhaseBandInput> phases,
  }) {
    final series = TrendSeries.fromLogs(logs);
    if (series.isEmpty) return WeightChartData.empty;
    final firstDay = TrendSeries.dayNumber(series.firstDate);
    final lastDay = TrendSeries.dayNumber(series.lastDate);
    if (lastDay <= firstDay) return WeightChartData.empty;

    final windowStart = range.windowStart(now);
    final windowStartDay = windowStart == null
        ? firstDay
        : TrendSeries.dayNumber(windowStart);
    final fromDay = windowStartDay > firstDay ? windowStartDay : firstDay;

    final trend = <ChartPoint>[];
    for (var day = fromDay; day <= lastDay; day++) {
      final date = DateTime(
        series.firstDate.year,
        series.firstDate.month,
        series.firstDate.day + (day - firstDay),
      );
      trend.add(ChartPoint(date, series.valueOn(date)));
    }

    final raw = <ChartPoint>[
      for (final l in logs)
        if (l.kg.isFinite && range.includes(l.date, now))
          ChartPoint(l.date, l.kg),
    ]..sort((a, b) => a.date.compareTo(b.date));

    return WeightChartData(
      trend: trend,
      raw: raw,
      bands: _bands(phases, windowStart),
      textSummary: _summary(trend, range),
    );
  }

  static List<PhaseBandSpan> _bands(
    List<PhaseBandInput> phases,
    DateTime? windowStart,
  ) {
    const half = PhysiqueTuning.targetBandHalfWidthKg;
    final spans = <PhaseBandSpan>[];
    for (final p in phases) {
      final started = p.startedAt;
      final startKg = p.startWeightKg;
      if (started == null || startKg == null) continue;
      final end = DateTime(
        started.year,
        started.month,
        started.day + p.plannedWeeks * 7,
      );
      if (windowStart != null && end.isBefore(windowStart)) continue;
      final flat =
          p.phase == DietPhase.maintain ||
          p.phase == DietPhase.recomp ||
          p.targetWeightKg == null;
      final endKg = flat ? startKg : p.targetWeightKg!;
      spans.add(
        PhaseBandSpan(
          phase: p.phase,
          start: started,
          end: end,
          startLowKg: startKg - half,
          startHighKg: startKg + half,
          endLowKg: endKg - half,
          endHighKg: endKg + half,
        ),
      );
    }
    return spans;
  }

  static String _summary(List<ChartPoint> trend, ChartRange range) {
    if (trend.length < 2) return WeightChartData.empty.textSummary;
    final delta = trend.last.value - trend.first.value;
    final days =
        TrendSeries.dayNumber(trend.last.date) -
        TrendSeries.dayNumber(trend.first.date);
    final String period;
    switch (range) {
      case ChartRange.month:
        period = '1 month';
      case ChartRange.quarter:
        period = '3 months';
      case ChartRange.all:
        final months = (days / 30).round();
        if (months >= 1) {
          period = months == 1 ? '1 month' : '$months months';
        } else {
          final weeks = (days / 7).round().clamp(1, 4);
          period = weeks == 1 ? '1 week' : '$weeks weeks';
        }
    }
    final rounded = (delta.abs() * 10).round() / 10;
    if (rounded == 0) return 'No change over $period.';
    final dir = delta < 0 ? 'Down' : 'Up';
    return '$dir ${rounded.toStringAsFixed(1)} kg over $period.';
  }
}

abstract final class WeightTrendRate {
  static const _lookbackDays = 14;

  /// Kg per week over the last 14 calendar days of the trend, or null when the
  /// series spans fewer than 7 days.
  static double? perWeekKg(TrendSeries series, DateTime now) {
    if (series.isEmpty) return null;
    final first = TrendSeries.dayNumber(series.firstDate);
    final last = TrendSeries.dayNumber(series.lastDate);
    if (last - first < 7) return null;
    final endDay = TrendSeries.dayNumber(now);
    var startDay = endDay - _lookbackDays;
    if (startDay < first) startDay = first;
    final span = endDay - startDay;
    if (span <= 0) return null;
    final end = DateTime(now.year, now.month, now.day);
    final start = DateTime(now.year, now.month, now.day - span);
    return (series.valueOn(end) - series.valueOn(start)) / span * 7;
  }
}
