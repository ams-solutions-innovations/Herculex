import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/programs/application/programs_providers.dart';
import 'package:herculex/features/programs/domain/programming_models.dart';
import 'package:herculex/features/workouts/application/workouts_providers.dart';
import 'package:herculex/features/workouts/presentation/views/exercise_library_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final sampleExercises = [
    const ExerciseCatalogData(
      id: 1,
      name: 'Barbell Bench Press',
      primaryMuscle: 'Chest',
      equipment: 'Barbell',
      mechanics: 'compound',
      force: 'push',
      plane: 'horizontal',
      defaultRestSeconds: 180,
      isCustom: false,
      category: 'strength',
      modality: 'barbell',
      cnsScore: 4,
      recoveryImpact: 4,
      loggingMetric: 'weight_reps',
      supportsWeightedBodyweight: false,
      isReviewed: true,
    ),
    const ExerciseCatalogData(
      id: 2,
      name: 'Incline Dumbbell Curl',
      primaryMuscle: 'Biceps',
      equipment: 'Dumbbell',
      mechanics: 'isolation',
      force: 'pull',
      plane: 'vertical',
      defaultRestSeconds: 90,
      isCustom: false,
      category: 'hypertrophy',
      modality: 'dumbbell',
      cnsScore: 2,
      recoveryImpact: 2,
      loggingMetric: 'weight_reps',
      supportsWeightedBodyweight: false,
      isReviewed: true,
    ),
    const ExerciseCatalogData(
      id: 3,
      name: 'Custom Cable Fly',
      primaryMuscle: 'Chest',
      equipment: 'Cable',
      mechanics: 'isolation',
      force: 'push',
      plane: 'horizontal',
      defaultRestSeconds: 60,
      isCustom: true,
      category: 'hypertrophy',
      modality: 'cable',
      cnsScore: 2,
      recoveryImpact: 2,
      loggingMetric: 'weight_reps',
      supportsWeightedBodyweight: false,
      isReviewed: true,
    ),
  ];

  testWidgets('ExerciseLibraryView renders search, filters and exercise list', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          exerciseSearchProvider.overrideWith((ref, filter) {
            var list = sampleExercises;
            if (filter.query != null && filter.query!.isNotEmpty) {
              list = list
                  .where(
                    (e) => e.name.toLowerCase().contains(
                      filter.query!.toLowerCase(),
                    ),
                  )
                  .toList();
            }
            if (filter.category != null) {
              list = list
                  .where(
                    (e) =>
                        e.primaryMuscle.toLowerCase() ==
                        filter.category!.toLowerCase(),
                  )
                  .toList();
            }
            return AsyncValue.data(list);
          }),
          exerciseAffinityProvider.overrideWith(
            (ref, exerciseId) => Stream.value(ExerciseAffinity.okay),
          ),
        ],
        child: const MaterialApp(home: ExerciseLibraryView()),
      ),
    );

    await tester.pumpAndSettle();

    // Verify title and search bar
    expect(find.text('Exercise Library'), findsOneWidget);
    expect(
      find.widgetWithText(
        TextField,
        'Search exercises by name, muscle, equipment…',
      ),
      findsOneWidget,
    );

    // Verify filter chips exist
    expect(find.widgetWithText(FilterChip, 'All'), findsOneWidget);
    expect(find.widgetWithText(FilterChip, 'Custom'), findsOneWidget);
    expect(find.widgetWithText(FilterChip, 'Chest'), findsOneWidget);
    expect(find.widgetWithText(FilterChip, 'Biceps'), findsOneWidget);

    // Verify exercise items
    expect(find.text('Barbell Bench Press'), findsOneWidget);
    expect(find.text('Incline Dumbbell Curl'), findsOneWidget);
    expect(find.text('Custom Cable Fly'), findsOneWidget);
    expect(find.text('Custom'), findsNWidgets(2)); // Chip + item 3 badge
    expect(find.text('3 exercises'), findsOneWidget);
    expect(find.text('Okay'), findsNWidgets(3));
  });

  testWidgets(
    'ExerciseLibraryView filters custom exercises when chip selected',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            exerciseSearchProvider.overrideWith((ref, filter) {
              return AsyncValue.data(sampleExercises);
            }),
            exerciseAffinityProvider.overrideWith(
              (ref, exerciseId) => Stream.value(ExerciseAffinity.okay),
            ),
          ],
          child: const MaterialApp(home: ExerciseLibraryView()),
        ),
      );

      await tester.pumpAndSettle();

      // Tap the "Custom" filter chip
      await tester.tap(find.widgetWithText(FilterChip, 'Custom'));
      await tester.pumpAndSettle();

      // Now only custom exercise should appear in the list
      expect(find.text('Custom Cable Fly'), findsOneWidget);
      expect(find.text('Barbell Bench Press'), findsNothing);
      expect(find.text('Incline Dumbbell Curl'), findsNothing);
      expect(find.text('1 exercise'), findsOneWidget);
    },
  );
}
