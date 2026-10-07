import 'package:drift/drift.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/analytics/domain/training_snapshot.dart';
import 'package:herculex/features/nutrition/data/nutrition_repository.dart';
import 'package:herculex/features/nutrition/data/tdee_estimates_repository.dart';
import 'package:herculex/features/nutrition/domain/meal.dart';
import 'package:herculex/features/nutrition/domain/tdee_estimate.dart';
import 'package:herculex/features/weekly_report/domain/iso_week.dart';
import 'package:herculex/features/weekly_report/domain/nutrition_section_calculator.dart';
import 'package:herculex/features/weekly_report/domain/physique_section_calculator.dart';

/// The raw, week-scoped observations the section calculators consume.
///
/// Everything here is data as stored; no section maths happens in this class.
/// [nutrition] carries an empty `targetByDate` because targets come from the
/// target resolver, which the service owns.
class WeeklyReportInputs {
  const WeeklyReportInputs({
    required this.nutrition,
    required this.weekHealth,
    required this.trailingHealth,
    required this.snapshot,
    required this.checkIns,
    required this.weights,
    required this.tdeeNewest,
    required this.tdeeBefore,
  });

  final NutritionWeekInputs nutrition;

  /// Health samples with `dateIso` inside the report window.
  final List<HealthSampleData> weekHealth;

  /// Health samples for the eight weeks leading up to the window end.
  final List<HealthSampleData> trailingHealth;

  /// All completed sets; the calculators filter by date themselves.
  final TrainingSnapshot snapshot;

  /// Non-deleted `checkin` assessments dated inside the window.
  final List<PhysiqueCheckInInput> checkIns;

  /// Bodyweight logs up to the window end, ascending by date. The physique
  /// calculator splits them into in-week and before-week.
  final List<BodyweightLog> weights;

  /// Newest estimate at or before the window end.
  final TdeeEstimateResult? tdeeNewest;

  /// Newest estimate strictly before the week started.
  final TdeeEstimateResult? tdeeBefore;
}

/// Loads the raw inputs for one ISO week.
///
/// The window is an argument, not a read of the current time: two calls with
/// the same week, `windowEnd` and database give identical results, which is
/// what lets a late-generated past week match an on-time one (D-05). All SQL
/// for the report lives here; the UI never touches drift.
class WeeklyReportInputsRepository {
  WeeklyReportInputsRepository(this._db, this._nutrition, this._tdeeEstimates);

  final AppDatabase _db;
  final NutritionRepository _nutrition;
  final TdeeEstimatesRepository _tdeeEstimates;

  /// How far before the week the trailing health window reaches. Superset of
  /// the recovery calculator's own eight-week correlation window; it filters
  /// precisely by date itself.
  static const int trailingDays = 56;

  Future<WeeklyReportInputs> load({
    required IsoWeek week,
    required DateTime windowEnd,
  }) async {
    final startIso = week.startIso;
    // Nothing dated after the window end belongs to the report: for the
    // current week that is today, for a finished week it is Sunday.
    final windowEndIso = dateIso(windowEnd);
    final upperIso = windowEndIso.compareTo(week.endIso) < 0
        ? windowEndIso
        : week.endIso;

    final loggedDays = await _foodLoggedDays(startIso, upperIso);
    final totals = await _dailyTotals(loggedDays, startIso, upperIso);
    final foodEntries = await _foodEntryNames(startIso, upperIso);

    final trailingStart = week.start;
    final trailingFromIso = dateIso(
      DateTime(
        trailingStart.year,
        trailingStart.month,
        trailingStart.day - trailingDays,
      ),
    );

    return WeeklyReportInputs(
      nutrition: NutritionWeekInputs(
        loggedDays: loggedDays,
        kcalByDate: totals.kcal,
        proteinByDate: totals.protein,
        targetByDate: const {},
        foodEntries: foodEntries,
      ),
      weekHealth: await _health(startIso, upperIso),
      trailingHealth: await _health(trailingFromIso, upperIso),
      snapshot: await TrainingSnapshot.load(_db),
      checkIns: await _checkIns(startIso, upperIso),
      weights: await _weights(upperIso),
      tdeeNewest: await _tdeeEstimates.latestAtOrBefore(windowEnd),
      tdeeBefore: await _tdeeEstimates.latestBefore(week.start),
    );
  }

  /// Presence-based (Phase 28 D-01): a day counts because an entry exists, not
  /// because its totals are positive.
  Future<Set<String>> _foodLoggedDays(String fromIso, String toIso) async {
    final col = _db.foodEntries.dateIso;
    final rows =
        await (_db.selectOnly(_db.foodEntries, distinct: true)
              ..addColumns([col])
              ..where(
                _db.foodEntries.deletedAt.isNull() &
                    col.isBiggerOrEqualValue(fromIso) &
                    col.isSmallerOrEqualValue(toIso),
              ))
            .get();
    return rows.map((r) => r.read(col)).whereType<String>().toSet();
  }

  Future<({Map<String, double> kcal, Map<String, double> protein})>
  _dailyTotals(Set<String> loggedDays, String fromIso, String toIso) async {
    if (loggedDays.isEmpty) {
      return (kcal: <String, double>{}, protein: <String, double>{});
    }
    final totals = await _nutrition
        .watchDailyTotalsForRange(
          DateTime.parse(fromIso),
          DateTime.parse(toIso),
        )
        .first;
    return (
      kcal: {
        for (final day in loggedDays)
          if (totals[day] != null) day: totals[day]!.kcal,
      },
      protein: {
        for (final day in loggedDays)
          if (totals[day] != null) day: totals[day]!.proteinG,
      },
    );
  }

  /// Name per live entry: the frozen snapshot name first (so a renamed or
  /// deleted catalogue food still reads as it did when logged), then the
  /// catalogue food, then the recipe. Entries with no resolvable name are
  /// skipped.
  Future<List<FoodEntryName>> _foodEntryNames(
    String fromIso,
    String toIso,
  ) async {
    final entries =
        await (_db.select(_db.foodEntries)
              ..where(
                (t) =>
                    t.deletedAt.isNull() &
                    t.dateIso.isBiggerOrEqualValue(fromIso) &
                    t.dateIso.isSmallerOrEqualValue(toIso),
              )
              ..orderBy([
                (t) => OrderingTerm.asc(t.dateIso),
                (t) => OrderingTerm.asc(t.id),
              ]))
            .get();
    if (entries.isEmpty) return const [];

    final foodIds = {
      for (final e in entries)
        if (_blank(e.snapshotName) && e.foodId != null) e.foodId!,
    };
    final foods = await _nutrition.foodsByIds(foodIds);

    final recipeIds = {
      for (final e in entries)
        if (_blank(e.snapshotName) && e.foodId == null && e.recipeId != null)
          e.recipeId!,
    };
    final recipeNames = <int, String>{};
    for (final id in recipeIds) {
      final recipe = await _nutrition.recipeById(id);
      if (recipe != null) recipeNames[id] = recipe.name;
    }

    final out = <FoodEntryName>[];
    for (final e in entries) {
      final snapshot = e.snapshotName?.trim();
      String? name;
      if (snapshot != null && snapshot.isNotEmpty) {
        name = snapshot;
      } else if (e.foodId != null) {
        name = foods[e.foodId]?.name;
      } else if (e.recipeId != null) {
        name = recipeNames[e.recipeId];
      }
      name = name?.trim();
      if (name == null || name.isEmpty) continue;
      final key = e.foodId != null
          ? 'food:${e.foodId}'
          : e.recipeId != null
          ? 'recipe:${e.recipeId}'
          : 'name:${name.toLowerCase()}';
      out.add(FoodEntryName(key: key, name: name));
    }
    return out;
  }

  Future<List<HealthSampleData>> _health(String fromIso, String toIso) {
    return (_db.select(_db.healthSamples)
          ..where(
            (t) =>
                t.dateIso.isBiggerOrEqualValue(fromIso) &
                t.dateIso.isSmallerOrEqualValue(toIso),
          )
          ..orderBy([(t) => OrderingTerm.asc(t.id)]))
        .get();
  }

  Future<List<PhysiqueCheckInInput>> _checkIns(
    String fromIso,
    String toIso,
  ) async {
    final rows =
        await (_db.select(_db.physiqueAssessments)
              ..where(
                (t) =>
                    t.kind.equals('checkin') &
                    t.deletedAt.isNull() &
                    t.dateIso.isBiggerOrEqualValue(fromIso) &
                    t.dateIso.isSmallerOrEqualValue(toIso),
              )
              ..orderBy([
                (t) => OrderingTerm.asc(t.dateIso),
                (t) => OrderingTerm.asc(t.id),
              ]))
            .get();
    return [
      for (final r in rows)
        PhysiqueCheckInInput(
          dateIso: r.dateIso,
          verdict: r.verdict,
          confidence: r.confidence,
        ),
    ];
  }

  Future<List<BodyweightLog>> _weights(String toIso) async {
    final rows =
        await (_db.select(_db.bodyMeasurements)
              ..where(
                (t) =>
                    t.metric.equals('bodyweight') &
                    t.deletedAt.isNull() &
                    t.dateIso.isSmallerOrEqualValue(toIso),
              )
              ..orderBy([
                (t) => OrderingTerm.asc(t.dateIso),
                (t) => OrderingTerm.asc(t.id),
              ]))
            .get();
    return [
      for (final r in rows) BodyweightLog(dateIso: r.dateIso, kg: r.value),
    ];
  }

  static bool _blank(String? s) => s == null || s.trim().isEmpty;
}
