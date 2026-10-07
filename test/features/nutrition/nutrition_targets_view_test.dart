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

  Finder phaseRow(String label) =>
      find.descendant(of: find.byType(ListTile), matching: find.text(label));

  Future<void> openPhasePicker(WidgetTester tester) async {
    await tester.tap(find.byType(HxPickerPill).first);
    await tester.pumpAndSettle();
  }

  Future<void> closeSheet(WidgetTester tester) async {
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
  }

  Future<void> pickPhase(WidgetTester tester, String label) async {
    await openPhasePicker(tester);
    await tester.tap(phaseRow(label));
    await tester.pumpAndSettle();
  }

  Future<void> pickPace(WidgetTester tester, String label) async {
    await tester.tap(find.byType(HxPickerPill).at(1));
    await tester.pumpAndSettle();
    await tester.tap(phaseRow(label));
    await tester.pumpAndSettle();
  }

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

      expect(find.text('Goals & nutrition'), findsOneWidget);
      expect(find.byType(HxBackButton), findsOneWidget);
      expect(find.text('Quick calorie and phase plan'), findsOneWidget);
      expect(find.byType(HxPickerPill), findsNWidgets(2));
      await openPhasePicker(tester);
      for (final l in ['Cut', 'Bulk', 'Lean bulk', 'Maintenance', 'Recomp']) {
        expect(phaseRow(l), findsOneWidget, reason: l);
      }
      await closeSheet(tester);
      expect(find.text('Daily targets'), findsOneWidget);
      expect(find.text('Active schedule'), findsOneWidget);
      expect(find.text('Carb cycling'), findsOneWidget);
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

      // Pick Lean bulk
      await pickPhase(tester, 'Lean bulk');

      expect(find.text('Clean (+150 kcal)'), findsOneWidget);
      expect(find.textContaining('Apply: Lean bulk'), findsOneWidget);

      // Pick Bulk
      await pickPhase(tester, 'Bulk');

      expect(find.text('0.50 kg/wk (standard)'), findsOneWidget);
      expect(find.textContaining('Apply: Bulk'), findsOneWidget);
    },
  );

  testWidgets(
    'DailyTargetsView renders Fasting-style header and add target button',
    (tester) async {
      await tester.pumpWidget(testApp(const DailyTargetsView()));
      await tester.pumpAndSettle();

      expect(find.text('Daily targets'), findsOneWidget);
      expect(find.byType(HxBackButton), findsOneWidget);
      expect(find.text('ADD / EDIT TARGET'), findsOneWidget);
    },
  );

  testWidgets(
    'TargetEditorView pre-fills baseline values and handles phase changes',
    (tester) async {
      await tester.pumpWidget(testApp(const TargetEditorView()));
      await tester.pumpAndSettle();

      expect(find.text('Add target'), findsOneWidget);
      expect(find.byType(HxBackButton), findsOneWidget);
      expect(find.text('NUTRITION PHASE'), findsOneWidget);
      expect(find.text('APPLIES TO'), findsOneWidget);
      expect(find.text('CALORIES'), findsOneWidget);
      expect(find.text('MACRO INPUT MODE'), findsOneWidget);

      // Tapping 'Cut' chip changes phase and updates save label
      await tester.tap(find.text('Cut'));
      await tester.pumpAndSettle();

      expect(find.text('SAVE: CUT'), findsOneWidget);

      // Tapping 'Maingain' chip changes phase and updates save label
      await tester.tap(find.text('Lean bulk'));
      await tester.pumpAndSettle();

      expect(find.text('SAVE: LEAN BULK'), findsOneWidget);

      // Tapping 'Bulk' chip changes phase and updates save label
      await tester.tap(find.text('Bulk'));
      await tester.pumpAndSettle();

      expect(find.text('SAVE: BULK'), findsOneWidget);
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

    expect(find.text('Baseline: 3000 kcal (TDEE)'), findsOneWidget);
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

    /// Whether [label] can be picked: opens the phase sheet, reads the row's
    /// onTap, and closes the sheet again.
    Future<bool> phaseEnabled(WidgetTester tester, String label) async {
      await openPhasePicker(tester);
      final tile = tester.widget<ListTile>(
        find.ancestor(of: find.text(label), matching: find.byType(ListTile)),
      );
      final enabled = tile.onTap != null;
      await closeSheet(tester);
      return enabled;
    }

    testWidgets('quick planner disables Cut and Bulk for under 18', (
      tester,
    ) async {
      bigView(tester);
      await tester.pumpWidget(
        testApp(const NutritionTargetsView(), overrides: as(minor)),
      );
      await tester.pumpAndSettle();

      expect(await phaseEnabled(tester, 'Cut'), isFalse);
      expect(await phaseEnabled(tester, 'Bulk'), isFalse);
      expect(await phaseEnabled(tester, 'Maintenance'), isTrue);
      expect(await phaseEnabled(tester, 'Recomp'), isTrue);
      expect(await phaseEnabled(tester, 'Lean bulk'), isTrue);
      expect(
        find.textContaining('Cut and Bulk are not available under 18'),
        findsOneWidget,
      );
      expect(find.text('Add age in profile'), findsNothing);
      expect(find.textContaining('Apply: Cut'), findsNothing);
    });

    testWidgets('quick planner shows Add age action when age is missing', (
      tester,
    ) async {
      bigView(tester);
      await tester.pumpWidget(
        testApp(const NutritionTargetsView(), overrides: as(noAge)),
      );
      await tester.pumpAndSettle();

      expect(await phaseEnabled(tester, 'Cut'), isFalse);
      expect(await phaseEnabled(tester, 'Bulk'), isFalse);
      expect(find.text('Add age in profile'), findsOneWidget);
    });

    testWidgets('adult keeps every chip enabled and no notice', (tester) async {
      bigView(tester);
      await tester.pumpWidget(testApp(const NutritionTargetsView()));
      await tester.pumpAndSettle();

      for (final l in ['Cut', 'Bulk', 'Maintenance', 'Recomp', 'Lean bulk']) {
        expect(await phaseEnabled(tester, l), isTrue, reason: l);
      }
      expect(find.textContaining('are not available under 18'), findsNothing);
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
      expect(find.textContaining('Apply: Recomp'), findsOneWidget);
      expect(find.textContaining('Apply: Cut'), findsNothing);
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
      expect(find.textContaining('Apply: Cut'), findsOneWidget);
    });

    testWidgets('maingain surplus is capped at +150 for under 18', (
      tester,
    ) async {
      bigView(tester);
      await tester.pumpWidget(
        testApp(const NutritionTargetsView(), overrides: as(minor)),
      );
      await tester.pumpAndSettle();

      await pickPhase(tester, 'Lean bulk');
      await pickPace(tester, 'Progressive (+250 kcal)');

      expect(
        find.textContaining('Apply: Lean bulk (3150 kcal)'),
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
      expect(chip('Cut').onSelected, isNull);
      expect(chip('Bulk').onSelected, isNull);
      expect(chip('Maintenance').onSelected, isNotNull);
      expect(chip('Recomp').onSelected, isNotNull);
      expect(chip('Lean bulk').onSelected, isNotNull);
      expect(
        find.textContaining('Cut and Bulk are not available under 18'),
        findsOneWidget,
      );

      await tester.tap(find.text('Cut'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.text('SAVE: CUT'), findsNothing);

      await tester.tap(find.text('Lean bulk'));
      await tester.pumpAndSettle();
      expect(find.text('SAVE: LEAN BULK'), findsOneWidget);
    });

    testWidgets('TargetEditorView shows Add age action for null age', (
      tester,
    ) async {
      await tester.pumpWidget(
        testApp(const TargetEditorView(), overrides: as(noAge)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Add age in profile'), findsOneWidget);
      final chip = tester.widget<ChoiceChip>(
        find.ancestor(of: find.text('Bulk'), matching: find.byType(ChoiceChip)),
      );
      expect(chip.onSelected, isNull);
    });
  });
}
