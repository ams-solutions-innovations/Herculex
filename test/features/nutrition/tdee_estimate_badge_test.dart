import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/design_system/components/hx_pill.dart';
import 'package:herculex/design_system/theme/app_theme.dart';
import 'package:herculex/features/nutrition/application/nutrition_providers.dart';
import 'package:herculex/features/nutrition/application/tdee_display_providers.dart';
import 'package:herculex/features/nutrition/application/tdee_providers.dart';
import 'package:herculex/features/nutrition/domain/diet_phase.dart';
import 'package:herculex/features/nutrition/domain/tdee_estimate.dart';
import 'package:herculex/features/nutrition/presentation/views/nutrition_targets_view.dart';
import 'package:herculex/features/nutrition/presentation/widgets/tdee_estimate_badge.dart';
import 'package:herculex/features/profile/domain/profile.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SharedPreferences prefs;

  const profile = Profile(
    name: 'Test Athlete',
    weightKg: 80,
    heightCm: 180,
    ageYears: 28,
    sex: BiologicalSex.male,
    activityLevel: ActivityLevel.active,
    goal: FitnessGoal.muscleGain,
  );

  // Missing weight: no estimate is possible.
  const noWeightProfile = Profile(
    name: 'No Weight',
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

  TdeeEstimateResult result(
    TdeeMethod method,
    TdeeConfidence confidence, {
    bool qualified = true,
  }) => TdeeEstimateResult(
    kcal: 2650,
    method: method,
    confidence: confidence,
    windowDays: 28,
    observedQualified: qualified,
    inputs: const {'span_days': 27, 'logged_days': 28},
    estimatedAt: DateTime(2026, 9, 28, 8),
  );

  List<Override> overrides({
    Stream<Profile?>? profileStream,
    required Stream<TdeeEstimateResult?> latest,
  }) => [
    sharedPreferencesProvider.overrideWithValue(prefs),
    profileProvider.overrideWith(
      (ref) => profileStream ?? Stream.value(profile),
    ),
    nutritionTargetsProvider.overrideWith((ref) => Stream.value([])),
    savedTargetForTodayProvider.overrideWith((ref) async => null),
    latestTdeeEstimateProvider.overrideWith((ref) => latest),
  ];

  Widget host(
    List<Override> o, {
    TextEditingController? controller,
    double? textScale,
  }) => ProviderScope(
    overrides: o,
    child: MaterialApp(
      theme: AppTheme.darkTheme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale ?? 1.0)),
        child: child!,
      ),
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (controller != null) TextField(controller: controller),
              const TdeeEstimateBadge(),
            ],
          ),
        ),
      ),
    ),
  );

  Future<void> pumpBadge(
    WidgetTester tester,
    TdeeEstimateResult? estimate, {
    double? textScale,
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      host(overrides(latest: Stream.value(estimate)), textScale: textScale),
    );
    await tester.pumpAndSettle();
  }

  group('labels', () {
    final cases = <String, (TdeeEstimateResult, String)>{
      'observed high': (
        result(TdeeMethod.observed, TdeeConfidence.high),
        'Measured · High confidence',
      ),
      'observed medium': (
        result(TdeeMethod.observed, TdeeConfidence.medium),
        'Measured · Medium confidence',
      ),
      'held': (
        result(TdeeMethod.observed, TdeeConfidence.medium, qualified: false),
        'Measured · Aging estimate',
      ),
      'classifier medium': (
        result(TdeeMethod.classifier, TdeeConfidence.medium),
        'Classified · Medium confidence',
      ),
      'classifier low': (
        result(TdeeMethod.classifier, TdeeConfidence.low),
        'Classified · Low confidence',
      ),
      'classifier high is clamped to medium': (
        result(TdeeMethod.classifier, TdeeConfidence.high),
        'Classified · Medium confidence',
      ),
      'stored cold start': (
        result(TdeeMethod.coldStart, TdeeConfidence.low),
        'Calibrating — using onboarding estimate',
      ),
    };
    for (final entry in cases.entries) {
      testWidgets(entry.key, (tester) async {
        await pumpBadge(tester, entry.value.$1);
        expect(find.text(entry.value.$2), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  testWidgets('cold start (no row) shows the calibrating badge', (
    tester,
  ) async {
    await pumpBadge(tester, null);
    expect(
      find.text('Calibrating — using onboarding estimate'),
      findsOneWidget,
    );
  });

  testWidgets('a stream error shows the same calibrating badge', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      host(overrides(latest: Stream<TdeeEstimateResult?>.error('boom'))),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Calibrating — using onboarding estimate'),
      findsOneWidget,
    );
    expect(find.textContaining('boom'), findsNothing);
    expect(find.textContaining('rror'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'reserves height 44 while the estimate is loading, then fades in',
    (tester) async {
      final controller = StreamController<TdeeEstimateResult?>();
      addTearDown(controller.close);
      await tester.pumpWidget(host(overrides(latest: controller.stream)));
      await tester.pump();

      expect(tester.getSize(find.byType(TdeeEstimateBadge)).height, 44);
      expect(find.byType(Text), findsNothing);

      controller.add(result(TdeeMethod.observed, TdeeConfidence.high));
      await tester.pumpAndSettle();
      expect(find.text('Measured · High confidence'), findsOneWidget);
    },
  );

  testWidgets('reserves height 44 while the profile is loading', (
    tester,
  ) async {
    final profileGate = Completer<Profile?>();
    await tester.pumpWidget(
      host(
        overrides(
          profileStream: Stream.fromFuture(profileGate.future),
          latest: Stream.value(null),
        ),
      ),
    );
    await tester.pump();

    expect(tester.getSize(find.byType(TdeeEstimateBadge)).height, 44);
    expect(find.byType(Text), findsNothing);

    profileGate.complete(profile);
    await tester.pumpAndSettle();
    expect(
      find.text('Calibrating — using onboarding estimate'),
      findsOneWidget,
    );
  });

  testWidgets('renders nothing when the profile cannot produce an estimate', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      host(
        overrides(
          profileStream: Stream.value(noWeightProfile),
          latest: Stream.value(null),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(TdeeEstimateBadge)), Size.zero);
    expect(find.byType(Text), findsNothing);
    expect(find.byType(HxPill), findsNothing);
    expect(find.bySemanticsLabel(RegExp('Maintenance estimate')), findsNothing);
    handle.dispose();
  });

  testWidgets('hit target is at least 44 logical px tall', (tester) async {
    await pumpBadge(tester, result(TdeeMethod.observed, TdeeConfidence.high));
    final target = find.byKey(const ValueKey('tdee_badge_target'));
    expect(target, findsOneWidget);
    expect(tester.getSize(target).height, greaterThanOrEqualTo(44));
    // Tapping the padding above the visible pill still opens the sheet.
    final rect = tester.getRect(target);
    await tester.tapAt(Offset(rect.left + 4, rect.top + 2));
    await tester.pumpAndSettle();
    expect(find.text('Maintenance estimate'), findsOneWidget);
  });

  testWidgets('tapping the badge opens the detail sheet', (tester) async {
    await pumpBadge(tester, result(TdeeMethod.observed, TdeeConfidence.high));
    expect(find.text('Maintenance estimate'), findsNothing);
    await tester.tap(find.text('Measured · High confidence'));
    await tester.pumpAndSettle();
    expect(find.text('Maintenance estimate'), findsOneWidget);
  });

  testWidgets('typing into another field does not change the badge', (
    tester,
  ) async {
    final controller = TextEditingController(text: '2650');
    addTearDown(controller.dispose);
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      host(
        overrides(
          latest: Stream.value(
            result(TdeeMethod.classifier, TdeeConfidence.medium),
          ),
        ),
        controller: controller,
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '3100');
    await tester.pumpAndSettle();
    expect(find.text('Classified · Medium confidence'), findsOneWidget);
  });

  testWidgets('semantics: button with the full description', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpBadge(tester, result(TdeeMethod.observed, TdeeConfidence.high));
    final node = tester.getSemantics(
      find.bySemanticsLabel(
        'Maintenance estimate: Measured, High confidence. '
        'Double tap for details.',
      ),
    );
    expect(node.flagsCollection.isButton, isTrue);
    handle.dispose();
  });

  testWidgets('semantics for the calibrating state', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpBadge(tester, null);
    expect(
      find.bySemanticsLabel(
        'Maintenance estimate: Calibrating, using onboarding estimate. '
        'Double tap for details.',
      ),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('a state change swaps the label through an AnimatedSwitcher', (
    tester,
  ) async {
    final controller = StreamController<TdeeEstimateResult?>();
    addTearDown(controller.close);
    await tester.pumpWidget(host(overrides(latest: controller.stream)));
    controller.add(result(TdeeMethod.observed, TdeeConfidence.high));
    await tester.pumpAndSettle();
    expect(find.text('Measured · High confidence'), findsOneWidget);
    expect(find.byType(AnimatedSwitcher), findsWidgets);

    controller.add(result(TdeeMethod.classifier, TdeeConfidence.low));
    await tester.pumpAndSettle();
    expect(find.text('Measured · High confidence'), findsNothing);
    expect(find.text('Classified · Low confidence'), findsOneWidget);
  });

  testWidgets('wraps at 2x text scale without overflow', (tester) async {
    await pumpBadge(tester, null, textScale: 2.0);
    expect(tester.takeException(), isNull);
    expect(
      find.text('Calibrating — using onboarding estimate'),
      findsOneWidget,
    );
  });

  testWidgets('sits once in TargetEditorView between the field and subtitle', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    final container = ProviderContainer(
      overrides: overrides(
        latest: Stream.value(result(TdeeMethod.observed, TdeeConfidence.high)),
      ),
    );
    addTearDown(container.dispose);
    await container.read(profileProvider.future);
    await container.read(latestTdeeEstimateProvider.future);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: const Scaffold(body: TargetEditorView()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TdeeEstimateBadge), findsOneWidget);
    final maintenanceField = find.byWidgetPredicate(
      (w) => w is TextField && w.controller?.text == '2650',
    );
    expect(maintenanceField, findsOneWidget);
    final subtitle = find.byWidgetPredicate(
      (w) => w is Text && DietPhase.values.any((p) => p.subtitle == w.data),
    );
    expect(subtitle, findsOneWidget);

    final badge = find.byType(TdeeEstimateBadge);
    expect(
      tester.getTopLeft(badge).dy,
      greaterThanOrEqualTo(tester.getBottomLeft(maintenanceField).dy),
    );
    expect(
      tester.getBottomLeft(badge).dy,
      lessThanOrEqualTo(tester.getTopLeft(subtitle).dy),
    );
  });
}
