import 'package:herculex/features/nutrition/domain/tdee_trend.dart';
import 'package:herculex/features/physique/domain/physique_series.dart';
import 'package:herculex/features/programs/domain/primary_lift_specialization.dart';
import 'package:herculex/features/programs/domain/programming_models.dart';
import 'package:herculex/features/workouts/domain/effective_load.dart';
import 'package:herculex/features/workouts/domain/one_rep_max.dart';

/// One logged standard set. The repository excludes warmup and non-standard
/// sets before building these.
class StrengthSample {
  const StrengthSample({
    required this.date,
    required this.exerciseSlug,
    required this.weightKg,
    required this.reps,
    this.bodyweightKg,
    this.includesBodyweight = false,
  });

  final DateTime date;
  final String exerciseSlug;
  final double weightKg;
  final int reps;
  final double? bodyweightKg;
  final bool includesBodyweight;
}

abstract final class E1rmSeriesBuilder {
  /// Best estimated 1RM per calendar day for [lift], inside the window.
  static List<ChartPoint> build({
    required List<StrengthSample> samples,
    required PrimaryLift lift,
    required DateTime now,
    required ChartRange range,
  }) {
    final bestByDay = <int, double>{};
    final dateByDay = <int, DateTime>{};
    for (final s in samples) {
      if (!lift.preferredSlugs.contains(s.exerciseSlug)) continue;
      if (!range.includes(s.date, now)) continue;
      if (s.weightKg <= 0 && !s.includesBodyweight) continue;
      final load = EffectiveLoad.computeKg(
        weightKg: s.weightKg,
        bodyweightKg: s.bodyweightKg,
        includesBodyweight: s.includesBodyweight,
      );
      final est = OneRepMax.estimate(weightKg: load, reps: s.reps);
      if (est == null) continue;
      final day = TrendSeries.dayNumber(s.date);
      final prev = bestByDay[day];
      if (prev == null || est > prev) {
        bestByDay[day] = est;
        dateByDay[day] = DateTime(s.date.year, s.date.month, s.date.day);
      }
    }
    final days = bestByDay.keys.toList()..sort();
    return [for (final d in days) ChartPoint(dateByDay[d]!, bestByDay[d]!)];
  }

  static bool hasDataIn({
    required List<StrengthSample> samples,
    required PrimaryLift lift,
    required DateTime now,
    required ChartRange range,
  }) => build(samples: samples, lift: lift, now: now, range: range).isNotEmpty;

  /// The lift with the most recent data inside the range, or null.
  static PrimaryLift? defaultLift({
    required List<StrengthSample> samples,
    required DateTime now,
    required ChartRange range,
  }) {
    PrimaryLift? best;
    int bestDay = -1;
    for (final lift in PrimaryLift.values) {
      final points = build(
        samples: samples,
        lift: lift,
        now: now,
        range: range,
      );
      if (points.isEmpty) continue;
      final day = TrendSeries.dayNumber(points.last.date);
      if (day > bestDay) {
        bestDay = day;
        best = lift;
      }
    }
    return best;
  }
}

class TrainingLevelPoint {
  const TrainingLevelPoint(this.date, this.level);
  final DateTime date;
  final ExperienceLevel level;
}

/// Training level over time, derived from workout history only. This is not
/// the XP rank (D-12): `understandsRirRpe` and `hasRunStructuredBlocks` have
/// no history, so both are false and the line tops out at intermediate.
abstract final class TrainingLevelSeriesBuilder {
  static const _maxGapDays = 42;
  static const _recentWindowDays = 84;

  static List<TrainingLevelPoint> build({
    required List<DateTime> sessionDates,
    required DateTime now,
    required ChartRange range,
  }) {
    if (sessionDates.isEmpty) return const [];
    final days = [for (final d in sessionDates) TrendSeries.dayNumber(d)]
      ..sort();
    final nowDay = TrendSeries.dayNumber(now);

    // Monday of the week containing the first session.
    final firstSession = _dateOfDay(days.first);
    final start = DateTime(
      firstSession.year,
      firstSession.month,
      firstSession.day - (firstSession.weekday - DateTime.monday),
    );

    final points = <TrainingLevelPoint>[];
    for (var i = 0; ; i++) {
      final sample = DateTime(start.year, start.month, start.day + 7 * i);
      final sampleDay = TrendSeries.dayNumber(sample);
      if (sampleDay > nowDay) break;
      if (!range.includes(sample, now)) continue;
      final rec = ExperienceLevel.recommend(
        consistentTrainingMonths: _streakMonths(days, sampleDay, sample),
        sessionsLast12Weeks: _recentCount(days, sampleDay),
        understandsRirRpe: false,
        hasRunStructuredBlocks: false,
      );
      points.add(TrainingLevelPoint(sample, rec.level));
    }
    return points.length < 2 ? const [] : points;
  }

  static DateTime _dateOfDay(int day) {
    final utc = DateTime.fromMillisecondsSinceEpoch(
      day * 86400000,
      isUtc: true,
    );
    return DateTime(utc.year, utc.month, utc.day);
  }

  static int _recentCount(List<int> days, int sampleDay) {
    var n = 0;
    for (final d in days) {
      if (d <= sampleDay && d > sampleDay - _recentWindowDays) n++;
    }
    return n;
  }

  /// Whole months of the latest streak ending at the sample, where no gap
  /// between consecutive sessions (or to the sample) exceeds 42 days.
  static int _streakMonths(List<int> days, int sampleDay, DateTime sample) {
    var idx = -1;
    for (var i = 0; i < days.length; i++) {
      if (days[i] <= sampleDay) idx = i;
    }
    if (idx < 0) return 0;
    if (sampleDay - days[idx] > _maxGapDays) return 0;
    var startIdx = idx;
    while (startIdx > 0 && days[startIdx] - days[startIdx - 1] <= _maxGapDays) {
      startIdx--;
    }
    final from = _dateOfDay(days[startIdx]);
    var months = (sample.year - from.year) * 12 + sample.month - from.month;
    if (sample.day < from.day) months--;
    return months < 0 ? 0 : months;
  }
}
