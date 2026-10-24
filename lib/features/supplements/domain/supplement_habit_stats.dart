import 'dart:math' as math;

import 'package:herculex/features/supplements/domain/supplement.dart';

/// Daily snapshot of supplement habit completion for a single calendar date.
class SupplementDayPoint {
  final DateTime date;
  final String dateIso;
  final Set<String> takenIds;
  final int takenCount;
  final int totalCount;

  const SupplementDayPoint({
    required this.date,
    required this.dateIso,
    required this.takenIds,
    required this.takenCount,
    required this.totalCount,
  });

  double get completionRatio =>
      totalCount <= 0 ? 0.0 : (takenCount / totalCount).clamp(0.0, 1.0);

  bool get isPerfect => totalCount > 0 && takenCount >= totalCount;

  bool get hasAnyTaken => takenCount > 0;
}

/// Habit adherence and streak metrics for a single [Supplement].
class SupplementItemHabitStat {
  final Supplement supplement;
  final int takenDays;
  final int activeWindowDays;
  final double adherenceRate;
  final int currentStreak;
  final int bestStreak;

  /// Oldest → today (length 7).
  final List<bool> last7Days;

  /// Oldest → today (length 14).
  final List<bool> last14Days;

  const SupplementItemHabitStat({
    required this.supplement,
    required this.takenDays,
    required this.activeWindowDays,
    required this.adherenceRate,
    required this.currentStreak,
    required this.bestStreak,
    required this.last7Days,
    required this.last14Days,
  });
}

/// Aggregated habit-tracking statistics across all supplements and days.
class SupplementHabitStats {
  final int rangeDays;

  /// Consecutive days (ending today or yesterday) with 100% of supplements taken.
  final int currentStreak;

  /// Best consecutive run of 100%-complete days in recorded history.
  final int bestStreak;

  /// Consecutive days (ending today or yesterday) where at least 1 supplement was taken.
  final int activeStreak;

  /// Average daily completion ratio (0.0–1.0) over [effectiveWindowDays].
  final double consistencyRate;

  /// Number of days in [rangeDays] where all supplements were taken (100%).
  final int perfectDays;

  /// Number of days in [rangeDays] where at least 1 supplement was taken.
  final int activeDays;

  /// Denominator days for [consistencyRate] (from first tracked day or start of range).
  final int effectiveWindowDays;

  /// Total individual supplement doses marked taken across [rangeDays].
  final int totalDosesTaken;

  /// Daily points for the selected [rangeDays] window (oldest → today).
  final List<SupplementDayPoint> dailyPoints;

  /// Trailing 28 days (4 weeks, oldest → today) for the habit heatmap grid.
  final List<SupplementDayPoint> heatmapPoints;

  /// Per-supplement consistency breakdown sorted by schedule/list order.
  final List<SupplementItemHabitStat> itemStats;

  const SupplementHabitStats({
    required this.rangeDays,
    required this.currentStreak,
    required this.bestStreak,
    required this.activeStreak,
    required this.consistencyRate,
    required this.perfectDays,
    required this.activeDays,
    required this.effectiveWindowDays,
    required this.totalDosesTaken,
    required this.dailyPoints,
    required this.heatmapPoints,
    required this.itemStats,
  });

  static const empty = SupplementHabitStats(
    rangeDays: 7,
    currentStreak: 0,
    bestStreak: 0,
    activeStreak: 0,
    consistencyRate: 0,
    perfectDays: 0,
    activeDays: 0,
    effectiveWindowDays: 0,
    totalDosesTaken: 0,
    dailyPoints: [],
    heatmapPoints: [],
    itemStats: [],
  );

  /// Computes habit tracking metrics from [supplements] and [historyByIso].
  ///
  /// [historyByIso] should cover at least `max(rangeDays, 90)` trailing days
  /// ending on [today].
  static SupplementHabitStats compute({
    required List<Supplement> supplements,
    required Map<String, Set<String>> historyByIso,
    required int rangeDays,
    DateTime? today,
    DateTime? earliestTrackedDate,
  }) {
    final now = today ?? DateTime.now();
    final anchor = DateTime(now.year, now.month, now.day);
    final totalCount = supplements.length;
    final currentIds = {for (final s in supplements) s.id};

    if (totalCount == 0) {
      return SupplementHabitStats(
        rangeDays: rangeDays,
        currentStreak: 0,
        bestStreak: 0,
        activeStreak: 0,
        consistencyRate: 0,
        perfectDays: 0,
        activeDays: 0,
        effectiveWindowDays: 0,
        totalDosesTaken: 0,
        dailyPoints: [
          for (int i = rangeDays - 1; i >= 0; i--)
            _pointForDate(
              anchor.subtract(Duration(days: i)),
              const {},
              currentIds,
              0,
            ),
        ],
        heatmapPoints: [
          for (int i = 27; i >= 0; i--)
            _pointForDate(
              anchor.subtract(Duration(days: i)),
              const {},
              currentIds,
              0,
            ),
        ],
        itemStats: const [],
      );
    }

    // Determine the longest history span available for streak calculation.
    final maxHistoryDays = math.max(
      math.max(rangeDays, 90),
      historyByIso.length,
    );
    final allPoints = <SupplementDayPoint>[];
    for (int i = maxHistoryDays - 1; i >= 0; i--) {
      final d = anchor.subtract(Duration(days: i));
      final iso = isoForDate(d);
      final rawTaken = historyByIso[iso] ?? const <String>{};
      allPoints.add(_pointForDate(d, rawTaken, currentIds, totalCount));
    }

    // Slice dailyPoints for rangeDays and heatmapPoints for 28 days.
    final dailyPoints = allPoints.sublist(allPoints.length - rangeDays);
    final heatmapPoints = allPoints.length >= 28
        ? allPoints.sublist(allPoints.length - 28)
        : allPoints;

    // Determine earliest active date so new users aren't penalized for days
    // before they ever started logging supplements.
    DateTime? firstActive = earliestTrackedDate != null
        ? DateTime(
            earliestTrackedDate.year,
            earliestTrackedDate.month,
            earliestTrackedDate.day,
          )
        : null;
    if (firstActive == null) {
      for (final p in allPoints) {
        if (p.hasAnyTaken) {
          firstActive = p.date;
          break;
        }
      }
    }

    final rangeStart = dailyPoints.first.date;
    final effectiveStart =
        (firstActive != null && firstActive.isAfter(rangeStart))
        ? firstActive
        : rangeStart;

    final effectivePoints = firstActive == null
        ? <SupplementDayPoint>[]
        : dailyPoints.where((p) => !p.date.isBefore(effectiveStart)).toList();

    final effectiveWindowDays = effectivePoints.length;
    double sumRatios = 0.0;
    for (final p in effectivePoints) {
      sumRatios += p.completionRatio;
    }
    final consistencyRate = effectiveWindowDays == 0
        ? 0.0
        : (sumRatios / effectiveWindowDays).clamp(0.0, 1.0);

    var perfectDays = 0;
    var activeDays = 0;
    var totalDosesTaken = 0;
    for (final p in dailyPoints) {
      if (p.isPerfect) perfectDays++;
      if (p.hasAnyTaken) activeDays++;
      totalDosesTaken += p.takenCount;
    }

    // Compute overall streaks across allPoints.
    final currentStreak = _computeCurrentStreak(
      allPoints.map((p) => p.isPerfect).toList(),
    );
    final bestStreak = _computeBestStreak(
      allPoints.map((p) => p.isPerfect).toList(),
    );
    final activeStreak = _computeCurrentStreak(
      allPoints.map((p) => p.hasAnyTaken).toList(),
    );

    // Per-supplement habit stats.
    final itemStats = <SupplementItemHabitStat>[];
    for (final s in supplements) {
      final takenFlagsAll = [
        for (final p in allPoints) p.takenIds.contains(s.id),
      ];
      final takenInRange = [
        for (final p in dailyPoints)
          if (p.takenIds.contains(s.id)) 1,
      ].length;

      // For a single supplement, effective window starts at max(rangeStart, first day this supplement or any supplement was taken).
      DateTime? firstSuppDate = firstActive;
      for (final p in allPoints) {
        if (p.takenIds.contains(s.id)) {
          if (firstSuppDate == null || p.date.isBefore(firstSuppDate)) {
            firstSuppDate = p.date;
          }
          break;
        }
      }

      final denomDays = effectiveWindowDays > 0
          ? effectiveWindowDays
          : rangeDays;
      final itemRate = denomDays == 0
          ? 0.0
          : (takenInRange / denomDays).clamp(0.0, 1.0);

      final last7 = takenFlagsAll.length >= 7
          ? takenFlagsAll.sublist(takenFlagsAll.length - 7)
          : takenFlagsAll;
      final last14 = takenFlagsAll.length >= 14
          ? takenFlagsAll.sublist(takenFlagsAll.length - 14)
          : takenFlagsAll;

      itemStats.add(
        SupplementItemHabitStat(
          supplement: s,
          takenDays: takenInRange,
          activeWindowDays: denomDays,
          adherenceRate: itemRate,
          currentStreak: _computeCurrentStreak(takenFlagsAll),
          bestStreak: _computeBestStreak(takenFlagsAll),
          last7Days: last7,
          last14Days: last14,
        ),
      );
    }

    return SupplementHabitStats(
      rangeDays: rangeDays,
      currentStreak: currentStreak,
      bestStreak: bestStreak,
      activeStreak: activeStreak,
      consistencyRate: consistencyRate,
      perfectDays: perfectDays,
      activeDays: activeDays,
      effectiveWindowDays: effectiveWindowDays,
      totalDosesTaken: totalDosesTaken,
      dailyPoints: dailyPoints,
      heatmapPoints: heatmapPoints,
      itemStats: itemStats,
    );
  }

  static SupplementDayPoint _pointForDate(
    DateTime date,
    Set<String> rawTaken,
    Set<String> currentIds,
    int totalCount,
  ) {
    final matching = rawTaken.intersection(currentIds);
    // If the user logged deleted supplements on an older day and matching is
    // smaller than rawTaken, still credit up to totalCount so historical
    // completion isn't wiped when a user swaps brands/IDs.
    final takenCount = totalCount == 0
        ? 0
        : math.min(totalCount, math.max(matching.length, rawTaken.length));
    return SupplementDayPoint(
      date: date,
      dateIso: isoForDate(date),
      takenIds: rawTaken,
      takenCount: takenCount,
      totalCount: totalCount,
    );
  }

  /// Calculates current streak from chronological boolean flags (oldest → today).
  /// If today is `false`, the streak from yesterday is still preserved because
  /// today is still in progress.
  static int _computeCurrentStreak(List<bool> flags) {
    if (flags.isEmpty) return 0;
    int idx = flags.length - 1;
    if (!flags[idx]) {
      idx--;
    }
    int streak = 0;
    while (idx >= 0 && flags[idx]) {
      streak++;
      idx--;
    }
    return streak;
  }

  static int _computeBestStreak(List<bool> flags) {
    int best = 0;
    int current = 0;
    for (final f in flags) {
      if (f) {
        current++;
        if (current > best) best = current;
      } else {
        current = 0;
      }
    }
    return best;
  }

  static String isoForDate(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
