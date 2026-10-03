import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/design_system/components/premium_button.dart';
import 'package:herculex/design_system/theme/app_theme.dart';
import 'package:herculex/features/weekly_report/domain/narrative_status.dart';
import 'package:herculex/features/weekly_report/domain/weekly_narrative.dart';
import 'package:herculex/features/weekly_report/domain/weekly_report_sections.dart';
import 'package:herculex/features/weekly_report/presentation/widgets/ai_narrative_card.dart';
import 'package:herculex/features/weekly_report/presentation/widgets/nutrition_section_card.dart';
import 'package:herculex/features/weekly_report/presentation/widgets/physique_section_card.dart';
import 'package:herculex/features/weekly_report/presentation/widgets/recovery_section_card.dart';
import 'package:herculex/features/weekly_report/presentation/widgets/training_section_card.dart';

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(900, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.darkTheme,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('NutritionSectionCard', () {
    const section = NutritionSection(
      daysLogged: 5,
      avgKcal: 2150,
      avgProteinG: 140,
      targetKcal: 2400,
      targetProteinG: 150,
      adherenceDays: 3,
      topFoods: [
        TopFood(name: 'Oats', count: 6),
        TopFood(name: 'Chicken breast', count: 5),
        TopFood(name: 'Rice', count: 4),
      ],
    );

    testWidgets('renders averages, target, days and foods', (tester) async {
      await _pump(tester, const NutritionSectionCard(section: section));
      expect(find.text('Nutrition'), findsOneWidget);
      expect(find.text('2150'), findsOneWidget);
      expect(find.text('of 2400'), findsOneWidget);
      expect(find.textContaining('140'), findsWidgets);
      expect(find.text('Days logged'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.textContaining('Oats'), findsOneWidget);
      expect(find.textContaining('Chicken breast'), findsOneWidget);
      expect(find.textContaining('Rice'), findsOneWidget);
      expect(find.text('No data this week'), findsNothing);
    });

    testWidgets('omits target and adherence when null', (tester) async {
      await _pump(
        tester,
        const NutritionSectionCard(
          section: NutritionSection(
            daysLogged: 2,
            avgKcal: 1800,
            avgProteinG: 100,
            topFoods: [],
          ),
        ),
      );
      expect(find.textContaining('of '), findsNothing);
      expect(find.text('Days on target'), findsNothing);
    });

    testWidgets('null section shows heading and the single no-data label', (
      tester,
    ) async {
      await _pump(tester, const NutritionSectionCard(section: null));
      expect(find.text('Nutrition'), findsOneWidget);
      expect(find.text('No data this week'), findsOneWidget);
      expect(find.text('Days logged'), findsNothing);
    });
  });

  group('TrainingSectionCard', () {
    testWidgets('renders sessions, tonnage delta and e1RM movers', (
      tester,
    ) async {
      await _pump(
        tester,
        const TrainingSectionCard(
          section: TrainingSection(
            sessions: 4,
            tonnageKg: 12500,
            prevWeekTonnageKg: 12000,
            e1rmMovers: [
              E1rmMover(exerciseName: 'Bench Press', e1rmKg: 105, deltaKg: 2.5),
            ],
          ),
        ),
      );
      expect(find.text('Training'), findsOneWidget);
      expect(find.text('4'), findsOneWidget);
      expect(find.textContaining('12500'), findsOneWidget);
      expect(find.textContaining('+500'), findsOneWidget);
      expect(find.textContaining('Bench Press'), findsOneWidget);
      expect(find.textContaining('+2.5 kg'), findsOneWidget);
    });

    testWidgets('null section shows the no-data label', (tester) async {
      await _pump(tester, const TrainingSectionCard(section: null));
      expect(find.text('Training'), findsOneWidget);
      expect(find.text('No data this week'), findsOneWidget);
    });
  });

  group('RecoverySectionCard', () {
    const statement = 'On days with more sleep, your RPE tended to be lower.';

    testWidgets('renders metrics, warnings, deload and statements verbatim', (
      tester,
    ) async {
      await _pump(
        tester,
        const RecoverySectionCard(
          section: RecoverySection(
            avgSleepHours: 7.4,
            avgSteps: 8200,
            avgRestingHr: 58,
            cnsDeloadSuggested: true,
            recoveryWarnings: ['Sleep under 6 h on 2 nights'],
            correlations: [
              CorrelationLine(
                kind: 'sleep_rpe',
                statement: statement,
                sampleSize: 6,
              ),
            ],
          ),
        ),
      );
      expect(find.text('Recovery'), findsOneWidget);
      expect(find.textContaining('7.4'), findsOneWidget);
      expect(find.textContaining('8200'), findsOneWidget);
      expect(find.textContaining('58'), findsOneWidget);
      expect(find.text('Sleep under 6 h on 2 nights'), findsOneWidget);
      expect(find.text('Deload suggested'), findsOneWidget);
      // Byte-for-byte: an exact-string finder, not textContaining.
      expect(find.text(statement), findsOneWidget);
    });

    testWidgets('hides metrics that are null and has no deload line', (
      tester,
    ) async {
      await _pump(
        tester,
        const RecoverySectionCard(
          section: RecoverySection(
            avgSleepHours: 7,
            cnsDeloadSuggested: false,
            recoveryWarnings: [],
            correlations: [],
          ),
        ),
      );
      expect(find.text('Avg steps'), findsNothing);
      expect(find.text('Resting HR'), findsNothing);
      expect(find.text('Deload suggested'), findsNothing);
    });

    testWidgets('null section shows the no-data label', (tester) async {
      await _pump(tester, const RecoverySectionCard(section: null));
      expect(find.text('Recovery'), findsOneWidget);
      expect(find.text('No data this week'), findsOneWidget);
    });
  });

  group('PhysiqueSectionCard', () {
    for (final entry in {
      'on_track': 'On track',
      'off_track': 'Off track',
      'inconclusive': 'Inconclusive',
    }.entries) {
      testWidgets('maps ${entry.key} to plain words', (tester) async {
        await _pump(
          tester,
          PhysiqueSectionCard(
            section: PhysiqueSection(
              checkInVerdict: entry.key,
              checkInConfidence: 'medium',
              bodyweightKg: 82.4,
              bodyweightDeltaKg: -0.4,
            ),
          ),
        );
        expect(find.text('Physique'), findsOneWidget);
        expect(find.text(entry.value), findsOneWidget);
        expect(find.textContaining('medium'), findsOneWidget);
        expect(find.textContaining('82.4'), findsOneWidget);
        expect(find.textContaining('-0.4'), findsOneWidget);
      });
    }

    testWidgets('null section shows the no-data label', (tester) async {
      await _pump(tester, const PhysiqueSectionCard(section: null));
      expect(find.text('Physique'), findsOneWidget);
      expect(find.text('No data this week'), findsOneWidget);
    });
  });

  group('AiNarrativeCard', () {
    const narrative = WeeklyNarrative(
      summary: 'You trained four times and ate close to target.',
      suggestions: [
        'Keep protein near 150 g on training days.',
        'Add a short walk on rest days.',
      ],
    );
    const note =
        'Herculex AI interprets the numbers above. It does not change them.';

    Future<void> pumpCard(
      WidgetTester tester, {
      required NarrativeStatus status,
      WeeklyNarrative? narrative,
      VoidCallback? onRetry,
      bool retryEnabled = true,
    }) => _pump(
      tester,
      AiNarrativeCard(
        status: status,
        narrative: narrative,
        onRetry: onRetry,
        retryEnabled: retryEnabled,
      ),
    );

    test('NarrativeStatus has exactly the five states', () {
      expect(NarrativeStatus.values.map((s) => s.name).toList(), [
        'loading',
        'ready',
        'pending',
        'offline',
        'quotaExhausted',
      ]);
    });

    testWidgets('ready: pill, heading, summary, suggestions, note, no button', (
      tester,
    ) async {
      await pumpCard(
        tester,
        status: NarrativeStatus.ready,
        narrative: narrative,
      );
      expect(find.text('Herculex AI'), findsOneWidget);
      expect(find.text("This week's read"), findsOneWidget);
      expect(find.text(narrative.summary), findsOneWidget);
      for (final s in narrative.suggestions) {
        expect(find.text(s), findsOneWidget);
      }
      expect(find.byIcon(Icons.arrow_right_alt), findsNWidgets(2));
      expect(find.byIcon(Icons.auto_awesome), findsOneWidget);
      expect(find.text(note), findsOneWidget);
      expect(find.byType(PremiumButton), findsNothing);
      expect(find.byType(InkWell), findsNothing);
      expect(find.text('Retry narrative'), findsNothing);
    });

    testWidgets('ready with three suggestions renders three rows', (
      tester,
    ) async {
      await pumpCard(
        tester,
        status: NarrativeStatus.ready,
        narrative: const WeeklyNarrative(
          summary: 'Summary.',
          suggestions: ['One.', 'Two.', 'Three.'],
        ),
      );
      expect(find.byIcon(Icons.arrow_right_alt), findsNWidgets(3));
    });

    testWidgets('has the Herculex AI interpretation semantics label', (
      tester,
    ) async {
      await pumpCard(
        tester,
        status: NarrativeStatus.ready,
        narrative: narrative,
      );
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              w.properties.label == 'Herculex AI interpretation',
        ),
        findsOneWidget,
      );
    });

    testWidgets('loading: heading, skeleton, label, no retry', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: const Scaffold(
            body: AiNarrativeCard(status: NarrativeStatus.loading),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text("This week's read"), findsOneWidget);
      expect(find.text('Herculex AI is reading your week…'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('narrative-skeleton-line')),
        findsNWidgets(3),
      );
      expect(find.byType(PremiumButton), findsNothing);
    });

    testWidgets('pending: generic copy and a working Retry button', (
      tester,
    ) async {
      var taps = 0;
      await pumpCard(
        tester,
        status: NarrativeStatus.pending,
        onRetry: () => taps++,
      );
      expect(
        find.text(
          "Narrative pending. Herculex AI couldn't write this week's "
          'summary. Your numbers above are saved. Try again.',
        ),
        findsOneWidget,
      );
      expect(find.text('Retry narrative'), findsOneWidget);
      final height = tester.getSize(find.byType(PremiumButton)).height;
      expect(height, greaterThanOrEqualTo(48));
      await tester.tap(find.text('Retry narrative'));
      expect(taps, 1);
    });

    testWidgets('offline: copy and enabled Retry', (tester) async {
      var taps = 0;
      await pumpCard(
        tester,
        status: NarrativeStatus.offline,
        onRetry: () => taps++,
      );
      expect(
        find.text("You're offline. Reconnect and tap Retry narrative."),
        findsOneWidget,
      );
      await tester.tap(find.text('Retry narrative'));
      expect(taps, 1);
    });

    testWidgets('quotaExhausted: per-day copy, Retry follows retryEnabled', (
      tester,
    ) async {
      var taps = 0;
      const copy =
          "You've used today's Herculex AI summaries. Your numbers above are "
          'saved. Try again tomorrow.';
      await pumpCard(
        tester,
        status: NarrativeStatus.quotaExhausted,
        onRetry: () => taps++,
        retryEnabled: false,
      );
      expect(find.text(copy), findsOneWidget);
      await tester.tap(find.text('Retry narrative'), warnIfMissed: false);
      expect(taps, 0);

      await pumpCard(
        tester,
        status: NarrativeStatus.quotaExhausted,
        onRetry: () => taps++,
      );
      expect(find.text(copy), findsOneWidget);
      await tester.tap(find.text('Retry narrative'));
      expect(taps, 1);
    });
  });
}
