import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/design_system/components/components.dart';
import 'package:herculex/design_system/theme/app_theme.dart';
import 'package:herculex/features/programs/presentation/views/program_review_view.dart';
import 'package:herculex/features/workouts/application/workouts_providers.dart';

void main() {
  ExerciseCatalogData exercise() => const ExerciseCatalogData(
    id: 1,
    name: 'Barbell Bench Press',
    primaryMuscle: 'Chest',
    equipment: 'barbell',
    mechanics: 'compound',
    force: 'push',
    plane: 'horizontal',
    defaultRestSeconds: 120,
    isCustom: false,
    category: 'strength',
    modality: 'strength',
    cnsScore: 4,
    recoveryImpact: 3,
    loggingMetric: 'weight_reps',
    supportsWeightedBodyweight: false,
    isReviewed: true,
    programmingDifficulty: 'intermediate',
    programmingCommonness: 'basic',
    allowedTrainingStyles: '[]',
    technicalEligibility: 'automatic',
  );

  Widget harness(ThemeData theme) => ProviderScope(
    overrides: [recentExerciseIdsProvider.overrideWith((ref) async => <int>{})],
    child: MaterialApp(
      theme: theme,
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: ExerciseReplacementSheet(
            current: exercise(),
            candidates: const [],
          ),
        ),
      ),
    ),
  );

  for (final theme in [AppTheme.lightTheme, AppTheme.darkTheme]) {
    testWidgets('exercise replacement sheet has an opaque Hx surface', (
      tester,
    ) async {
      await tester.pumpWidget(harness(theme));

      expect(find.byType(HxSheet), findsOneWidget);
      expect(find.text('Choose a replacement'), findsOneWidget);

      final sheetMaterial = tester.widget<Material>(
        find
            .descendant(
              of: find.byType(HxSheet),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(sheetMaterial.color, theme.colorScheme.surfaceContainer);
      expect(sheetMaterial.color, isNot(Colors.transparent));
    });

    testWidgets('exercise replacement defaults to the recommended wave scope', (
      tester,
    ) async {
      await tester.pumpWidget(harness(theme));

      expect(find.text('This wave · Recommended'), findsOneWidget);
      expect(find.text('This and future waves'), findsOneWidget);
      expect(find.text('Entire block'), findsOneWidget);
      expect(
        tester
            .widget<ChoiceChip>(
              find.widgetWithText(ChoiceChip, 'This wave · Recommended'),
            )
            .selected,
        isTrue,
      );
    });
  }
}
