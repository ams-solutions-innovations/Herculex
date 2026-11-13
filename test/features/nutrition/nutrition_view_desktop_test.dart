import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/nutrition/application/nutrition_providers.dart';
import 'package:herculex/features/nutrition/application/tdee_providers.dart';
import 'package:herculex/features/nutrition/domain/daily_totals.dart';
import 'package:herculex/features/nutrition/presentation/views/nutrition_view.dart';
import 'package:herculex/features/profile/domain/profile.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  Widget buildTestWidget({required Size size}) {
    return ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        dailyTotalsProvider.overrideWith(
          (ref, arg) => Stream.value(DailyTotals.empty),
        ),
        entriesByMealProvider.overrideWith(
          (ref, arg) => const AsyncData(<String, List<FoodEntryData>>{}),
        ),
        profileProvider.overrideWith(
          (ref) => Stream.value(
            const Profile(
              name: 'Athlete',
              weightKg: 80,
              heightCm: 180,
              ageYears: 25,
              activityLevel: ActivityLevel.active,
              goal: FitnessGoal.maintenance,
            ),
          ),
        ),
        tdeeEstimateProvider.overrideWithValue(null),
        averageWeeklyCaloriesProvider.overrideWithValue(2200),
      ],
      child: MaterialApp(
        home: SizedBox(
          width: size.width,
          height: size.height,
          child: const NutritionView(),
        ),
      ),
    );
  }

  testWidgets('NutritionView renders multi-column layout on wide screens', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(buildTestWidget(size: const Size(1280, 900)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('DAILY TARGETS'), findsOneWidget);
    expect(find.text("TODAY'S MEALS"), findsOneWidget);
    expect(find.text('WEEKLY OVERVIEW'), findsOneWidget);
    expect(find.text('ENERGY & METABOLISM'), findsOneWidget);
    expect(find.text('CARB CYCLING'), findsOneWidget);
  });

  testWidgets('NutritionView renders single column vertical flow on mobile', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(buildTestWidget(size: const Size(400, 800)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // On mobile, the desktop side cards are omitted in favor of the clean vertical list
    expect(find.text('WEEKLY OVERVIEW'), findsNothing);
    expect(find.text('ENERGY & METABOLISM'), findsNothing);
    expect(find.text('CARB CYCLING'), findsNothing);
  });
}
