import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/design_system/components/components.dart';
import 'package:herculex/design_system/theme/app_theme.dart';
import 'package:herculex/features/dashboard/application/dashboard_providers.dart';
import 'package:herculex/features/dashboard/presentation/widgets/remaining_calories_card.dart';
import 'package:herculex/features/nutrition/application/nutrition_providers.dart';
import 'package:herculex/features/nutrition/application/tdee_providers.dart';
import 'package:herculex/features/nutrition/domain/diet_phase.dart';
import 'package:herculex/features/nutrition/domain/macro_targets.dart';
import 'package:herculex/features/nutrition/domain/tdee_estimate.dart';
import 'package:herculex/features/nutrition/presentation/views/nutrition_targets_view.dart';
import 'package:herculex/features/profile/domain/profile.dart';
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

  Finder fieldWith(String text) => find.byWidgetPredicate(
    (w) => w is TextField && w.controller?.text == text,
  );

  final observed2650 = TdeeEstimateResult(
    kcal: 2650,
    method: TdeeMethod.observed,
    confidence: TdeeConfidence.medium,
    windowDays: 28,
    observedQualified: true,
    inputs: const {},
    estimatedAt: DateTime(2026, 9, 1, 8),
  );

  List<Override> baseOverrides({TdeeEstimateResult? estimate}) => [
    sharedPreferencesProvider.overrideWithValue(prefs),
    profileProvider.overrideWith((ref) => Stream.value(testProfile)),
    nutritionTargetsProvider.overrideWith((ref) => Stream.value([])),
    latestTdeeEstimateProvider.overrideWith((ref) => Stream.value(estimate)),
  ];

  Widget testApp(
    Widget child, {
    List<Override> overrides = const [],
    ProviderContainer? container,
  }) {
    final app = MaterialApp(
      theme: AppTheme.darkTheme,
      home: Scaffold(body: child),
    );
    if (container != null) {
      return UncontrolledProviderScope(container: container, child: app);
    }
    return ProviderScope(
      overrides: [...baseOverrides(), ...overrides],
      child: app,
    );
  }

  /// Builds a container whose profile and estimate streams have already
  /// emitted, because TargetEditorView.initState reads them once.
  Future<ProviderContainer> warmContainer({
    TdeeEstimateResult? estimate,
  }) async {
    final container = ProviderContainer(
      overrides: baseOverrides(estimate: estimate),
    );
    addTearDown(container.dispose);
    await container.read(profileProvider.future);
    await container.read(latestTdeeEstimateProvider.future);
    return container;
  }

  testWidgets(
    'NutritionTargetsView renders Fasting-style header, quick planner and hub tiles',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(testApp(const NutritionTargetsView()));
      await tester.pumpAndSettle();

      expect(find.text('Cilji in prehrana'), findsOneWidget);
      expect(find.byType(HxBackButton), findsOneWidget);
      expect(find.text('Hitri načrt kalorij in faz'), findsOneWidget);
      expect(find.text('Redukcija'), findsAtLeastNWidgets(1));
      expect(find.text('Masa'), findsAtLeastNWidgets(1));
      expect(find.text('Čista rast'), findsAtLeastNWidgets(1));
      expect(find.text('Vzdrževanje'), findsAtLeastNWidgets(1));
      expect(find.text('Dnevni cilji'), findsOneWidget);
      expect(find.text('Aktiven razpored'), findsOneWidget);
      expect(find.text('Ciklanje ogljikovih hidratov'), findsOneWidget);
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
      await tester.tap(find.text('Čista rast').first);
      await tester.pumpAndSettle();

      expect(find.text('Čisto (+150 kcal)'), findsOneWidget);
      expect(find.textContaining('Uporabi: Čista rast'), findsOneWidget);

      // Tap Bulk
      await tester.tap(find.text('Masa').first);
      await tester.pumpAndSettle();

      expect(find.text('0,50 kg/ted (standardno)'), findsOneWidget);
      expect(find.textContaining('Uporabi: Masa'), findsOneWidget);
    },
  );

  testWidgets(
    'DailyTargetsView renders Fasting-style header and add target button',
    (tester) async {
      await tester.pumpWidget(testApp(const DailyTargetsView()));
      await tester.pumpAndSettle();

      expect(find.text('Dnevni cilji'), findsOneWidget);
      expect(find.byType(HxBackButton), findsOneWidget);
      expect(find.text('DODAJ / UREDI CILJ'), findsOneWidget);
    },
  );

  testWidgets(
    'TargetEditorView pre-fills baseline values and handles phase changes',
    (tester) async {
      await tester.pumpWidget(testApp(const TargetEditorView()));
      await tester.pumpAndSettle();

      expect(find.text('Dodaj cilj'), findsOneWidget);
      expect(find.byType(HxBackButton), findsOneWidget);
      expect(find.text('PREHRANSKA FAZA'), findsOneWidget);
      expect(find.text('VELJA ZA'), findsOneWidget);
      expect(find.text('KALORIJE'), findsOneWidget);
      expect(find.text('NAČIN VNOSA MAKROHRANIL'), findsOneWidget);

      // Tapping 'Cut' chip changes phase and updates save label
      await tester.tap(find.text('Redukcija'));
      await tester.pumpAndSettle();

      expect(find.text('SHRANI: REDUKCIJA'), findsOneWidget);

      // Tapping 'Maingain' chip changes phase and updates save label
      await tester.tap(find.text('Čista rast'));
      await tester.pumpAndSettle();

      expect(find.text('SHRANI: ČISTA RAST'), findsOneWidget);

      // Tapping 'Bulk' chip changes phase and updates save label
      await tester.tap(find.text('Masa'));
      await tester.pumpAndSettle();

      expect(find.text('SHRANI: MASA'), findsOneWidget);
    },
  );

  testWidgets('TargetEditorView maintenance field shows observed estimate', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    final container = await warmContainer(estimate: observed2650);
    await tester.pumpWidget(
      testApp(const TargetEditorView(), container: container),
    );
    await tester.pumpAndSettle();

    // Pure maintenance, not the goal-adjusted fromProfile figure.
    expect(fieldWith('2650'), findsOneWidget);
    // Daily calories stay goal-adjusted: 2650 + 300 (muscle gain).
    expect(fieldWith('2950'), findsOneWidget);
    expect(
      container.read(baselineTargetsProvider)!.kcal,
      MacroTargets.fromMaintenance(testProfile, 2650)!.kcal,
    );
  });

  testWidgets(
    'TargetEditorView cold start seeds maintenance from the profile',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      final container = await warmContainer();
      await tester.pumpWidget(
        testApp(const TargetEditorView(), container: container),
      );
      await tester.pumpAndSettle();

      final seed = MacroTargets.seedMaintenanceKcal(testProfile)!.round();
      expect(seed, 2775);
      expect(fieldWith('$seed'), findsOneWidget);
      expect(
        fieldWith(MacroTargets.fromProfile(testProfile)!.kcal.toString()),
        findsOneWidget,
      );
    },
  );

  testWidgets('TargetEditorView editing a saved target still shows estimate', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    final container = await warmContainer(estimate: observed2650);
    await tester.pumpWidget(
      testApp(
        const TargetEditorView(
          initialTarget: NutritionTargetData(
            id: 1,
            label: 'Custom',
            kcal: 2100,
            proteinG: 180,
            carbsG: 200,
            fatG: 60,
            appliesTo: 'all',
          ),
        ),
        container: container,
      ),
    );
    await tester.pumpAndSettle();

    expect(fieldWith('2650'), findsOneWidget);
    expect(fieldWith('2100'), findsOneWidget);
  });

  testWidgets('Quick phase planner baselines on pure maintenance', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      testApp(
        const NutritionTargetsView(),
        overrides: [maintenanceKcalProvider.overrideWithValue(3000)],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Izhodišče: 3000 kcal (TDEE)'), findsOneWidget);
  });

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

  group('PHYS-04 phase eligibility gates', () {
    const minor = Profile(
      name: 'Minor',
      weightKg: 70,
      heightCm: 175,
      ageYears: 17,
      sex: BiologicalSex.male,
      activityLevel: ActivityLevel.active,
      goal: FitnessGoal.muscleGain,
    );
    const noAge = Profile(
      name: 'NoAge',
      weightKg: 70,
      heightCm: 175,
      sex: BiologicalSex.male,
      activityLevel: ActivityLevel.active,
      goal: FitnessGoal.muscleGain,
    );

    List<Override> as(Profile p) => [
      profileProvider.overrideWith((ref) => Stream.value(p)),
      maintenanceKcalProvider.overrideWithValue(3000),
    ];

    void bigView(WidgetTester tester) {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
    }

    VoidCallback? chipTap(WidgetTester tester, String label) {
      final ink = find.ancestor(
        of: find.text(label).first,
        matching: find.byType(InkWell),
      );
      return tester.widget<InkWell>(ink.first).onTap;
    }

    testWidgets('quick planner disables Cut and Bulk for under 18', (
      tester,
    ) async {
      bigView(tester);
      await tester.pumpWidget(
        testApp(const NutritionTargetsView(), overrides: as(minor)),
      );
      await tester.pumpAndSettle();

      expect(chipTap(tester, 'Redukcija'), isNull);
      expect(chipTap(tester, 'Masa'), isNull);
      expect(chipTap(tester, 'Vzdrževanje'), isNotNull);
      expect(chipTap(tester, 'Rekompozicija'), isNotNull);
      expect(chipTap(tester, 'Čista rast'), isNotNull);
      expect(
        find.textContaining('Redukcija in Masa nista na voljo pod 18 let'),
        findsOneWidget,
      );
      expect(find.text('Dodaj starost v profilu'), findsNothing);

      await tester.tap(find.text('Redukcija').first);
      await tester.pumpAndSettle();
      expect(find.textContaining('Uporabi: Redukcija'), findsNothing);
    });

    testWidgets('quick planner shows Add age action when age is missing', (
      tester,
    ) async {
      bigView(tester);
      await tester.pumpWidget(
        testApp(const NutritionTargetsView(), overrides: as(noAge)),
      );
      await tester.pumpAndSettle();

      expect(chipTap(tester, 'Redukcija'), isNull);
      expect(chipTap(tester, 'Masa'), isNull);
      expect(find.text('Dodaj starost v profilu'), findsOneWidget);
    });

    testWidgets('adult keeps every chip enabled and no notice', (tester) async {
      bigView(tester);
      await tester.pumpWidget(testApp(const NutritionTargetsView()));
      await tester.pumpAndSettle();

      for (final l in [
        'Redukcija',
        'Masa',
        'Vzdrževanje',
        'Rekompozicija',
        'Čista rast',
      ]) {
        expect(chipTap(tester, l), isNotNull, reason: l);
      }
      expect(find.textContaining('nista na voljo pod 18 let'), findsNothing);
    });

    testWidgets('deep-link Cut is coerced for under 18', (tester) async {
      bigView(tester);
      await tester.pumpWidget(
        testApp(
          const NutritionTargetsView(initialPhase: DietPhase.cut),
          overrides: as(minor),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Uporabi: Rekompozicija'), findsOneWidget);
      expect(find.textContaining('Uporabi: Redukcija'), findsNothing);
    });

    testWidgets('deep-link Cut is kept for an adult', (tester) async {
      bigView(tester);
      await tester.pumpWidget(
        testApp(
          const NutritionTargetsView(initialPhase: DietPhase.cut),
          overrides: [maintenanceKcalProvider.overrideWithValue(3000)],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Uporabi: Redukcija'), findsOneWidget);
    });

    testWidgets('maingain surplus is capped at +150 for under 18', (
      tester,
    ) async {
      bigView(tester);
      await tester.pumpWidget(
        testApp(const NutritionTargetsView(), overrides: as(minor)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Čista rast').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Progresivno (+250 kcal)'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Uporabi: Čista rast (3150 kcal)'),
        findsOneWidget,
      );
    });

    testWidgets('TargetEditorView disables Cut and Bulk for under 18', (
      tester,
    ) async {
      await tester.pumpWidget(
        testApp(const TargetEditorView(), overrides: as(minor)),
      );
      await tester.pumpAndSettle();

      ChoiceChip chip(String l) => tester.widget<ChoiceChip>(
        find.ancestor(of: find.text(l), matching: find.byType(ChoiceChip)),
      );
      expect(chip('Redukcija').onSelected, isNull);
      expect(chip('Masa').onSelected, isNull);
      expect(chip('Vzdrževanje').onSelected, isNotNull);
      expect(chip('Rekompozicija').onSelected, isNotNull);
      expect(chip('Čista rast').onSelected, isNotNull);
      expect(
        find.textContaining('Redukcija in Masa nista na voljo pod 18 let'),
        findsOneWidget,
      );

      await tester.tap(find.text('Redukcija'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.text('SHRANI: REDUKCIJA'), findsNothing);

      await tester.tap(find.text('Čista rast'));
      await tester.pumpAndSettle();
      expect(find.text('SHRANI: ČISTA RAST'), findsOneWidget);
    });

    testWidgets('TargetEditorView shows Add age action for null age', (
      tester,
    ) async {
      await tester.pumpWidget(
        testApp(const TargetEditorView(), overrides: as(noAge)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Dodaj starost v profilu'), findsOneWidget);
      final chip = tester.widget<ChoiceChip>(
        find.ancestor(of: find.text('Masa'), matching: find.byType(ChoiceChip)),
      );
      expect(chip.onSelected, isNull);
    });
  });
}
