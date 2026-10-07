import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/features/nutrition/application/nutrition_providers.dart';
import 'package:herculex/features/nutrition/domain/daily_totals.dart';
import 'package:herculex/features/profile/domain/profile.dart';
import 'package:intl/intl.dart';

void main() {
  test(
    'averageWeeklyMacroProvider excludes today and calculates past 7 completed days',
    () async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      final historyMap = <String, DailyTotals>{};

      // Today: 500 kcal (breakfast only)
      final todayIso = DateFormat('yyyy-MM-dd').format(today);
      historyMap[todayIso] = const DailyTotals(
        kcal: 500,
        proteinG: 30,
        carbsG: 50,
        fatG: 10,
      );

      // Days 1 through 7 before today: 2500 kcal each day
      for (int i = 1; i <= 7; i++) {
        final d = today.subtract(Duration(days: i));
        final iso = DateFormat('yyyy-MM-dd').format(d);
        historyMap[iso] = const DailyTotals(
          kcal: 2500,
          proteinG: 150,
          carbsG: 250,
          fatG: 70,
        );
      }

      final container = ProviderContainer(
        overrides: [
          nutritionHistoryProvider.overrideWith(
            (ref) => Stream.value(historyMap),
          ),
        ],
      );
      addTearDown(container.dispose);

      // Await stream emission
      await container.read(nutritionHistoryProvider.future);

      // Read the provider
      final avgKcal = container.read(averageWeeklyCaloriesProvider);
      final avgProtein = container.read(averageWeeklyMacroProvider('protein'));

      // Should be exactly 2500 kcal and 150g protein (today's 500 kcal is excluded)
      expect(avgKcal, equals(2500.0));
      expect(avgProtein, equals(150.0));
    },
  );

  test(
    'Profile supports targetWeightKg and serializes/deserializes properly',
    () {
      const profile = Profile(
        name: 'Tester',
        goal: FitnessGoal.weightLoss,
        activityLevel: ActivityLevel.active,
        weightKg: 85.0,
        targetWeightKg: 78.0,
        heightCm: 182.0,
      );

      final json = profile.toJson();
      expect(json['targetWeightKg'], equals(78.0));

      final decoded = Profile.fromJson(json);
      expect(decoded.targetWeightKg, equals(78.0));

      final copy = profile.copyWith(targetWeightKg: 75.0);
      expect(copy.targetWeightKg, equals(75.0));
    },
  );
}
