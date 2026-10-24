import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/features/steps/application/steps_providers.dart';
import 'package:herculex/features/steps/domain/step_lifting_correlation.dart';
import 'package:herculex/features/steps/domain/step_record.dart';
import 'package:herculex/features/steps/domain/step_score_engine.dart';
import 'package:herculex/features/steps/domain/step_weightlifting_impact.dart';
import 'package:herculex/features/steps/presentation/views/steps_tracking_view.dart';
import 'package:herculex/features/steps/presentation/widgets/step_hero_progress_ring.dart';
import 'package:herculex/features/steps/presentation/widgets/step_hourly_bar_chart.dart';
import 'package:herculex/features/steps/presentation/widgets/step_weightlifting_impact_card.dart';

void main() {
  group('Steps Presentation Widgets Tests', () {
    testWidgets('StepHeroProgressRing renders step counts and progress', (
      tester,
    ) async {
      final record = StepRecord.fromStepCount(
        dateIso: '2026-10-14',
        stepCount: 8420,
        goal: 10000,
        distanceKm: 6.4,
        activeKcal: 336.0,
        activeMinutes: 76,
      );
      final score = StepScoreEngine.calculate(steps: 8420, goal: 10000);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: StepHeroProgressRing(record: record, score: score),
            ),
          ),
        ),
      );

      expect(find.text('DAILY STEP TARGET'), findsOneWidget);
      expect(find.text('8,420'), findsOneWidget);
      expect(find.text('of 10,000 steps'), findsOneWidget);
      expect(find.text('84%'), findsOneWidget);
      expect(find.text('6.4 km'), findsOneWidget);
      expect(find.text('336 kcal'), findsOneWidget);
    });

    testWidgets('StepHourlyBarChart renders hourly title and intervals', (
      tester,
    ) async {
      final record = StepRecord.fromStepCount(
        dateIso: '2026-10-14',
        stepCount: 10000,
        goal: 10000,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: StepHourlyBarChart(record: record),
            ),
          ),
        ),
      );

      expect(find.text('HOURLY DISTRIBUTION'), findsOneWidget);
      expect(find.text('Activity pacing throughout the day'), findsOneWidget);
    });

    testWidgets(
      'StepWeightliftingImpactCard renders volume and tactical cues',
      (tester) async {
        final impact = StepWeightliftingEngine.calculate(steps: 19500);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: StepWeightliftingImpactCard(impact: impact),
              ),
            ),
          ),
        );

        expect(find.text('SIGNIFICANT LEG FATIGUE'), findsOneWidget);
        expect(find.text('Weightlifting Impact Analysis'), findsOneWidget);
        expect(find.text('-20% Sets'), findsOneWidget);
        expect(find.text('+45g Carbs'), findsOneWidget);
        expect(find.text('LOWER BODY SESSION (LEGS / SQUATS)'), findsOneWidget);
        expect(find.text('UPPER BODY SESSION (BENCH / PRESS)'), findsOneWidget);
      },
    );

    testWidgets(
      'StepsTrackingView responds to swipe gestures to change selected date',
      (tester) async {
        final container = ProviderContainer(
          overrides: [
            selectedStepRecordProvider.overrideWith(
              (ref) => Future.value(null),
            ),
            todayStepsProvider.overrideWith((ref) => Stream.value(null)),
            stepHistoryProvider(30).overrideWith((ref) => Future.value([])),
            stepLiftingCorrelationProvider.overrideWith(
              (ref) => Future.value(StepLiftingCorrelation.empty()),
            ),
          ],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(home: StepsTrackingView()),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        final initialDate = container.read(selectedStepDateProvider);

        // Swipe right to navigate to previous day
        await tester.drag(find.byType(StepsTrackingView), const Offset(300, 0));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        final previousDate = container.read(selectedStepDateProvider);
        expect(
          previousDate.day,
          initialDate.subtract(const Duration(days: 1)).day,
        );

        // Swipe left to navigate forward to today
        await tester.drag(
          find.byType(StepsTrackingView),
          const Offset(-300, 0),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        final nextDate = container.read(selectedStepDateProvider);
        expect(nextDate.day, initialDate.day);
      },
    );
  });
}
