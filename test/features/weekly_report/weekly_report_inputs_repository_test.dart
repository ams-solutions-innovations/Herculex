import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/core/utils/clock.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/nutrition/data/nutrition_repository.dart';
import 'package:herculex/features/nutrition/data/openfoodfacts_client.dart';
import 'package:herculex/features/nutrition/data/tdee_estimates_repository.dart';
import 'package:herculex/features/nutrition/domain/tdee_estimate.dart';
import 'package:herculex/features/weekly_report/data/weekly_report_inputs_repository.dart';
import 'package:herculex/features/weekly_report/domain/iso_week.dart';

import '../../support/fake_clock.dart';
import '../../support/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WeeklyReportInputsRepository', () {
    late AppDatabase db;
    late Clock clock;
    late NutritionRepository nutrition;
    late TdeeEstimatesRepository tdee;
    late WeeklyReportInputsRepository repo;

    // 2026-W40 runs Monday 2026-09-28 to Sunday 2026-10-04.
    final week = IsoWeek(2026, 40);
    final fullWindowEnd = week.endExclusive;

    setUp(() async {
      db = await openTestDatabase();
      clock = FakeClock(DateTime(2026, 10, 12, 9));
      nutrition = NutritionRepository(db, OpenFoodFactsClient(), clock);
      tdee = TdeeEstimatesRepository(db, clock);
      repo = WeeklyReportInputsRepository(db, nutrition, tdee);
    });

    tearDown(() async => db.close());

    Future<int> food(String name, double kcalPer100g) => db
        .into(db.foods)
        .insert(FoodsCompanion.insert(name: name, kcalPer100g: kcalPer100g));

    Future<void> logAt(int foodId, DateTime day, {double grams = 100}) =>
        nutrition.logFood(date: day, foodId: foodId, grams: grams);

    Future<void> sample(String date, String kind, double value) => db
        .into(db.healthSamples)
        .insert(
          HealthSamplesCompanion.insert(
            dateIso: date,
            kind: kind,
            value: value,
          ),
        );

    Future<void> weight(
      String date,
      double kg, {
      String metric = 'bodyweight',
    }) => db
        .into(db.bodyMeasurements)
        .insert(
          BodyMeasurementsCompanion.insert(
            dateIso: date,
            metric: metric,
            value: kg,
          ),
        );

    TdeeEstimateResult estimate(int kcal, DateTime at) => TdeeEstimateResult(
      kcal: kcal,
      method: TdeeMethod.classifier,
      confidence: TdeeConfidence.medium,
      windowDays: 14,
      observedQualified: false,
      inputs: const {},
      estimatedAt: at,
    );

    test('logged days are presence-based, in-week, and skip soft-deleted '
        'entries', () async {
      final f = await food('Oats', 400);
      await logAt(f, DateTime(2026, 9, 27)); // before the week
      await logAt(f, DateTime(2026, 9, 28));
      await logAt(f, DateTime(2026, 9, 30), grams: 50);
      await logAt(f, DateTime(2026, 10, 5)); // after the week
      // A tombstoned entry on a day with nothing else.
      await db
          .into(db.foodEntries)
          .insert(
            FoodEntriesCompanion.insert(
              dateIso: '2026-09-29',
              meal: 'snack',
              foodId: Value(f),
              deletedAt: Value(DateTime(2026, 9, 29, 20)),
            ),
          );

      final inputs = await repo.load(week: week, windowEnd: fullWindowEnd);

      expect(inputs.nutrition.loggedDays, {'2026-09-28', '2026-09-30'});
      expect(inputs.nutrition.kcalByDate.keys.toSet(), {
        '2026-09-28',
        '2026-09-30',
      });
      expect(inputs.nutrition.kcalByDate['2026-09-28'], closeTo(400, 0.01));
      expect(inputs.nutrition.kcalByDate['2026-09-30'], closeTo(200, 0.01));
      expect(inputs.nutrition.proteinByDate.keys.toSet(), {
        '2026-09-28',
        '2026-09-30',
      });
      expect(inputs.nutrition.targetByDate, isEmpty);
    });

    test('a day logged with zero kcal still counts as logged', () async {
      final f = await food('Water', 0);
      await logAt(f, DateTime(2026, 9, 29));

      final inputs = await repo.load(week: week, windowEnd: fullWindowEnd);

      expect(inputs.nutrition.loggedDays, {'2026-09-29'});
      expect(inputs.nutrition.kcalByDate['2026-09-29'], 0);
    });

    test('entries dated after the window end are excluded for the current '
        'week to date', () async {
      final f = await food('Oats', 400);
      await logAt(f, DateTime(2026, 9, 29));
      await logAt(f, DateTime(2026, 10, 2)); // planned ahead

      final inputs = await repo.load(
        week: week,
        windowEnd: DateTime(2026, 9, 30, 12),
      );

      expect(inputs.nutrition.loggedDays, {'2026-09-29'});
      expect(inputs.nutrition.foodEntries, hasLength(1));
    });

    test('food entry names: snapshot, then catalogue, then recipe; '
        'unresolvable entries are skipped', () async {
      final f = await food('Catalogue Rice', 130);
      await logAt(f, DateTime(2026, 9, 28)); // snapshotName 'Catalogue Rice'

      // Snapshot name differs from the catalogue name: snapshot wins.
      await db
          .into(db.foodEntries)
          .insert(
            FoodEntriesCompanion.insert(
              dateIso: '2026-09-28',
              meal: 'lunch',
              foodId: Value(f),
              snapshotName: const Value('Frozen Name'),
            ),
          );
      // No snapshot: falls back to the catalogue food.
      await db
          .into(db.foodEntries)
          .insert(
            FoodEntriesCompanion.insert(
              dateIso: '2026-09-29',
              meal: 'lunch',
              foodId: Value(f),
            ),
          );
      // Recipe entry without a snapshot name.
      final recipeId = await db
          .into(db.recipes)
          .insert(RecipesCompanion.insert(name: 'Big Stew'));
      await db
          .into(db.foodEntries)
          .insert(
            FoodEntriesCompanion.insert(
              dateIso: '2026-09-30',
              meal: 'dinner',
              recipeId: Value(recipeId),
            ),
          );
      // Nothing to resolve a name from.
      await db
          .into(db.foodEntries)
          .insert(
            FoodEntriesCompanion.insert(dateIso: '2026-10-01', meal: 'snack'),
          );

      final inputs = await repo.load(week: week, windowEnd: fullWindowEnd);

      final names = inputs.nutrition.foodEntries.map((e) => e.name).toList();
      expect(names, [
        'Catalogue Rice',
        'Frozen Name',
        'Catalogue Rice',
        'Big Stew',
      ]);
      expect(inputs.nutrition.foodEntries[3].key, 'recipe:$recipeId');
    });

    test('health samples: week and trailing eight weeks', () async {
      await sample('2026-09-27', 'sleep_hours', 6); // before the week
      await sample('2026-09-28', 'sleep_hours', 7);
      await sample('2026-10-04', 'steps', 9000);
      await sample('2026-10-05', 'steps', 1234); // after the week
      await sample('2026-08-10', 'resting_hr', 55); // inside trailing (7 wks)
      await sample('2026-07-01', 'resting_hr', 99); // older than trailing

      final inputs = await repo.load(week: week, windowEnd: fullWindowEnd);

      expect(inputs.weekHealth.map((h) => h.dateIso).toSet(), {
        '2026-09-28',
        '2026-10-04',
      });
      expect(inputs.trailingHealth.map((h) => h.dateIso).toSet(), {
        '2026-08-10',
        '2026-09-27',
        '2026-09-28',
        '2026-10-04',
      });
    });

    test('weights: bodyweight only, up to the window end, ascending', () async {
      await weight('2026-09-20', 81.0);
      await weight('2026-10-02', 80.2);
      await weight('2026-09-29', 80.6);
      await weight('2026-09-29', 12, metric: 'waist'); // other metric
      await weight('2026-10-08', 79.0); // after the week

      final inputs = await repo.load(week: week, windowEnd: fullWindowEnd);

      expect(inputs.weights.map((w) => w.dateIso), [
        '2026-09-20',
        '2026-09-29',
        '2026-10-02',
      ]);
      expect(inputs.weights.map((w) => w.kg), [81.0, 80.6, 80.2]);
    });

    test('check-ins: kind checkin, not deleted, inside the week', () async {
      final goalId = await db
          .into(db.physiqueGoals)
          .insert(PhysiqueGoalsCompanion());
      Future<void> assess(
        String kind,
        String date, {
        String? verdict,
        DateTime? deletedAt,
      }) => db
          .into(db.physiqueAssessments)
          .insert(
            PhysiqueAssessmentsCompanion.insert(
              goalId: goalId,
              kind: kind,
              dateIso: date,
              verdict: Value(verdict),
              deletedAt: Value(deletedAt),
            ),
          );

      await assess('checkin', '2026-09-30', verdict: 'on_track');
      await assess('analysis', '2026-09-30', verdict: 'off_track');
      await assess('checkin', '2026-10-01', deletedAt: DateTime(2026, 10, 2));
      await assess('checkin', '2026-09-21', verdict: 'off_track');
      await assess('checkin', '2026-10-06', verdict: 'off_track');

      final inputs = await repo.load(week: week, windowEnd: fullWindowEnd);

      expect(inputs.checkIns, hasLength(1));
      expect(inputs.checkIns.single.dateIso, '2026-09-30');
      expect(inputs.checkIns.single.verdict, 'on_track');
    });

    test('tdee rows: newest at or before window end, newest before the week '
        'start', () async {
      await tdee.record(estimate(2400, DateTime(2026, 9, 14, 8)));
      await tdee.record(estimate(2450, DateTime(2026, 9, 21, 8)));
      await tdee.record(estimate(2500, DateTime(2026, 10, 1, 8)));
      await tdee.record(estimate(2600, DateTime(2026, 10, 9, 8))); // later

      final inputs = await repo.load(week: week, windowEnd: fullWindowEnd);

      expect(inputs.tdeeNewest?.kcal, 2500);
      expect(inputs.tdeeBefore?.kcal, 2450);
    });

    test('tdee rows are null when there is no history', () async {
      final inputs = await repo.load(week: week, windowEnd: fullWindowEnd);

      expect(inputs.tdeeNewest, isNull);
      expect(inputs.tdeeBefore, isNull);
      expect(inputs.snapshot.sets, isEmpty);
    });

    test(
      'load is deterministic: the injected time never moves the result',
      () async {
        final f = await food('Oats', 400);
        await logAt(f, DateTime(2026, 9, 28));
        await sample('2026-09-29', 'steps', 8000);
        await weight('2026-09-30', 80);

        final a = await repo.load(week: week, windowEnd: fullWindowEnd);
        (clock as FakeClock).set(DateTime(2027, 3, 1));
        final b = await repo.load(week: week, windowEnd: fullWindowEnd);

        expect(b.nutrition.loggedDays, a.nutrition.loggedDays);
        expect(b.nutrition.kcalByDate, a.nutrition.kcalByDate);
        expect(
          b.weekHealth.map((h) => h.id).toList(),
          a.weekHealth.map((h) => h.id).toList(),
        );
        expect(
          b.weights.map((w) => w.kg).toList(),
          a.weights.map((w) => w.kg).toList(),
        );
      },
    );
  });
}
