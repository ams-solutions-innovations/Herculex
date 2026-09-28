import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/core/utils/clock.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/nutrition/application/tdee_providers.dart';
import 'package:herculex/features/nutrition/application/tdee_recalibration_controller.dart';
import 'package:herculex/features/nutrition/data/nutrition_repository.dart';
import 'package:herculex/features/nutrition/data/openfoodfacts_client.dart';
import 'package:herculex/features/nutrition/data/tdee_estimates_repository.dart';
import 'package:herculex/features/nutrition/data/tdee_inputs_repository.dart';
import 'package:herculex/features/nutrition/domain/macro_targets.dart';
import 'package:herculex/features/nutrition/domain/tdee_estimate.dart';
import 'package:herculex/features/profile/domain/profile.dart';

import '../../support/test_database.dart';

class _FixedClock implements Clock {
  _FixedClock(this.time);
  DateTime time;
  @override
  DateTime now() => time;
}

class _FakeRecalibrator implements TdeeRecalibrator {
  final calls = <bool>[];
  @override
  Future<TdeeEstimateResult?> run({bool force = false}) async {
    calls.add(force);
    return null;
  }
}

const _profile = Profile(
  goal: FitnessGoal.maintenance,
  activityLevel: ActivityLevel.active,
  ageYears: 28,
  weightKg: 80,
  heightCm: 180,
  sex: BiologicalSex.male,
);

DateTime _noon(int y, int m, int d) => DateTime(y, m, d, 12);

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late _FixedClock clock;
  late NutritionRepository nutrition;
  late TdeeEstimatesRepository history;
  late TdeeInputsRepository inputs;
  late int foodId;
  Profile? profile;
  late TdeeRecalibrator recalibrator;

  setUp(() async {
    db = await openTestDatabase();
    clock = _FixedClock(_noon(2026, 2, 1));
    nutrition = NutritionRepository(db, OpenFoodFactsClient(), clock);
    history = TdeeEstimatesRepository(db, clock);
    inputs = TdeeInputsRepository(db, nutrition, clock);
    profile = _profile;
    recalibrator = TdeeRecalibrator(
      () async => profile,
      history,
      inputs,
      clock,
    );
    // 250 kcal per 100 g, so 1000 g is 2500 kcal.
    foodId = await db
        .into(db.foods)
        .insert(FoodsCompanion.insert(name: 'Fuel', kcalPer100g: 250));
  });

  tearDown(() async {
    await db.close();
  });

  Future<List<TdeeEstimateResult>> rows() => history.recent(limit: 50);

  Future<void> logFoodOn(DateTime day) =>
      nutrition.logFood(date: day, foodId: foodId, grams: 1000);

  Future<void> logWeightOn(DateTime day, double kg) => db
      .into(db.bodyMeasurements)
      .insert(
        BodyMeasurementsCompanion.insert(
          dateIso: dateIsoOf(day),
          metric: 'bodyweight',
          value: kg,
        ),
      );

  // Fixture L: food every day from 2026-02-01, weight every second day from
  // 2026-02-01 (last log 2026-03-01), nothing after 2026-03-01.
  final fixtureStart = DateTime(2026, 2, 1);
  final fixtureEnd = DateTime(2026, 3, 1);
  var loggedThrough = DateTime(2026, 1, 31);

  Future<void> logThrough(DateTime end) async {
    var d = loggedThrough.add(const Duration(days: 1));
    d = DateTime(d.year, d.month, d.day);
    while (!d.isAfter(end) && !d.isAfter(fixtureEnd)) {
      await logFoodOn(d);
      final index = DateTime.utc(
        d.year,
        d.month,
        d.day,
      ).difference(DateTime.utc(2026, 2, 1)).inDays;
      if (index.isEven) await logWeightOn(d, 80.0);
      d = DateTime(d.year, d.month, d.day + 1);
    }
    loggedThrough = end.isAfter(fixtureEnd) ? fixtureEnd : end;
  }

  setUp(() {
    loggedThrough = fixtureStart.subtract(const Duration(days: 1));
  });

  ProviderContainer wired(_FakeRecalibrator fake, Stream<Profile?> profiles) {
    final c = ProviderContainer(
      overrides: [
        tdeeRecalibratorProvider.overrideWithValue(fake),
        profileProvider.overrideWith((ref) => profiles),
        latestTdeeEstimateProvider.overrideWith((ref) => Stream.value(null)),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  Future<TdeeEstimateResult?> runOn(
    int y,
    int m,
    int d, {
    bool force = false,
  }) async {
    clock.time = _noon(y, m, d);
    await logThrough(DateTime(y, m, d));
    return recalibrator.run(force: force);
  }

  group('TdeeRecalibrator', () {
    test('empty database records one coldStart row, then nothing', () async {
      final seed = MacroTargets.seedMaintenanceKcal(_profile)!;
      final first = await recalibrator.run();
      expect(first, isNotNull);
      expect(first!.method, TdeeMethod.coldStart);
      expect(first.kcal, seed.round());
      expect(first.windowDays, 0);
      expect(first.observedQualified, isFalse);
      expect((await rows()).length, 1);

      expect(await recalibrator.run(), isNull);
      expect((await rows()).length, 1);
    });

    test('logging stopped: fresh -> held -> fallback (fixture L)', () async {
      final seed = MacroTargets.seedMaintenanceKcal(_profile)!.round();

      // 1. First run with qualifying data stays pending on coldStart.
      final r1 = await runOn(2026, 2, 15);
      expect(r1!.method, TdeeMethod.coldStart);
      expect(r1.observedQualified, isTrue);
      expect(await recalibrator.run(), isNull);

      // 2. Seven days later the second qualifying run promotes.
      final r2 = await runOn(2026, 2, 22);
      expect(r2!.method, TdeeMethod.observed);
      expect(r2.observedQualified, isTrue);
      expect(await recalibrator.run(), isNull);

      // 3. Fresh row F, everything logged today.
      final r3 = await runOn(2026, 3, 1);
      expect(r3!.method, TdeeMethod.observed);
      expect(r3.observedQualified, isTrue);
      expect(r3.kcal, 2500);
      expect(r3.estimatedAt, _noon(2026, 3, 1));
      expect(await recalibrator.run(), isNull);

      // 4. A week of silence: held (aging), same kcal as F.
      final r4 = await runOn(2026, 3, 8);
      expect(r4!.method, TdeeMethod.observed);
      expect(r4.observedQualified, isFalse);
      expect(r4.kcal, r3.kcal);
      expect(r4.inputs['held'], isTrue);
      expect(r4.inputs['measured_at'], '2026-03-01');
      expect(r4.badgeState, TdeeBadgeState.measuredAging);
      expect(await recalibrator.run(), isNull);

      // 5. Two weeks of silence: fallback to the seed.
      final r5 = await runOn(2026, 3, 15);
      expect(r5!.method, TdeeMethod.coldStart);
      expect(r5.kcal, seed);
      expect(r5.observedQualified, isFalse);
      expect(await recalibrator.run(), isNull);

      expect((await rows()).length, 5);
    });

    test('force writes a row even on the same day', () async {
      await recalibrator.run();
      final forced = await recalibrator.run(force: true);
      expect(forced, isNotNull);
      expect((await rows()).length, 2);
    });

    test('null or incomplete profile writes nothing', () async {
      profile = null;
      expect(await recalibrator.run(), isNull);

      profile = const Profile(
        goal: FitnessGoal.maintenance,
        activityLevel: ActivityLevel.active,
        weightKg: 80,
      );
      expect(await recalibrator.run(force: true), isNull);
      expect((await rows()).length, 0);
    });

    test('repository failure is swallowed and returns null', () async {
      final broken = await openTestDatabase();
      final clk = _FixedClock(_noon(2026, 2, 1));
      final r = TdeeRecalibrator(
        () async => _profile,
        TdeeEstimatesRepository(broken, clk),
        TdeeInputsRepository(
          broken,
          NutritionRepository(broken, OpenFoodFactsClient(), clk),
          clk,
        ),
        clk,
      );
      await broken.close();
      expect(await r.run(), isNull);
    });

    test('concurrent runs do not double-write', () async {
      final f1 = recalibrator.run();
      final f2 = recalibrator.run();
      final results = await Future.wait([f1, f2]);
      expect(results.where((r) => r != null).length, 1);
      expect((await rows()).length, 1);
    });

    test('nutrition_targets is untouched by any run', () async {
      await db
          .into(db.nutritionTargets)
          .insert(
            NutritionTargetsCompanion.insert(
              label: 'Manual',
              kcal: 2222,
              proteinG: 150,
              carbsG: 250,
              fatG: 70,
              appliesTo: const Value('global'),
            ),
          );
      final before = await db.select(db.nutritionTargets).get();

      await runOn(2026, 2, 15);
      await runOn(2026, 2, 22);
      await recalibrator.run(force: true);

      final after = await db.select(db.nutritionTargets).get();
      expect(after, before);
    });
  });

  group('resume', () {
    test('same-day resume is a no-op even when data changed', () async {
      await runOn(2026, 2, 15);
      final count = (await rows()).length;

      clock.time = DateTime(2026, 2, 15, 20);
      await db
          .into(db.healthSamples)
          .insert(
            HealthSamplesCompanion.insert(
              dateIso: '2026-02-15',
              kind: 'steps',
              value: 12000,
            ),
          );
      await logWeightOn(DateTime(2026, 2, 15), 83);

      expect(await recalibrator.run(), isNull);
      expect((await rows()).length, count);
    });

    test('resume after the cadence records exactly one row per day', () async {
      await runOn(2026, 2, 15);
      await runOn(2026, 2, 22);
      final before = (await rows()).length;

      clock.time = _noon(2026, 3, 1);
      await logThrough(DateTime(2026, 3, 1));
      final resumed = await recalibrator.run();
      expect(resumed, isNotNull);
      expect((await rows()).length, before + 1);

      // A second resume the same day records nothing.
      clock.time = DateTime(2026, 3, 1, 22);
      expect(await recalibrator.run(), isNull);
      expect((await rows()).length, before + 1);
    });

    test(
      'overlapping resume during an in-flight run does not double-write',
      () async {
        await logThrough(DateTime(2026, 2, 15));
        clock.time = _noon(2026, 2, 15);
        final a = recalibrator.run();
        final b = recalibrator.run();
        await Future.wait([a, b]);
        expect((await rows()).length, 1);
      },
    );

    test('only resumed triggers a non-forced run; dispose detaches', () async {
      final fake = _FakeRecalibrator();
      final c = wired(fake, Stream.value(null));
      c.read(tdeeRecalibrationControllerProvider);
      await Future<void>.delayed(Duration.zero);
      expect(fake.calls, isEmpty);

      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.detached);
      expect(fake.calls, isEmpty);

      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(fake.calls, [false]);

      c.dispose();
      binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(fake.calls, [false]);
    });
  });

  group('tdeeRecalibrationControllerProvider', () {
    test('profile arrival runs once; level change forces a run', () async {
      final fake = _FakeRecalibrator();
      final profiles = StreamController<Profile?>();
      addTearDown(profiles.close);
      final c = wired(fake, profiles.stream);
      c.read(tdeeRecalibrationControllerProvider);

      profiles.add(null);
      await pumpEventQueue();
      expect(fake.calls, isEmpty);

      profiles.add(_profile);
      await pumpEventQueue();
      expect(fake.calls, [false]);

      // Same activity level, different weight: no run.
      profiles.add(_profile.copyWith(weightKg: 81));
      await pumpEventQueue();
      expect(fake.calls, [false]);

      // Manual reset: forced.
      profiles.add(_profile.copyWith(activityLevel: ActivityLevel.veryActive));
      await pumpEventQueue();
      expect(fake.calls, [false, true]);
    });

    test('end to end: a reset reseeds through a forced history row', () async {
      final profiles = StreamController<Profile?>();
      addTearDown(profiles.close);
      final c = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          clockProvider.overrideWithValue(clock),
          profileProvider.overrideWith((ref) => profiles.stream),
        ],
      );
      addTearDown(c.dispose);
      c.read(tdeeRecalibrationControllerProvider);

      Future<void> until(bool Function() ok) async {
        for (var i = 0; i < 200 && !ok(); i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      }

      profiles.add(_profile);
      await until(
        () => c.read(latestTdeeEstimateProvider).asData?.value != null,
      );
      expect((await rows()).length, 1);

      final reset = _profile.copyWith(activityLevel: ActivityLevel.veryActive);
      profiles.add(reset);
      await until(
        () =>
            c.read(maintenanceKcalProvider) ==
            MacroTargets.seedMaintenanceKcal(reset)!.round(),
      );
      final all = await rows();
      expect(all.length, 2);
      expect(all.first.kcal, MacroTargets.seedMaintenanceKcal(reset)!.round());
      expect(c.read(maintenanceKcalProvider), all.first.kcal);
    });
  });
}

String dateIsoOf(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';
