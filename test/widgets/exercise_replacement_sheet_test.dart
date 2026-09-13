import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/design_system/components/components.dart';
import 'package:herculex/design_system/theme/app_theme.dart';
import 'package:herculex/features/programs/presentation/views/program_review_view.dart';
import 'package:herculex/features/workouts/application/workouts_providers.dart';
import 'package:herculex/features/workouts/presentation/sheets/smart_substitution_sheet.dart';

void main() {
  ExerciseCatalogData sampleExercise() => const ExerciseCatalogData(
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

  WorkoutExerciseData sampleWorkoutExercise() => const WorkoutExerciseData(
    id: 101,
    sessionId: 1,
    exerciseId: 1,
    orderIndex: 0,
  );

  for (final (name, theme) in [
    ('light', AppTheme.lightTheme),
    ('dark', AppTheme.darkTheme),
  ]) {
    testWidgets('ExerciseReplacementSheet renders with opaque surface in $name mode', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            recentExerciseIdsProvider.overrideWith((ref) async => <int>{}),
          ],
          child: MaterialApp(
            theme: theme,
            home: Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: ExerciseReplacementSheet(
                  current: sampleExercise(),
                  candidates: const [],
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(HxSheet), findsOneWidget);
      final sheetMaterial = tester.widget<Material>(
        find
            .descendant(
              of: find.byType(HxSheet),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(sheetMaterial.color, isNotNull);
      expect(sheetMaterial.color!.a, 1.0);
      expect(sheetMaterial.color, theme.colorScheme.surfaceContainer);
    });

    testWidgets('SmartSubstitutionSheet renders with opaque surface in $name mode', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            recentExerciseIdsProvider.overrideWith((ref) async => <int>{}),
            exerciseCatalogProvider(const ExerciseCatalogFilter()).overrideWith(
              (ref) => const AsyncValue.data(<ExerciseCatalogData>[]),
            ),
          ],
          child: MaterialApp(
            theme: theme,
            home: Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: SmartSubstitutionSheet(
                  workoutExercise: sampleWorkoutExercise(),
                  originalExercise: sampleExercise(),
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(HxSheet), findsOneWidget);
      expect(find.text('Smart Substitution'), findsOneWidget);
      final sheetMaterial = tester.widget<Material>(
        find
            .descendant(
              of: find.byType(HxSheet),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(sheetMaterial.color, isNotNull);
      expect(sheetMaterial.color!.a, 1.0);
      expect(sheetMaterial.color, theme.colorScheme.surfaceContainer);
    });
  }
}
