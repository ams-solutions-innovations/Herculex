/// Nutrition card calculator for the weekly report (RPT-01, RPT-02).
///
/// A pure function of explicit inputs and an [IsoWeek]: no providers, no
/// database, no wall-clock reads. The same inputs therefore give the same
/// section for any week, including past and late-generated ones (D-05).
///
/// Adherence is presence-based (Phase 28 D-01): a day counts as logged because
/// the user logged it, never because its totals are non-zero, and averages are
/// taken over logged days only.
library;

import 'package:herculex/features/weekly_report/domain/iso_week.dart';
import 'package:herculex/features/weekly_report/domain/weekly_report_sections.dart';

/// One logged food entry reduced to what the top-foods ranking needs.
class FoodEntryName {
  const FoodEntryName({required this.key, required this.name});

  /// Stable identity used for grouping (catalogue id or normalised name).
  final String key;

  /// Display name; trimmed and capped when it reaches the section.
  final String name;
}

/// Everything the nutrition calculator reads for one week.
///
/// Dates are `yyyy-MM-dd` strings. Out-of-week dates are ignored by the
/// calculator, so callers may pass a slightly wider range.
class NutritionWeekInputs {
  const NutritionWeekInputs({
    required this.loggedDays,
    required this.kcalByDate,
    required this.proteinByDate,
    required this.targetByDate,
    required this.foodEntries,
  });

  /// Days on which the user logged at least one entry.
  final Set<String> loggedDays;
  final Map<String, double> kcalByDate;
  final Map<String, double> proteinByDate;

  /// Per-day targets; empty when no target applies.
  final Map<String, ({int kcal, int proteinG})> targetByDate;

  /// Entries of the week, used only for the top-foods ranking.
  final List<FoodEntryName> foodEntries;

  /// Same inputs with [targetByDate] replaced (the service fills targets in
  /// after the repository builds the rest).
  NutritionWeekInputs copyWith({
    Map<String, ({int kcal, int proteinG})>? targetByDate,
  }) => NutritionWeekInputs(
    loggedDays: loggedDays,
    kcalByDate: kcalByDate,
    proteinByDate: proteinByDate,
    targetByDate: targetByDate ?? this.targetByDate,
    foodEntries: foodEntries,
  );
}

abstract final class NutritionSectionCalculator {
  /// A logged day is "on target" when its kcal is within this fraction of
  /// that day's target kcal.
  static const double adherenceBandFraction = 0.10;

  /// Foods listed in the section.
  static const int maxTopFoods = 3;

  /// Returns null when no day of [week] was logged (D-06: "No data this
  /// week").
  static NutritionSection? compute({
    required IsoWeek week,
    required NutritionWeekInputs inputs,
  }) {
    final startIso = week.startIso;
    final endIso = week.endIso;
    bool inWeek(String d) =>
        d.compareTo(startIso) >= 0 && d.compareTo(endIso) <= 0;

    final days = inputs.loggedDays.where(inWeek).toList()..sort();
    if (days.isEmpty) return null;

    var kcalSum = 0.0;
    var proteinSum = 0.0;
    for (final d in days) {
      kcalSum += _finiteOrZero(inputs.kcalByDate[d]);
      proteinSum += _finiteOrZero(inputs.proteinByDate[d]);
    }

    var targetKcalSum = 0;
    var targetProteinSum = 0;
    var targetDays = 0;
    var adherence = 0;
    for (final d in days) {
      final target = inputs.targetByDate[d];
      if (target == null || target.kcal <= 0) continue;
      targetDays++;
      targetKcalSum += target.kcal;
      targetProteinSum += target.proteinG;
      final kcal = _finiteOrZero(inputs.kcalByDate[d]);
      if ((kcal - target.kcal).abs() <= target.kcal * adherenceBandFraction) {
        adherence++;
      }
    }

    return NutritionSection(
      daysLogged: days.length,
      avgKcal: (kcalSum / days.length).round(),
      avgProteinG: (proteinSum / days.length).round(),
      targetKcal: targetDays == 0 ? null : (targetKcalSum / targetDays).round(),
      targetProteinG: targetDays == 0
          ? null
          : (targetProteinSum / targetDays).round(),
      adherenceDays: targetDays == 0 ? null : adherence,
      topFoods: _topFoods(inputs.foodEntries),
    );
  }

  static List<TopFood> _topFoods(List<FoodEntryName> entries) {
    final counts = <String, int>{};
    final names = <String, String>{};
    for (final e in entries) {
      final name = e.name.trim();
      if (name.isEmpty) continue;
      counts[e.key] = (counts[e.key] ?? 0) + 1;
      names.putIfAbsent(e.key, () => name);
    }
    final ranked =
        [
          for (final entry in counts.entries)
            TopFood.truncated(name: names[entry.key]!, count: entry.value),
        ]..sort((a, b) {
          final byCount = b.count.compareTo(a.count);
          return byCount != 0 ? byCount : a.name.compareTo(b.name);
        });
    return ranked.take(maxTopFoods).toList();
  }

  static double _finiteOrZero(double? v) =>
      (v == null || !v.isFinite) ? 0.0 : v;
}
