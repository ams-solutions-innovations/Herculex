import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/nutrition/application/goals_providers.dart';
import 'package:herculex/features/nutrition/data/nutrition_repository.dart';
import 'package:herculex/features/nutrition/data/openfoodfacts_client.dart';
import 'package:herculex/features/nutrition/domain/diet_phase.dart';
import 'package:herculex/features/nutrition/domain/target_resolver.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../support/fake_clock.dart';
import '../../support/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late NutritionRepository repo;
  late FakeClock clock;
  setUp(() async {
    db = await openTestDatabase();
    clock = FakeClock(DateTime(2026, 10, 21, 14));
    repo = NutritionRepository(db, OpenFoodFactsClient(), clock);
  });
  tearDown(() => db.close());

  Future<void> save(DateTime from, int kcal) => repo.upsertTarget(
    label: 'General',
    appliesTo: 'global',
    kcal: kcal,
    proteinG: 150,
    carbsG: 200,
    fatG: 65,
    effectiveFrom: from,
  );

  Future<int?> at(DateTime date) async {
    final rows = await repo.watchTargets().first;
    return TargetResolver.resolveRule(
      rules: [
        for (final r in rows)
          TargetRule(
            kcal: r.kcal,
            proteinG: r.proteinG,
            carbsG: r.carbsG,
            fatG: r.fatG,
            appliesTo: r.appliesTo,
            effectiveFromDateIso: r.effectiveFromDateIso,
          ),
      ],
      date: date,
      isTrainingDay: false,
    )?.kcal;
  }

  test(
    'today, tomorrow and a past edit preserve their separate intervals',
    () async {
      await db
          .into(db.nutritionTargets)
          .insert(
            NutritionTargetsCompanion.insert(
              label: 'Original',
              kcal: 2500,
              proteinG: 150,
              carbsG: 300,
              fatG: 70,
            ),
          );
      await save(DateTime(2026, 10, 21), 2100);
      await save(DateTime(2026, 10, 22), 2300);
      await save(DateTime(2026, 10, 1), 2000);
      expect(await at(DateTime(2026, 9, 30)), 2500);
      expect(await at(DateTime(2026, 10, 1)), 2000);
      expect(await at(DateTime(2026, 10, 20)), 2000);
      expect(await at(DateTime(2026, 10, 21)), 2100);
      expect(await at(DateTime(2026, 10, 22)), 2300);
      expect(await at(DateTime(2027, 1, 1)), 2300);
    },
  );

  test(
    're-saving a scope/start retains its identity and other scheduled versions',
    () async {
      await save(DateTime(2026, 10, 21), 2100);
      await save(DateTime(2026, 11, 1), 2400);
      final old = (await repo.watchTargets().first).first;
      await save(DateTime(2026, 10, 21), 2200);
      final rows = await repo.watchTargets().first;
      expect(rows, hasLength(2));
      expect(rows.first.id, old.id);
      expect(rows.first.syncUuid, old.syncUuid);
      expect(await at(DateTime(2026, 10, 21)), 2200);
      expect(await at(DateTime(2026, 11, 1)), 2400);
    },
  );

  test(
    'future overrides are ineligible until their date and specificity survives',
    () {
      const rules = [
        TargetRule(
          kcal: 2000,
          proteinG: 100,
          carbsG: 200,
          fatG: 60,
          appliesTo: 'global',
        ),
        TargetRule(
          kcal: 2500,
          proteinG: 150,
          carbsG: 250,
          fatG: 70,
          appliesTo: 'training_day',
          effectiveFromDateIso: '2026-10-22',
        ),
        TargetRule(
          kcal: 2700,
          proteinG: 150,
          carbsG: 300,
          fatG: 70,
          appliesTo: 'date:2026-10-22',
          effectiveFromDateIso: '2026-10-22',
        ),
      ];
      expect(
        TargetResolver.resolveRule(
          rules: rules,
          date: DateTime(2026, 10, 21),
          isTrainingDay: true,
        )?.kcal,
        2000,
      );
      expect(
        TargetResolver.resolveRule(
          rules: rules,
          date: DateTime(2026, 10, 22),
          isTrainingDay: true,
        )?.kcal,
        2700,
      );
      expect(
        TargetResolver.resolveRule(
          rules: rules,
          date: DateTime(2026, 10, 23),
          isTrainingDay: true,
        )?.kcal,
        2500,
      );
    },
  );

  test(
    'a future phase does not change the currently displayed diet plan',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          clockProvider.overrideWithValue(clock),
        ],
      );
      addTearDown(container.dispose);
      final applier = container.read(activeDietPlanProvider.notifier);
      await applier.setPlan(
        phase: DietPhase.maintain,
        weeklyRateKg: 0,
        kcalDelta: 0,
        paceLabel: 'Maintain',
      );
      await applier.setPlan(
        phase: DietPhase.cut,
        weeklyRateKg: 0.5,
        kcalDelta: -400,
        paceLabel: 'Cut',
        effectiveFrom: DateTime(2026, 10, 22),
      );
      expect(container.read(activeDietPlanProvider).phase, DietPhase.maintain);
      expect(container.read(activeDietPlanProvider).kcalDelta, 0);
    },
  );
  test(
    'deleting a dated target keeps a tombstone for another device',
    () async {
      await repo.upsertTarget(
        label: 'Today',
        appliesTo: 'global',
        kcal: 2400,
        proteinG: 160,
        carbsG: 275,
        fatG: 80,
        effectiveFrom: DateTime(2026, 10, 21),
      );
      final target = await db.select(db.nutritionTargets).getSingle();
      await repo.deleteTarget(target.id);
      expect(await repo.watchTargets().first, isEmpty);
      expect(
        (await db.select(db.nutritionTargets).getSingle()).deletedAt,
        isNotNull,
      );
    },
  );
}
