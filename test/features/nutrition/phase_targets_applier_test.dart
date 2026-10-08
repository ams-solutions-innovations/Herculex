import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/nutrition/application/goals_providers.dart';
import 'package:herculex/features/nutrition/application/phase_targets_applier.dart';
import 'package:herculex/features/nutrition/domain/diet_phase.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/test_database.dart';

void main() {
  late AppDatabase db;
  late SharedPreferences prefs;
  late ProviderContainer container;

  Future<void> setUpWith(Map<String, Object> initial) async {
    SharedPreferences.setMockInitialValues(initial);
    prefs = await SharedPreferences.getInstance();
    db = await openTestDatabase();
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        appDatabaseProvider.overrideWithValue(db),
      ],
    );
  }

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  group('ActiveDietPlan.isSet', () {
    test('is false while only the defaults are showing', () async {
      await setUpWith({});
      final plan = container.read(activeDietPlanProvider);
      expect(plan.isSet, isFalse);
      expect(plan.phase, DietPhase.cut, reason: 'the default stays as is');
    });

    test('is true once a plan was stored', () async {
      await setUpWith({'diet_active_phase': 'bulk'});
      final plan = container.read(activeDietPlanProvider);
      expect(plan.isSet, isTrue);
      expect(plan.phase, DietPhase.bulk);
    });
  });

  group('PhaseTargetsApplier', () {
    test('writes the daily target and the active plan together', () async {
      await setUpWith({});
      final pace = DietPhaseCalculator.paceOptionsFor(DietPhase.cut)[1];
      await container
          .read(phaseTargetsApplierProvider)
          .apply(
            phase: DietPhase.cut,
            pace: pace,
            targets: const PhaseTargets(
              kcal: 2000,
              proteinG: 176,
              carbsG: 200,
              fatG: 60,
              deltaKcal: -500,
            ),
          );

      final rows = await db.select(db.nutritionTargets).get();
      expect(rows, hasLength(1));
      expect(rows.single.label, 'General (Cut)');
      expect(rows.single.appliesTo, 'global');
      expect(rows.single.kcal, 2000);
      expect(rows.single.proteinG, 176);
      expect(rows.single.carbsG, 200);
      expect(rows.single.fatG, 60);

      final plan = container.read(activeDietPlanProvider);
      expect(plan.isSet, isTrue);
      expect(plan.phase, DietPhase.cut);
      expect(plan.weeklyRateKg, 0.5);
      expect(plan.kcalDelta, -500);
      expect(plan.paceLabel, pace.label);
      expect(prefs.getString('diet_active_phase'), 'cut');
    });

    test('a later phase replaces the plan', () async {
      await setUpWith({});
      final applier = container.read(phaseTargetsApplierProvider);
      await applier.apply(
        phase: DietPhase.cut,
        pace: DietPhaseCalculator.paceOptionsFor(DietPhase.cut)[1],
        targets: const PhaseTargets(
          kcal: 2000,
          proteinG: 176,
          carbsG: 200,
          fatG: 60,
        ),
      );
      await applier.apply(
        phase: DietPhase.maintain,
        pace: DietPhaseCalculator.paceOptionsFor(DietPhase.maintain).single,
        targets: const PhaseTargets(
          kcal: 2500,
          proteinG: 144,
          carbsG: 300,
          fatG: 80,
        ),
      );
      final plan = container.read(activeDietPlanProvider);
      expect(plan.phase, DietPhase.maintain);
      expect(plan.kcalDelta, 0);
      final labels = [
        for (final r in await db.select(db.nutritionTargets).get()) r.label,
      ];
      expect(labels, contains('General (Maintenance)'));
    });
  });
}
