import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/core/utils/clock.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/nutrition/data/nutrition_repository.dart';
import 'package:herculex/features/nutrition/data/openfoodfacts_client.dart';
import 'package:herculex/features/nutrition/data/tdee_inputs_repository.dart';
import 'package:herculex/features/nutrition/domain/meal.dart';

import 'support/test_database.dart';

class _FixedClock implements Clock {
  DateTime time;
  _FixedClock(this.time);
  @override
  DateTime now() => time;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TdeeInputsRepository', () {
    late AppDatabase db;
    late _FixedClock clock;
    late NutritionRepository nutrition;
    late TdeeInputsRepository repo;

    // "Today" is 2026-09-28; the 60-day lookback starts 2026-07-30.
    final today = DateTime(2026, 9, 28, 12);

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

    Future<void> weight(String date, double kg, {String metric = 'bodyweight'}) =>
        db
            .into(db.bodyMeasurements)
            .insert(
              BodyMeasurementsCompanion.insert(
                dateIso: date,
                metric: metric,
                value: kg,
              ),
            );

    setUp(() async {
      db = await openTestDatabase();
      clock = _FixedClock(today);
      nutrition = NutritionRepository(db, OpenFoodFactsClient(), clock);
      repo = TdeeInputsRepository(db, nutrition, clock);
    });

    tearDown(() async {
      await db.close();
    });

    test('empty database returns empty collections and never throws', () async {
      final i = await repo.load();
      expect(i.foodLoggedDays, isEmpty);
      expect(i.dailyKcalByDate, isEmpty);
      expect(i.weightLogs, isEmpty);
      expect(i.stepsByDate, isEmpty);
      expect(i.avgActiveKcal, isNull);
      expect(i.avgSleepHours, isNull);
      expect(i.avgRestingHr, isNull);
      expect(i.workoutsPerWeek, 0);
    });

    test('foodLoggedDays are distinct dateIso values within 60 days', () async {
      final f = await food('Rice', 130);
      // 10 entries across 6 distinct days.
      for (final d in [1, 1, 2, 3, 3, 3, 4, 5, 5, 6]) {
        await logAt(f, DateTime(2026, 9, d));
      }
      // Older than the 60-day lookback: excluded.
      await logAt(f, DateTime(2026, 7, 1));

      final i = await repo.load();
      expect(i.foodLoggedDays, {
        '2026-09-01',
        '2026-09-02',
        '2026-09-03',
        '2026-09-04',
        '2026-09-05',
        '2026-09-06',
      });
    });

    test('a zero-kcal entry still counts the day as logged (presence)',
        () async {
      final water = await food('Water', 0);
      await logAt(water, DateTime(2026, 9, 10));

      final i = await repo.load();
      expect(i.foodLoggedDays, contains('2026-09-10'));
      expect(i.dailyKcalByDate['2026-09-10'], 0);
    });

    test('dailyKcalByDate sums snapshot-aware totals per logged day', () async {
      final a = await food('A', 100); // 100 kcal per 100 g
      final b = await food('B', 200);
      await logAt(a, DateTime(2026, 9, 12));
      await logAt(b, DateTime(2026, 9, 12), grams: 50); // 100 kcal
      await logAt(a, DateTime(2026, 9, 13), grams: 250); // 250 kcal

      final i = await repo.load();
      expect(i.dailyKcalByDate['2026-09-12'], closeTo(200, 0.01));
      expect(i.dailyKcalByDate['2026-09-13'], closeTo(250, 0.01));
      expect(i.dailyKcalByDate.keys.toSet(), i.foodLoggedDays);

      // Editing the catalogue later does not move a snapshotted entry.
      await db.customStatement('UPDATE foods SET kcal_per100g = 999');
      final again = await repo.load();
      expect(again.dailyKcalByDate['2026-09-12'], closeTo(200, 0.01));
    });

    test('weightLogs are bodyweight only, ascending, within 60 days', () async {
      await weight('2026-09-20', 80.4);
      await weight('2026-09-10', 81.0);
      await weight('2026-09-15', 40.0, metric: 'waist');
      await weight('2026-07-01', 90.0); // too old

      final i = await repo.load();
      expect(i.weightLogs.map((w) => w.kg), [81.0, 80.4]);
      expect(i.weightLogs.first.date, DateTime(2026, 9, 10));
      expect(i.weightLogs.last.date, DateTime(2026, 9, 20));
    });

    test('soft-deleted food and weight rows are excluded', () async {
      final f = await food('Rice', 130);
      await logAt(f, DateTime(2026, 9, 10));
      await weight('2026-09-10', 80);
      await db.update(db.foodEntries).write(
        FoodEntriesCompanion(deletedAt: Value(DateTime(2026, 9, 11))),
      );
      await db.update(db.bodyMeasurements).write(
        BodyMeasurementsCompanion(deletedAt: Value(DateTime(2026, 9, 11))),
      );

      final i = await repo.load();
      expect(i.foodLoggedDays, isEmpty);
      expect(i.weightLogs, isEmpty);
    });

    test('stepsByDate holds only steps rows within 60 days', () async {
      await sample('2026-09-20', 'steps', 8000);
      await sample('2026-09-21', 'steps', 9500);
      await sample('2026-07-01', 'steps', 1234); // too old
      await sample('2026-09-20', 'food_kcal', 2000);
      await sample('2026-09-20', 'weight_kg', 80);
      await sample('2026-09-20', 'sleep_hours', 7);

      final i = await repo.load();
      expect(i.stepsByDate, {'2026-09-20': 8000, '2026-09-21': 9500});
    });

    test('health averages use the last 14 days of their kinds', () async {
      await sample('2026-09-20', 'active_kcal', 400);
      await sample('2026-09-22', 'active_kcal', 600);
      await sample('2026-08-01', 'active_kcal', 9999); // outside 14 days
      await sample('2026-09-20', 'sleep_hours', 7);
      await sample('2026-09-21', 'sleep_hours', 8);
      await sample('2026-09-21', 'resting_hr', 60);

      final i = await repo.load();
      expect(i.avgActiveKcal, closeTo(500, 0.001));
      expect(i.avgSleepHours, closeTo(7.5, 0.001));
      expect(i.avgRestingHr, closeTo(60, 0.001));
    });

    test('averages are null when only other kinds exist', () async {
      await sample('2026-09-20', 'steps', 8000);
      final i = await repo.load();
      expect(i.avgActiveKcal, isNull);
      expect(i.avgSleepHours, isNull);
      expect(i.avgRestingHr, isNull);
    });

    test('workoutsPerWeek counts completed sessions in 28 days / 4', () async {
      Future<void> session(DateTime start, {DateTime? end}) => db
          .into(db.workoutSessions)
          .insert(
            WorkoutSessionsCompanion.insert(
              startedAt: start,
              endedAt: Value(end),
            ),
          );

      for (var d = 1; d <= 8; d++) {
        final s = DateTime(2026, 9, d, 18);
        await session(s, end: s.add(const Duration(hours: 1)));
      }
      // Unfinished: not counted.
      await session(DateTime(2026, 9, 20, 18));
      // Older than 28 days: not counted (window starts 2026-08-31 12:00).
      final old = DateTime(2026, 8, 1, 18);
      await session(old, end: old.add(const Duration(hours: 1)));

      final i = await repo.load();
      expect(i.workoutsPerWeek, closeTo(8 / 4, 0.0001));
    });

    test('dateIso helper matches the stored key format', () {
      expect(dateIso(DateTime(2026, 9, 5)), '2026-09-05');
    });
  });
}
