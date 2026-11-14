import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/workouts/data/templates_repository.dart';
import 'package:herculex/features/workouts/presentation/views/template_builder_view.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../support/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = await openTestDatabase();
  });

  tearDown(() => db.close());

  Future<int> findOrInsertExercise({
    required String name,
    required String primaryMuscle,
    required String mechanics,
    required String force,
    required String plane,
    required String movementPattern,
    required String equipment,
  }) async {
    final existing = await (db.select(
      db.exerciseCatalog,
    )..where((t) => t.name.equals(name))).get();
    if (existing.isNotEmpty) return existing.first.id;
    return db
        .into(db.exerciseCatalog)
        .insert(
          ExerciseCatalogCompanion.insert(
            name: name,
            primaryMuscle: primaryMuscle,
            equipment: equipment,
            mechanics: mechanics,
            force: force,
            plane: plane,
            movementPattern: Value(movementPattern),
          ),
        );
  }

  testWidgets(
    'TemplateBuilderView header places swap and delete side-by-side and Substitute opens biomechanical matcher',
    (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final revHyperId = await findOrInsertExercise(
        name: 'Reverse Hyperextension',
        primaryMuscle: 'Hamstrings',
        mechanics: 'compound',
        force: 'pull',
        plane: 'sagittal',
        movementPattern: 'hinge',
        equipment: 'Machine',
      );
      await findOrInsertExercise(
        name: 'Back Extension',
        primaryMuscle: 'Hamstrings',
        mechanics: 'compound',
        force: 'pull',
        plane: 'sagittal',
        movementPattern: 'hinge',
        equipment: 'Bodyweight',
      );

      final repo = TemplatesRepository(db);
      final template = await repo.createTemplate(name: 'Lower Day');
      await repo.addExerciseToTemplate(
        templateId: template.id,
        exerciseId: revHyperId,
        targetSets: 2,
      );

      final container = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: TemplateBuilderView(
              existing: template,
              returnsSelection: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Reverse Hyperextension'), findsOneWidget);
      expect(find.text('Sets: 2'), findsOneWidget);

      // Swap and delete icons are horizontally aligned on the same row.
      final swapTopLeft = tester.getTopLeft(
        find.byTooltip('Substitute exercise'),
      );
      final deleteTopLeft = tester.getTopLeft(
        find.byTooltip('Remove exercise'),
      );
      expect(swapTopLeft.dy, deleteTopLeft.dy);
      expect(swapTopLeft.dx, lessThan(deleteTopLeft.dx));

      // Tapping Substitute opens the biomechanical substitution sheet, not Add Exercise.
      await tester.tap(find.byTooltip('Substitute exercise'));
      await tester.pumpAndSettle();

      expect(find.text('Substitute Exercise'), findsOneWidget);
      expect(find.text('Suggested Biomechanical Matches'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('Add Exercise'),
        ),
        findsNothing,
      );
      expect(find.text('Back Extension'), findsOneWidget);

      await tester.ensureVisible(find.text('Back Extension'));
      await tester.tap(find.text('Back Extension'));
      await tester.pumpAndSettle();

      expect(find.text('Back Extension'), findsOneWidget);
      expect(find.text('Reverse Hyperextension'), findsNothing);
    },
  );
}
