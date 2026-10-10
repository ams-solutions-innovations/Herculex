import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/design_system/components/components.dart';
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

    // The chip row is gone: one filter pill opens a grouped sheet.
    expect(find.byType(FilterChip), findsNothing);
    expect(find.byKey(const ValueKey('exercise-library-filter')), findsOne);

    // Verify exercise items
    expect(find.text('Barbell Bench Press'), findsOneWidget);
    expect(find.text('Incline Dumbbell Curl'), findsOneWidget);
    expect(find.text('Custom Cable Fly'), findsOneWidget);
    expect(find.text('Custom'), findsOneWidget); // item 3 badge
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

      // Open the filter sheet and pick "Custom".
      await tester.tap(find.byKey(const ValueKey('exercise-library-filter')));
      await tester.pumpAndSettle();
      expect(find.text('Filter exercises'), findsOneWidget);
      await tester.tap(find.widgetWithText(HxTextPill, 'Custom'));
      await tester.pumpAndSettle();

      // Now only custom exercise should appear in the list
      expect(find.text('Filter exercises'), findsNothing);
      expect(find.text('Custom Cable Fly'), findsOneWidget);
      expect(find.text('Barbell Bench Press'), findsNothing);
      expect(find.text('Incline Dumbbell Curl'), findsNothing);
      expect(find.text('1 exercise'), findsOneWidget);

      // Clearing the filter brings everything back.
      await tester.tap(find.byTooltip('Clear filter'));
      await tester.pumpAndSettle();
      expect(find.text('3 exercises'), findsOneWidget);
    },
  );

  testWidgets('ExerciseLibraryView "Core lifts" shows only starred exercises', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          exerciseSearchProvider.overrideWith(
            (ref, filter) => AsyncValue.data(sampleExercises),
          ),
          exerciseAffinityProvider.overrideWith(
            (ref, exerciseId) => Stream.value(
              exerciseId == 1 ? ExerciseAffinity.core : ExerciseAffinity.okay,
            ),
          ),
          exerciseIdsWithAffinityProvider.overrideWith(
            (ref, affinity) =>
                Stream.value(affinity == ExerciseAffinity.core ? {1} : <int>{}),
          ),
        ],
        child: const MaterialApp(home: ExerciseLibraryView()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('exercise-library-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(HxTextPill, 'Core lifts'));
    await tester.pumpAndSettle();

    expect(find.text('Barbell Bench Press'), findsOneWidget);
    expect(find.text('Incline Dumbbell Curl'), findsNothing);
    expect(find.text('Custom Cable Fly'), findsNothing);
    expect(find.text('1 exercise'), findsOneWidget);
  });
}
