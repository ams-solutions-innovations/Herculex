import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/core/utils/clock.dart';
import 'package:herculex/design_system/theme/app_theme.dart';
import 'package:herculex/features/nutrition/application/tdee_calibration_providers.dart';
import 'package:herculex/features/nutrition/application/tdee_providers.dart';
import 'package:herculex/features/nutrition/data/tdee_inputs_repository.dart';
import 'package:herculex/features/nutrition/domain/tdee_estimate.dart';
import 'package:herculex/features/nutrition/domain/tdee_trend.dart';
import 'package:herculex/features/nutrition/presentation/views/activity_calibration_view.dart';
import 'package:herculex/features/profile/domain/profile.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _profile = Profile(
  name: 'Test Athlete',
  weightKg: 80,
  heightCm: 180,
  ageYears: 28,
  sex: BiologicalSex.male,
  activityLevel: ActivityLevel.active,
  goal: FitnessGoal.maintenance,
);

TdeeEstimateResult _estimate(
  TdeeMethod method, {
  Map<String, Object?> inputs = const {},
  bool qualified = true,
}) => TdeeEstimateResult(
  kcal: 2650,
  method: method,
  confidence: TdeeConfidence.medium,
  windowDays: 28,
  observedQualified: qualified,
  inputs: inputs,
  estimatedAt: DateTime(2026, 10, 8, 8),
);

class _FixedClock implements Clock {
  const _FixedClock(this._now);
  final DateTime _now;
  @override
  DateTime now() => _now;
}

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  Future<void> pump(
    WidgetTester tester, {
    required TdeeEstimateResult? latest,
    List<TdeeEstimateResult> history = const [],
    TdeeInputs inputs = const TdeeInputs(),
    Profile? profile = _profile,
  }) async {
    tester.view.physicalSize = const Size(900, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          profileProvider.overrideWith((ref) => Stream.value(profile)),
          latestTdeeEstimateProvider.overrideWith(
            (ref) => Stream.value(latest),
          ),
          tdeeEstimateHistoryProvider.overrideWith(
            (ref) => Stream.value(history),
          ),
          tdeeCalibrationInputsProvider.overrideWith((ref) async => inputs),
          clockProvider.overrideWithValue(
            _FixedClock(DateTime(2026, 10, 9, 12)),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: const ActivityCalibrationView(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('cold start: shows the sum from BMR and the activity factor', (
    tester,
  ) async {
    await pump(tester, latest: null, inputs: const TdeeInputs());

    expect(
      find.text('Calibrating — using onboarding estimate'),
      findsOneWidget,
    );
    expect(find.text('Starting estimate'), findsOneWidget);
    expect(find.text('· in use now'), findsOneWidget);
    expect(find.text('Base metabolism (BMR)'), findsOneWidget);
    expect(find.textContaining('Activity factor (Active)'), findsOneWidget);
    expect(find.text('WHAT IT NEEDS TO MEASURE'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('observed: shows intake, weight energy and maintenance', (
    tester,
  ) async {
    await pump(
      tester,
      latest: _estimate(
        TdeeMethod.observed,
        inputs: const {
          'mean_intake_kcal': 2400,
          'logged_days': 24,
          'span_days': 27,
          'weight_trend_delta_kg': -0.8,
          'weigh_ins': 10,
        },
      ),
    );

    expect(find.text('Measured · Medium confidence'), findsOneWidget);
    expect(find.text('Average intake'), findsOneWidget);
    expect(find.text('2,400 kcal'), findsOneWidget);
    expect(find.text('+250 kcal'), findsOneWidget);
    expect(find.text('2,650 kcal'), findsWidgets);
    // A qualified observed estimate no longer needs the checklist.
    expect(find.text('WHAT IT NEEDS TO MEASURE'), findsNothing);
  });

  testWidgets('classifier with history and logs renders every chart', (
    tester,
  ) async {
    final now = DateTime(2026, 10, 9);
    String iso(int age) {
      final d = DateTime(now.year, now.month, now.day - age);
      return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}';
    }

    await pump(
      tester,
      latest: _estimate(
        TdeeMethod.classifier,
        inputs: const {'activity_factor': 1.55, 'avg_steps': 9000},
      ),
      history: [
        _estimate(TdeeMethod.classifier),
        TdeeEstimateResult(
          kcal: 2500,
          method: TdeeMethod.coldStart,
          confidence: TdeeConfidence.low,
          windowDays: 0,
          observedQualified: false,
          inputs: const {},
          estimatedAt: DateTime(2026, 9, 20, 8),
        ),
      ],
      inputs: TdeeInputs(
        foodLoggedDays: {for (var i = 0; i < 10; i++) iso(i)},
        dailyKcalByDate: {for (var i = 0; i < 10; i++) iso(i): 2300.0 + i * 20},
        weightLogs: [
          for (var i = 20; i >= 0; i -= 4)
            WeightLog(
              DateTime(now.year, now.month, now.day - i),
              80 - i * 0.02,
            ),
        ],
      ),
    );

    expect(find.text('Maintenance over time'), findsOneWidget);
    expect(find.text('Weight trend'), findsOneWidget);
    expect(find.text('Daily intake'), findsOneWidget);
    expect(find.text('Classified · Medium confidence'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no profile metrics: explains what to add, no crash', (
    tester,
  ) async {
    await pump(tester, latest: null, profile: null);

    expect(
      find.textContaining('Add your weight, height and age'),
      findsOneWidget,
    );
    expect(find.text('Weight trend'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
