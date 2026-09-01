import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/features/dashboard/presentation/dashboard_providers.dart';
import 'package:herculex/features/dashboard/presentation/widgets/remaining_calories_card.dart';
import 'package:herculex/features/nutrition/presentation/nutrition_providers.dart';
import 'package:herculex/features/nutrition/presentation/nutrition_targets_view.dart';
import 'package:herculex/features/profile/domain/profile.dart';
import 'package:herculex/theme/app_theme.dart';
import 'package:herculex/ui/ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SharedPreferences prefs;

  const testProfile = Profile(
    name: 'Test Athlete',
    weightKg: 80,
    heightCm: 180,
    ageYears: 28,
    sex: BiologicalSex.male,
    activityLevel: ActivityLevel.active,
    goal: FitnessGoal.muscleGain,
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  Widget testApp(Widget child, {List<Override> overrides = const []}) {
    return ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        profileProvider.overrideWith((ref) => Stream.value(testProfile)),
        nutritionTargetsProvider.overrideWith((ref) => Stream.value([])),
        ...overrides,
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(body: child),
      ),
    );
  }

  testWidgets(
    'NutritionTargetsView renders Fasting-style header, quick planner and hub tiles',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(testApp(const NutritionTargetsView()));
      await tester.pumpAndSettle();

      expect(find.text('Targets & Dieting'), findsOneWidget);
      expect(find.byType(HxBackButton), findsOneWidget);
      expect(find.text('Quick Calories & Phase Planner'), findsOneWidget);
      expect(find.text('Cut'), findsAtLeastNWidgets(1));
      expect(find.text('Bulk'), findsAtLeastNWidgets(1));
      expect(find.text('Maingain'), findsAtLeastNWidgets(1));
      expect(find.text('Maintain'), findsAtLeastNWidgets(1));
      expect(find.text('Daily Targets'), findsOneWidget);
      expect(find.text('Active Schedule'), findsOneWidget);
      expect(find.text('Carb Cycle'), findsOneWidget);
    },
  );

  testWidgets(
    'NutritionTargetsView switches between Cut, Bulk, Maingain and updates dynamic target',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(testApp(const NutritionTargetsView()));
      await tester.pumpAndSettle();

      // Tap Maingain
      await tester.tap(find.text('Maingain').first);
      await tester.pumpAndSettle();

      expect(find.text('Lean (+150 kcal)'), findsOneWidget);
      expect(find.textContaining('Apply Maingain'), findsOneWidget);

      // Tap Bulk
      await tester.tap(find.text('Bulk').first);
      await tester.pumpAndSettle();

      expect(find.text('0.50 kg/w (Standard)'), findsOneWidget);
      expect(find.textContaining('Apply Bulk'), findsOneWidget);
    },
  );

  testWidgets(
    'DailyTargetsView renders Fasting-style header and add target button',
    (tester) async {
      await tester.pumpWidget(testApp(const DailyTargetsView()));
      await tester.pumpAndSettle();

      expect(find.text('Daily Targets'), findsOneWidget);
      expect(find.byType(HxBackButton), findsOneWidget);
      expect(find.text('ADD / EDIT TARGET'), findsOneWidget);
    },
  );

  testWidgets(
    'TargetEditorView pre-fills baseline values and handles phase changes',
    (tester) async {
      await tester.pumpWidget(testApp(const TargetEditorView()));
      await tester.pumpAndSettle();

      expect(find.text('Add Target'), findsOneWidget);
      expect(find.byType(HxBackButton), findsOneWidget);
      expect(find.text('DIETING PHASE'), findsOneWidget);
      expect(find.text('APPLIES TO'), findsOneWidget);
      expect(find.text('CALORIES'), findsOneWidget);
      expect(find.text('MACRO INPUT METHOD'), findsOneWidget);

      // Tapping 'Cut' chip changes phase and updates save label
      await tester.tap(find.text('Cut'));
      await tester.pumpAndSettle();

      expect(find.text('SAVE CUT'), findsOneWidget);

      // Tapping 'Maingain' chip changes phase and updates save label
      await tester.tap(find.text('Maingain'));
      await tester.pumpAndSettle();

      expect(find.text('SAVE MAINGAIN'), findsOneWidget);

      // Tapping 'Bulk' chip changes phase and updates save label
      await tester.tap(find.text('Bulk'));
      await tester.pumpAndSettle();

      expect(find.text('SAVE BULK'), findsOneWidget);
    },
  );

  testWidgets('RemainingCaloriesCard renders Set a goal when null', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      testApp(
        const RemainingCaloriesCard(),
        overrides: [remainingCaloriesProvider.overrideWithValue(null)],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Remaining'), findsOneWidget);
    expect(find.text('Set a goal'), findsOneWidget);
  });
}
