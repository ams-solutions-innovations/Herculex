import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/core/utils/clock.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/nutrition/application/nutrition_providers.dart';
import 'package:herculex/features/nutrition/application/tdee_providers.dart';
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

const _profile = Profile(
  goal: FitnessGoal.muscleGain,
  activityLevel: ActivityLevel.active,
  ageYears: 28,
  weightKg: 80,
  heightCm: 180,
  sex: BiologicalSex.male,
);

TdeeEstimateResult _row(
  int kcal,
  TdeeMethod method, {
  bool qualified = true,
}) => TdeeEstimateResult(
  kcal: kcal,
  method: method,
  confidence: TdeeConfidence.medium,
  windowDays: method == TdeeMethod.coldStart ? 0 : 28,
  observedQualified: qualified,
  inputs: const {},
  estimatedAt: DateTime(2026, 9, 20, 9),
);

void _expectSameTargets(MacroTargets? actual, MacroTargets? expected) {
  expect(actual, isNotNull);
  expect(expected, isNotNull);
  expect(actual!.kcal, expected!.kcal);
  expect(actual.proteinG, expected.proteinG);
  expect(actual.carbsG, expected.carbsG);
  expect(actual.fatG, expected.fatG);
}

void main() {
  final clock = _FixedClock(DateTime(2026, 9, 28, 12));

  ProviderContainer make({
    Stream<Profile?>? profile,
    required Stream<TdeeEstimateResult?> estimate,
    List<Override> extra = const [],
  }) {
    final container = ProviderContainer(
      overrides: [
        clockProvider.overrideWithValue(clock),
        profileProvider.overrideWith((ref) => profile ?? Stream.value(_profile)),
        latestTdeeEstimateProvider.overrideWith((ref) => estimate),
        ...extra,
      ],
    );
    addTearDown(container.dispose);
    // Keep the estimate stream subscribed, as the app's controller does.
    container.listen(latestTdeeEstimateProvider, (_, _) {});
    return container;
  }

  Future<void> settle(ProviderContainer c) async {
    await c.read(profileProvider.future);
    // Let the estimate stream deliver (or not) before reading.
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
  }

  final seed = MacroTargets.seedMaintenanceKcal(_profile)!;

  void expectSeedEstimate(TdeeEstimateResult? est) {
    expect(est, isNotNull);
    expect(est!.method, TdeeMethod.coldStart);
    expect(est.kcal, seed.round());
    expect(est.confidence, TdeeConfidence.low);
    expect(est.windowDays, 0);
    expect(est.inputs['onboarding_level'], 'Active');
    expect(est.inputs['activity_factor'], 1.55);
  }

  group('tdeeEstimateProvider / baselineTargetsProvider', () {
    test('null estimate row yields the cold-start seed', () async {
      final c = make(estimate: Stream.value(null));
      await settle(c);

      expectSeedEstimate(c.read(tdeeEstimateProvider));
      _expectSameTargets(
        c.read(baselineTargetsProvider),
        MacroTargets.fromProfile(_profile),
      );
    });

    test('loading estimate stream degrades to the seed without error', () async {
      final controller = StreamController<TdeeEstimateResult?>();
      addTearDown(controller.close);
      final c = make(estimate: controller.stream);
      await settle(c);

      expectSeedEstimate(c.read(tdeeEstimateProvider));
      _expectSameTargets(
        c.read(baselineTargetsProvider),
        MacroTargets.fromProfile(_profile),
      );
    });

    test('estimate stream error degrades to the seed without error', () async {
      final c = make(estimate: Stream.error(StateError('boom')));
      await settle(c);

      expectSeedEstimate(c.read(tdeeEstimateProvider));
      _expectSameTargets(
        c.read(baselineTargetsProvider),
        MacroTargets.fromProfile(_profile),
      );
    });

    test('observed row is used and the goal delta is added once', () async {
      final c = make(estimate: Stream.value(_row(2600, TdeeMethod.observed)));
      await settle(c);

      expect(c.read(tdeeEstimateProvider)!.kcal, 2600);
      expect(c.read(maintenanceKcalProvider), 2600);
      final baseline = c.read(baselineTargetsProvider)!;
      _expectSameTargets(baseline, MacroTargets.fromMaintenance(_profile, 2600));
      // muscleGain: +300 exactly once.
      expect(baseline.kcal, 2900);
    });

    test('classifier row is used', () async {
      final c = make(estimate: Stream.value(_row(2400, TdeeMethod.classifier)));
      await settle(c);

      expect(c.read(maintenanceKcalProvider), 2400);
      expect(c.read(baselineTargetsProvider)!.kcal, 2700);
    });

    test('stored coldStart kcal is ignored in favour of the live seed', () async {
      final c = make(estimate: Stream.value(_row(2000, TdeeMethod.coldStart)));
      await settle(c);

      expect(c.read(maintenanceKcalProvider), seed.round());
      _expectSameTargets(
        c.read(baselineTargetsProvider),
        MacroTargets.fromProfile(_profile),
      );
    });

    test('changing ActivityLevel reseeds without any new row', () async {
      final profiles = StreamController<Profile?>();
      addTearDown(profiles.close);
      final c = make(
        profile: profiles.stream,
        estimate: Stream.value(_row(2000, TdeeMethod.coldStart)),
      );
      final sub = c.listen(tdeeEstimateProvider, (_, _) {});
      addTearDown(sub.close);

      profiles.add(_profile);
      await settle(c);
      expect(c.read(maintenanceKcalProvider), seed.round());

      final reset = _profile.copyWith(activityLevel: ActivityLevel.veryActive);
      profiles.add(reset);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(
        c.read(maintenanceKcalProvider),
        MacroTargets.seedMaintenanceKcal(reset)!.round(),
      );
      expect(c.read(maintenanceKcalProvider), isNot(seed.round()));
    });

    test('an observed user keeps their method after a manual reset', () async {
      final profiles = StreamController<Profile?>();
      addTearDown(profiles.close);
      final c = make(
        profile: profiles.stream,
        estimate: Stream.value(_row(2600, TdeeMethod.observed)),
      );
      final sub = c.listen(tdeeEstimateProvider, (_, _) {});
      addTearDown(sub.close);

      profiles.add(_profile.copyWith(activityLevel: ActivityLevel.sedentary));
      await settle(c);

      expect(c.read(tdeeEstimateProvider)!.method, TdeeMethod.observed);
      expect(c.read(maintenanceKcalProvider), 2600);
    });

    test('null profile yields null baseline and maintenance', () async {
      final c = make(
        profile: Stream.value(null),
        estimate: Stream.value(_row(2600, TdeeMethod.observed)),
      );
      await settle(c);

      expect(c.read(baselineTargetsProvider), isNull);
      expect(c.read(maintenanceKcalProvider), isNull);
      expect(c.read(tdeeEstimateProvider), isNull);
    });

    test('profile missing weight/height/age yields null', () async {
      const partial = Profile(
        goal: FitnessGoal.maintenance,
        activityLevel: ActivityLevel.active,
        weightKg: 80,
      );
      final c = make(
        profile: Stream.value(partial),
        estimate: Stream.value(_row(2600, TdeeMethod.observed)),
      );
      await settle(c);

      expect(c.read(baselineTargetsProvider), isNull);
      expect(c.read(maintenanceKcalProvider), isNull);
    });
  });

  group('TDEE-04 saved manual target wins', () {
    test('a saved global rule beats an observed estimate', () async {
      final db = await openTestDatabase();
      addTearDown(db.close);

      const saved = NutritionTargetData(
        id: 1,
        label: 'Manual',
        kcal: 2222,
        proteinG: 150,
        carbsG: 250,
        fatG: 70,
        appliesTo: 'global',
      );
      final c = make(
        estimate: Stream.value(_row(3000, TdeeMethod.observed)),
        extra: [
          appDatabaseProvider.overrideWithValue(db),
          nutritionTargetsProvider.overrideWith((ref) => Stream.value([saved])),
          activeDietScheduleProvider.overrideWith((ref) => Stream.value(null)),
        ],
      );
      await settle(c);

      final date = DateTime(2026, 9, 28);
      final effective = await c.read(effectiveTargetsProvider(date).future);
      expect(effective!.kcal, 2222);

      // Sanity: without the saved rule the estimate would have been used.
      expect(c.read(baselineTargetsProvider)!.kcal, 3300);
    });
  });
}
