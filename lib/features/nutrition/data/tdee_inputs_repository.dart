import 'package:drift/drift.dart';
import 'package:herculex/core/utils/clock.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/nutrition/data/nutrition_repository.dart';
import 'package:herculex/features/nutrition/domain/meal.dart';
import 'package:herculex/features/nutrition/domain/tdee_estimator.dart';

/// Raw observations the estimator and classifier consume.
///
/// Adherence is presence-based (D-01): [foodLoggedDays] comes from which days
/// have food entries, never from a positive-kcal check, and bodyweight logs are read
/// independently of food so the two gates stay separate.
class TdeeInputs {
  const TdeeInputs({
    this.foodLoggedDays = const {},
    this.dailyKcalByDate = const {},
    this.weightLogs = const [],
    this.stepsByDate = const {},
    this.avgActiveKcal,
    this.avgSleepHours,
    this.avgRestingHr,
    this.workoutsPerWeek = 0,
  });

  /// `yyyy-MM-dd` days with at least one food entry.
  final Set<String> foodLoggedDays;

  /// Snapshot/recipe-aware kcal for each day in [foodLoggedDays].
  final Map<String, double> dailyKcalByDate;

  /// Bodyweight logs, ascending by date.
  final List<WeightLog> weightLogs;

  /// Steps per day (`kind == 'steps'` only).
  final Map<String, double> stepsByDate;

  /// Recorded-only context (last 14 days, mean per day with data).
  final double? avgActiveKcal;
  final double? avgSleepHours;
  final double? avgRestingHr;

  /// Completed sessions in the last 28 days divided by 4.
  final double workoutsPerWeek;
}

class TdeeInputsRepository {
  TdeeInputsRepository(this._db, this._nutrition, this._clock);

  final AppDatabase _db;
  final NutritionRepository _nutrition;
  final Clock _clock;

  /// 35-day widest window plus EWMA warm-up and the shift-comparison window.
  static const int lookbackDays = 60;
  static const int _healthAverageDays = 14;
  static const int _workoutDays = 28;

  Future<TdeeInputs> load() async {
    final now = _clock.now();
    final start = now.subtract(const Duration(days: lookbackDays));
    final cutoffIso = dateIso(start);

    final foodLoggedDays = await _foodLoggedDays(cutoffIso);
    final dailyKcal = await _dailyKcal(start, now, foodLoggedDays);
    final weights = await _weightLogs(cutoffIso);
    final steps = await _stepsByDate(cutoffIso);
    final recentIso = dateIso(
      now.subtract(const Duration(days: _healthAverageDays)),
    );

    return TdeeInputs(
      foodLoggedDays: foodLoggedDays,
      dailyKcalByDate: dailyKcal,
      weightLogs: weights,
      stepsByDate: steps,
      avgActiveKcal: await _average('active_kcal', recentIso),
      avgSleepHours: await _average('sleep_hours', recentIso),
      avgRestingHr: await _average('resting_hr', recentIso),
      workoutsPerWeek: await _workoutsPerWeek(now),
    );
  }

  Future<Set<String>> _foodLoggedDays(String cutoffIso) async {
    final col = _db.foodEntries.dateIso;
    final rows =
        await (_db.selectOnly(_db.foodEntries, distinct: true)
              ..addColumns([col])
              ..where(
                _db.foodEntries.deletedAt.isNull() &
                    col.isBiggerOrEqualValue(cutoffIso),
              ))
            .get();
    return rows.map((r) => r.read(col)).whereType<String>().toSet();
  }

  Future<Map<String, double>> _dailyKcal(
    DateTime start,
    DateTime end,
    Set<String> loggedDays,
  ) async {
    if (loggedDays.isEmpty) return const {};
    final totals = await _nutrition.watchDailyTotalsForRange(start, end).first;
    return {
      for (final day in loggedDays)
        if (totals[day] != null) day: totals[day]!.kcal,
    };
  }

  Future<List<WeightLog>> _weightLogs(String cutoffIso) async {
    final rows =
        await (_db.select(_db.bodyMeasurements)
              ..where(
                (t) =>
                    t.metric.equals('bodyweight') &
                    t.deletedAt.isNull() &
                    t.dateIso.isBiggerOrEqualValue(cutoffIso),
              )
              ..orderBy([(t) => OrderingTerm.asc(t.dateIso)]))
            .get();
    return rows
        .map((r) => WeightLog(DateTime.parse(r.dateIso), r.value))
        .toList(growable: false);
  }

  Future<Map<String, double>> _stepsByDate(String cutoffIso) async {
    final rows =
        await (_db.select(_db.healthSamples)
              ..where(
                (t) =>
                    t.kind.equals('steps') &
                    t.dateIso.isBiggerOrEqualValue(cutoffIso),
              )
              ..orderBy([(t) => OrderingTerm.asc(t.id)]))
            .get();
    // Ascending id, so a later re-read of the same day overwrites the earlier.
    return {for (final r in rows) r.dateIso: r.value};
  }

  /// Mean per row with data for [kind] since [sinceIso]; null when none.
  Future<double?> _average(String kind, String sinceIso) async {
    final rows =
        await (_db.select(_db.healthSamples)..where(
              (t) =>
                  t.kind.equals(kind) &
                  t.dateIso.isBiggerOrEqualValue(sinceIso),
            ))
            .get();
    if (rows.isEmpty) return null;
    return rows.fold<double>(0, (s, r) => s + r.value) / rows.length;
  }

  Future<double> _workoutsPerWeek(DateTime asOf) async {
    final from = asOf.subtract(const Duration(days: _workoutDays));
    final rows =
        await (_db.select(_db.workoutSessions)..where(
              (t) =>
                  t.endedAt.isNotNull() &
                  t.deletedAt.isNull() &
                  t.startedAt.isBiggerOrEqualValue(from),
            ))
            .get();
    return rows.length / 4.0;
  }
}
