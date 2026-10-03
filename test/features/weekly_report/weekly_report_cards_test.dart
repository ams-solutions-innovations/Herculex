import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/design_system/theme/app_theme.dart';
import 'package:herculex/features/weekly_report/domain/weekly_report_sections.dart';
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
}
