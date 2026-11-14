import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/design_system/components/components.dart';
import 'package:herculex/design_system/theme/app_theme.dart';
import 'package:herculex/features/programs/presentation/sheets/exercise_replacement_sheet.dart';
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
    plannedAllowsAdvancedTechniques: false,
  );

  for (final (name, theme) in [
    ('light', AppTheme.lightTheme),
    ('dark', AppTheme.darkTheme),
  ]) {
    testWidgets(
      'ExerciseReplacementSheet renders with opaque surface in $name mode',
      (tester) async {
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
      },
    );

    testWidgets(
      'SmartSubstitutionSheet renders with opaque surface in $name mode',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              recentExerciseIdsProvider.overrideWith((ref) async => <int>{}),
              exerciseCatalogProvider(
                const ExerciseCatalogFilter(),
              ).overrideWith(
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
      },
    );
  }

  testWidgets(
    'SmartSubstitutionSheet.pickSubstitute shows Substitute Exercise with biomechanical matches and returns picked exercise',
    (tester) async {
      final dumbbellBench = const ExerciseCatalogData(
        id: 2,
        name: 'Dumbbell Bench Press',
        primaryMuscle: 'Chest',
        equipment: 'dumbbell',
        mechanics: 'compound',
        force: 'push',
        plane: 'horizontal',
        defaultRestSeconds: 120,
        isCustom: false,
        category: 'strength',
        modality: 'dumbbell',
        cnsScore: 3,
        recoveryImpact: 3,
        loggingMetric: 'weight_reps',
        supportsWeightedBodyweight: false,
        isReviewed: true,
        programmingDifficulty: 'beginner',
        programmingCommonness: 'basic',
        allowedTrainingStyles: '[]',
        technicalEligibility: 'automatic',
      );
      final legCurl = const ExerciseCatalogData(
        id: 3,
        name: 'Seated Leg Curl',
        primaryMuscle: 'Hamstrings',
        equipment: 'machine',
        mechanics: 'isolation',
        force: 'pull',
        plane: 'sagittal',
        defaultRestSeconds: 90,
        isCustom: false,
        category: 'hypertrophy',
        modality: 'machine',
        cnsScore: 2,
        recoveryImpact: 2,
        loggingMetric: 'weight_reps',
        supportsWeightedBodyweight: false,
        isReviewed: true,
        programmingDifficulty: 'beginner',
        programmingCommonness: 'basic',
        allowedTrainingStyles: '[]',
        technicalEligibility: 'automatic',
      );

      ExerciseCatalogData? picked;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            recentExerciseIdsProvider.overrideWith((ref) async => <int>{}),
            exerciseCatalogProvider(const ExerciseCatalogFilter()).overrideWith(
              (ref) => AsyncValue.data([
                sampleExercise(),
                legCurl,
                dumbbellBench,
              ]),
            ),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () async {
                      picked = await SmartSubstitutionSheet.pickSubstitute(
                        context,
                        originalExercise: sampleExercise(),
                      );
                    },
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Substitute Exercise'), findsOneWidget);
      expect(find.text('Suggested Biomechanical Matches'), findsOneWidget);
      expect(find.text('Dumbbell Bench Press'), findsOneWidget);
      expect(find.text('Add Exercise'), findsNothing);

      await tester.ensureVisible(find.text('Dumbbell Bench Press'));
      await tester.tap(find.text('Dumbbell Bench Press'));
      await tester.pumpAndSettle();

      expect(picked?.id, 2);
    },
  );
}
