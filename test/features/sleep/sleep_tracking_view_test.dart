// test/features/sleep/sleep_tracking_view_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/features/sleep/application/sleep_providers.dart';
import 'package:herculex/features/sleep/domain/sleep_lifting_correlation.dart';
import 'package:herculex/features/sleep/domain/sleep_record.dart';
import 'package:herculex/features/sleep/domain/sleep_score_engine.dart';
import 'package:herculex/features/sleep/domain/sleep_weightlifting_impact.dart';
import 'package:herculex/features/sleep/presentation/views/sleep_tracking_view.dart';
import 'package:herculex/features/sleep/presentation/widgets/sleep_hero_gauge.dart';
import 'package:herculex/features/sleep/presentation/widgets/sleep_stages_breakdown_card.dart';
import 'package:herculex/features/sleep/presentation/widgets/sleep_weightlifting_impact_card.dart';

void main() {
  group('Sleep Presentation Widgets Tests', () {
    testWidgets('SleepHeroGauge renders score and duration metrics', (
      tester,
    ) async {
      final record = SleepRecord.fromHours(
        dateIso: '2026-10-13',
        totalHours: 8.0,
        deepHours: 1.8,
        remHours: 1.8,
        lightHours: 4.4,
        restingHr: 54.0,
      );
      final score = SleepScoreEngine.calculate(record);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SleepHeroGauge(
              record: record,
              score: score,
              targetHours: 8.0,
            ),
          ),
        ),
      );

      // Verify header and metrics
      expect(find.text('SLEEP RECOVERY INDEX'), findsOneWidget);
      expect(find.text('8h'), findsOneWidget);
      expect(find.text('54 bpm'), findsOneWidget);
    });

    testWidgets('SleepStagesBreakdownCard renders stages correctly', (
      tester,
    ) async {
      final record = SleepRecord.fromHours(
        dateIso: '2026-10-13',
        totalHours: 7.5,
        deepHours: 1.5,
        remHours: 1.5,
        lightHours: 4.0,
        awakeHours: 0.5,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SleepStagesBreakdownCard(record: record),
            ),
          ),
        ),
      );

      expect(find.text('SLEEP STAGES & CYCLES'), findsOneWidget);
      expect(find.text('DEEP SLEEP'), findsOneWidget);
      expect(find.text('REM SLEEP'), findsOneWidget);
      expect(find.text('LIGHT SLEEP'), findsOneWidget);
      expect(find.text('AWAKE TIME'), findsOneWidget);
      expect(find.text('HGH & Tissue Repair'), findsOneWidget);
      expect(find.text('CNS Motor Recruitment'), findsOneWidget);
    });

    testWidgets(
      'SleepWeightliftingImpactCard renders athletic advice and volume factor',
      (tester) async {
        final impact = SleepWeightliftingEngine.evaluate(sleepHours: 5.0);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: SleepWeightliftingImpactCard(impact: impact),
              ),
            ),
          ),
        );

        expect(find.text(impact.statusBadge), findsOneWidget);
        expect(find.text('VOLUME MOD'), findsOneWidget);
        expect(find.text('75%'), findsOneWidget); // 75% volume for <5.5h
        expect(find.text('PHYSIOLOGICAL IMPACT'), findsOneWidget);
        expect(find.text('TACTICAL PRE-WORKOUT PROTOCOL'), findsOneWidget);
      },
    );

    testWidgets(
      'SleepTrackingView responds to swipe gestures to change selected date',
      (tester) async {
        final container = ProviderContainer(
          overrides: [
            selectedSleepRecordProvider.overrideWith(
              (ref) => Future.value(null),
            ),
            todaySleepProvider.overrideWith((ref) => Stream.value(null)),
            sleepHistoryProvider(30).overrideWith((ref) => Future.value([])),
            sleepLiftingCorrelationProvider.overrideWith(
              (ref) => Future.value(SleepLiftingCorrelation.empty()),
            ),
          ],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(home: SleepTrackingView()),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        final initialDate = container.read(selectedSleepDateProvider);

        // Swipe right to navigate to previous day
        await tester.drag(find.byType(SleepTrackingView), const Offset(300, 0));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        final previousDate = container.read(selectedSleepDateProvider);
        expect(
          previousDate.day,
          initialDate.subtract(const Duration(days: 1)).day,
        );

        // Swipe left to navigate forward to today
        await tester.drag(
          find.byType(SleepTrackingView),
          const Offset(-300, 0),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        final nextDate = container.read(selectedSleepDateProvider);
        expect(nextDate.day, initialDate.day);
      },
    );
  });
}
