import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/core/utils/clock.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/design_system/theme/app_theme.dart';
import 'package:herculex/features/nutrition/application/nutrition_providers.dart';
import 'package:herculex/features/nutrition/application/tdee_display_providers.dart';
import 'package:herculex/features/nutrition/application/tdee_providers.dart';
import 'package:herculex/features/nutrition/data/nutrition_repository.dart';
import 'package:herculex/features/nutrition/domain/target_resolver.dart';
import 'package:herculex/features/nutrition/domain/tdee_estimate.dart';
import 'package:herculex/features/nutrition/presentation/sheets/tdee_estimate_sheet.dart';

class _FixedClock implements Clock {
  _FixedClock(this._now);
  final DateTime _now;
  @override
  DateTime now() => _now;
}

class _FakeNutritionRepository implements NutritionRepository {
  _FakeNutritionRepository({required this.trained});
  final bool trained;

  @override
  Future<bool> trainedOn(DateTime date) async => trained;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

NutritionTargetData _target(int id, int kcal, String appliesTo) =>
    NutritionTargetData(
      id: id,
      label: 'T$id',
      kcal: kcal,
      proteinG: 150,
      carbsG: 200,
      fatG: 60,
      appliesTo: appliesTo,
    );

void main() {
  group('savedTargetForTodayProvider', () {
    // 2026-09-28 is a Monday.
    Future<TargetRule?> resolve(
      List<NutritionTargetData> rows, {
      bool trained = false,
    }) async {
      final c = ProviderContainer(
        overrides: [
          clockProvider.overrideWithValue(
            _FixedClock(DateTime(2026, 9, 28, 10)),
          ),
          nutritionTargetsProvider.overrideWith((ref) => Stream.value(rows)),
          nutritionRepositoryProvider.overrideWithValue(
            _FakeNutritionRepository(trained: trained),
          ),
        ],
      );
      addTearDown(c.dispose);
      return c.read(savedTargetForTodayProvider.future);
    }

    test(
      'no saved rows means no saved target (no baseline fallback)',
      () async {
        expect(await resolve(const []), isNull);
      },
    );

    test('a global rule is the saved target', () async {
      final rule = await resolve([_target(1, 2400, 'global')]);
      expect(rule?.kcal, 2400);
    });

    test('a more specific weekday rule beats a global one', () async {
      final rule = await resolve([
        _target(1, 2400, 'global'),
        _target(2, 2100, 'weekday:1'),
      ]);
      expect(rule?.kcal, 2100);
    });

    test('a training-day rule only applies on a training day', () async {
      final rows = [_target(1, 2800, 'training_day')];
      expect(await resolve(rows, trained: false), isNull);
      expect((await resolve(rows, trained: true))?.kcal, 2800);
    });
  });

  final now = DateTime(2026, 9, 28, 10);

  TdeeEstimateResult observed({
    Map<String, Object?>? inputs,
    bool qualified = true,
    int kcal = 2310,
    int windowDays = 21,
    TdeeConfidence confidence = TdeeConfidence.high,
  }) => TdeeEstimateResult(
    kcal: kcal,
    method: TdeeMethod.observed,
    confidence: confidence,
    windowDays: windowDays,
    observedQualified: qualified,
    inputs:
        inputs ??
        const {
          'mean_intake_kcal': 2310,
          'logged_days': 12,
          'window_days': 21,
          'span_days': 13,
          'weight_trend_delta_kg': -0.4,
          'weigh_ins': 6,
        },
    estimatedAt: DateTime(2026, 9, 28, 8),
  );

  TdeeEstimateResult classifier(Map<String, Object?> extra) =>
      TdeeEstimateResult(
        kcal: 2650,
        method: TdeeMethod.classifier,
        confidence: TdeeConfidence.medium,
        windowDays: 14,
        observedQualified: false,
        inputs: {
          'avg_steps': 9200,
          'step_days': 12,
          'workouts_per_week': 3,
          'activity_factor': 1.55,
          ...extra,
        },
        estimatedAt: DateTime(2026, 9, 27, 8),
      );

  final calibrating = TdeeEstimateResult(
    kcal: 2775,
    method: TdeeMethod.coldStart,
    confidence: TdeeConfidence.low,
    windowDays: 0,
    observedQualified: false,
    inputs: const {
      'onboarding_level': 'Lightly Active',
      'activity_factor': 1.375,
    },
    estimatedAt: DateTime(2026, 9, 28, 8),
  );

  const saved2400 = TargetRule(
    kcal: 2400,
    proteinG: 180,
    carbsG: 250,
    fatG: 70,
    appliesTo: 'global',
  );

  Future<void> open(
    WidgetTester tester, {
    required TdeeEstimateResult? estimate,
    TargetRule? saved,
    double width = 800,
    double textScale = 1.0,
  }) async {
    tester.view.physicalSize = Size(width, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          clockProvider.overrideWithValue(_FixedClock(now)),
          tdeeEstimateProvider.overrideWithValue(estimate),
          savedTargetForTodayProvider.overrideWith((ref) async => saved),
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showTdeeEstimateSheet(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Finder usedCard() => find.byKey(const ValueKey('tdee_used_card'));
  Finder alsoRecorded() => find.byKey(const ValueKey('tdee_also_recorded'));

  testWidgets('shows the title and no subtitle', (tester) async {
    await open(tester, estimate: observed());
    expect(find.text('Maintenance estimate'), findsOneWidget);
  });

  testWidgets('observed: window derives from span_days + 1, not window_days', (
    tester,
  ) async {
    await open(tester, estimate: observed());
    expect(
      find.text('Worked out from what you ate and how your weight trended.'),
      findsOneWidget,
    );
    expect(find.text('WINDOW'), findsOneWidget);
    expect(find.text('Based on the last 14 days'), findsOneWidget);
    expect(find.text('WHAT WE USED'), findsOneWidget);
    expect(find.text('Average intake'), findsOneWidget);
    expect(find.text('2,310 kcal/day'), findsOneWidget);
    expect(find.text('Days with food logged'), findsOneWidget);
    expect(find.text('12 of 14'), findsOneWidget);
    expect(find.text('Weight trend'), findsOneWidget);
    expect(find.text('-0.4 kg'), findsOneWidget);
    expect(find.text('Weigh-ins'), findsOneWidget);
    expect(find.text('6'), findsOneWidget);
    expect(find.text('Based on the last 21 days'), findsNothing);
    expect(find.text('12 of 21'), findsNothing);
    expect(find.textContaining('35'), findsNothing);
    expect(find.text('Updated today'), findsOneWidget);
  });

  testWidgets('observed 28 dense days shows 28, never the 35 candidate', (
    tester,
  ) async {
    await open(
      tester,
      estimate: observed(
        windowDays: 35,
        inputs: const {
          'mean_intake_kcal': 2310,
          'logged_days': 28,
          'window_days': 35,
          'span_days': 27,
          'weight_trend_delta_kg': -0.4,
          'weigh_ins': 9,
        },
      ),
    );
    expect(find.text('Based on the last 28 days'), findsOneWidget);
    expect(find.text('28 of 28'), findsOneWidget);
    expect(find.textContaining('35'), findsNothing);
  });

  testWidgets('observed without span_days omits window line and food days', (
    tester,
  ) async {
    await open(
      tester,
      estimate: observed(
        inputs: const {
          'mean_intake_kcal': 2310,
          'logged_days': 12,
          'window_days': 21,
          'weight_trend_delta_kg': -0.4,
          'weigh_ins': 6,
        },
      ),
    );
    expect(find.textContaining('Based on the last'), findsNothing);
    expect(find.text('Days with food logged'), findsNothing);
    expect(find.textContaining('21'), findsNothing);
    expect(find.text('Average intake'), findsOneWidget);
    expect(find.text('Weight trend'), findsOneWidget);
    expect(find.text('-'), findsNothing);
    expect(find.text('N/A'), findsNothing);
  });

  testWidgets('aging: method line and Last measured row', (tester) async {
    await open(
      tester,
      estimate: observed(
        qualified: false,
        inputs: {
          'mean_intake_kcal': 2310,
          'logged_days': 12,
          'window_days': 21,
          'span_days': 13,
          'weight_trend_delta_kg': -0.4,
          'weigh_ins': 6,
          'held': true,
          'measured_at': DateTime(2026, 9, 19, 9).toIso8601String(),
        },
      ),
    );
    expect(
      find.text('Measured from your logs 9 days ago. Log again to refresh it.'),
      findsOneWidget,
    );
    expect(find.text('Last measured'), findsOneWidget);
    expect(find.text('9 days ago'), findsOneWidget);
    expect(find.text('Based on the last 14 days'), findsOneWidget);
    expect(find.text('Measured · Aging estimate'), findsOneWidget);
  });

  testWidgets('classified: only used inputs inside WHAT WE USED', (
    tester,
  ) async {
    await open(tester, estimate: classifier(const {}));
    expect(
      find.text('Worked out from your daily activity and training.'),
      findsOneWidget,
    );
    expect(find.text('Based on the last 14 days'), findsOneWidget);
    expect(find.text('Average steps'), findsOneWidget);
    expect(find.text('9,200/day'), findsOneWidget);
    expect(find.text('Logged workouts'), findsOneWidget);
    expect(find.text('3/week'), findsOneWidget);
    expect(find.text('Activity factor'), findsOneWidget);
    expect(find.text('1.55'), findsOneWidget);
    expect(find.text('Also recorded (not used in the estimate)'), findsNothing);
    expect(alsoRecorded(), findsNothing);
    expect(find.text('Active calories'), findsNothing);
  });

  testWidgets('classified: recorded-only inputs sit outside WHAT WE USED', (
    tester,
  ) async {
    await open(
      tester,
      estimate: classifier(const {
        'active_kcal': 480,
        'sleep_hours': 7.4,
        'resting_hr': 58,
      }),
    );
    expect(
      find.text('Also recorded (not used in the estimate)'),
      findsOneWidget,
    );
    for (final label in ['Active calories', 'Sleep', 'Resting heart rate']) {
      expect(find.text(label), findsOneWidget);
      expect(
        find.descendant(of: usedCard(), matching: find.text(label)),
        findsNothing,
      );
      expect(
        find.descendant(of: alsoRecorded(), matching: find.text(label)),
        findsOneWidget,
      );
    }
    expect(find.text('480 kcal/day'), findsOneWidget);
    expect(find.text('7.4 h/night'), findsOneWidget);
    expect(find.text('58 bpm'), findsOneWidget);
    expect(
      find.descendant(of: usedCard(), matching: find.text('Average steps')),
      findsOneWidget,
    );
  });

  testWidgets('classified: also-recorded rows render only when present', (
    tester,
  ) async {
    await open(tester, estimate: classifier(const {'sleep_hours': 7.4}));
    expect(alsoRecorded(), findsOneWidget);
    expect(find.text('Sleep'), findsOneWidget);
    expect(find.text('Active calories'), findsNothing);
    expect(find.text('Resting heart rate'), findsNothing);
  });

  testWidgets('null estimate renders title and trust footnote only', (
    tester,
  ) async {
    await open(tester, estimate: null);
    expect(tester.takeException(), isNull);
    expect(find.text('Maintenance estimate'), findsOneWidget);
    expect(
      find.text(
        'This is an estimate, not a medical measurement. '
        'It never changes a target you set yourself.',
      ),
      findsOneWidget,
    );
    expect(find.text('WINDOW'), findsNothing);
    expect(find.text('WHAT WE USED'), findsNothing);
  });

  testWidgets('calibrating: onboarding rows and empty-state sentence', (
    tester,
  ) async {
    await open(tester, estimate: calibrating);
    expect(
      find.text(
        'Using the activity level you chose at setup until there is enough '
        'data to measure.',
      ),
      findsOneWidget,
    );
    expect(find.text('Onboarding activity level'), findsOneWidget);
    expect(find.text('Lightly Active'), findsOneWidget);
    expect(find.text('Activity factor'), findsOneWidget);
    expect(find.text('1.375'), findsOneWidget);
    expect(
      find.text(
        'Log food and your weight for about two weeks and this switches to '
        'a measured number automatically.',
      ),
      findsOneWidget,
    );
    expect(find.text('WINDOW'), findsNothing);
    expect(
      find.text('Calibrating — using onboarding estimate'),
      findsOneWidget,
    );
  });

  testWidgets('saved target: two tiles side by side, caption below saved', (
    tester,
  ) async {
    await open(tester, estimate: observed(), saved: saved2400);
    final savedTile = find.byKey(const ValueKey('tdee_saved_tile'));
    final estTile = find.byKey(const ValueKey('tdee_estimate_tile'));
    expect(savedTile, findsOneWidget);
    expect(estTile, findsOneWidget);
    expect(
      find.descendant(of: savedTile, matching: find.text('YOUR SAVED TARGET')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: savedTile, matching: find.text('2,400 kcal')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: savedTile, matching: find.byIcon(Icons.flag_rounded)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: estTile, matching: find.text('MAINTENANCE ESTIMATE')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: estTile, matching: find.text('2,310 kcal')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: estTile,
        matching: find.byIcon(Icons.timeline_rounded),
      ),
      findsOneWidget,
    );

    final caption = find.text('set manually');
    expect(caption, findsOneWidget);
    expect(find.descendant(of: savedTile, matching: caption), findsNothing);
    expect(find.descendant(of: estTile, matching: caption), findsNothing);
    expect(
      tester.getTopLeft(caption).dy,
      greaterThanOrEqualTo(tester.getBottomLeft(savedTile).dy),
    );
    // Side by side at a wide surface.
    expect(tester.getTopLeft(savedTile).dy, tester.getTopLeft(estTile).dy);
    expect(
      find.text(
        'Your saved target includes any cut or bulk adjustment, so it can '
        'sit above or below maintenance on purpose.',
      ),
      findsOneWidget,
    );
    // No delta, arrow or signed difference between the two figures.
    expect(
      find.byWidgetPredicate(
        (w) => w is Text && RegExp(r'[+↑↓→]').hasMatch(w.data ?? ''),
      ),
      findsNothing,
    );
  });

  testWidgets('no saved target: one full-width estimate tile only', (
    tester,
  ) async {
    await open(tester, estimate: observed());
    expect(find.byKey(const ValueKey('tdee_saved_tile')), findsNothing);
    expect(find.byKey(const ValueKey('tdee_estimate_tile')), findsOneWidget);
    expect(find.text('YOUR SAVED TARGET'), findsNothing);
    expect(find.text('set manually'), findsNothing);
    expect(find.textContaining('Your saved target includes'), findsNothing);
    expect(find.byIcon(Icons.timeline_rounded), findsOneWidget);
    // Full width: as wide as the input card below it.
    expect(
      tester.getSize(find.byKey(const ValueKey('tdee_estimate_tile'))).width,
      tester.getSize(usedCard()).width,
    );
  });

  testWidgets('2x text scale with a saved target does not overflow', (
    tester,
  ) async {
    await open(tester, estimate: observed(), saved: saved2400, textScale: 2.0);
    expect(tester.takeException(), isNull);
    expect(find.text('set manually'), findsOneWidget);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('360dp wide at ${scale}x stacks the tiles without overflow', (
      tester,
    ) async {
      await open(
        tester,
        estimate: observed(),
        saved: saved2400,
        width: 360,
        textScale: scale,
      );
      expect(tester.takeException(), isNull);
      final savedTile = find.byKey(const ValueKey('tdee_saved_tile'));
      final estTile = find.byKey(const ValueKey('tdee_estimate_tile'));
      final caption = find.text('set manually');
      expect(
        tester.getTopLeft(savedTile).dy,
        lessThan(tester.getTopLeft(estTile).dy),
      );
      expect(
        tester.getTopLeft(caption).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(savedTile).dy),
      );
      expect(
        tester.getTopLeft(caption).dy,
        lessThan(tester.getTopLeft(estTile).dy),
      );
    });
  }

  testWidgets('600dp wide keeps the tiles side by side', (tester) async {
    await open(tester, estimate: observed(), saved: saved2400, width: 600);
    expect(tester.takeException(), isNull);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('tdee_saved_tile'))).dy,
      tester.getTopLeft(find.byKey(const ValueKey('tdee_estimate_tile'))).dy,
    );
  });

  testWidgets('trust footnote is present and no accept controls exist', (
    tester,
  ) async {
    await open(tester, estimate: observed(), saved: saved2400);
    expect(
      find.text(
        'This is an estimate, not a medical measurement. '
        'It never changes a target you set yourself.',
      ),
      findsOneWidget,
    );
    for (final s in [
      'Update my target',
      'Keep current target',
      'Done',
      'Use this estimate',
    ]) {
      expect(find.textContaining(s), findsNothing);
    }
    expect(find.byType(ElevatedButton), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
  });
}
