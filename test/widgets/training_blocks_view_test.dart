import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/programs/data/programs_repository.dart';
import 'package:herculex/features/programs/domain/split_template.dart';
import 'package:herculex/features/programs/presentation/training_blocks_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Smoke coverage for the reworked Blocks tab. The feature previously had no
/// widget tests at all, so these assert the things a silent render failure or a
/// regression to the old placeholder UI would break.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late SharedPreferences prefs;
  late ProgramsRepository repo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.customStatement('PRAGMA foreign_keys = ON');
    repo = ProgramsRepository(db);
  });

  tearDown(() => db.close());

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          appDatabaseProvider.overrideWithValue(db),
        ],
        child: const MaterialApp(home: TrainingBlocksView()),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Tears the tree down inside the test body. Disposing the ProviderScope
  /// cancels drift's watch streams, which schedule a zero-duration cleanup
  /// timer — left to the framework's own teardown it trips the "timer still
  /// pending" assertion.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    // The cleanup timer is scheduled while this frame's tree is finalized, so
    // it needs a further elapsed frame to actually fire.
    await tester.pump(const Duration(milliseconds: 10));
  }

  Future<int> buildBlock({int? templateId}) {
    return repo.createProgramFromSplit(
      name: 'Test PPL',
      weeks: 4,
      plan: SplitTemplates.generate(type: SplitType.ppl, daysPerWeek: 3),
      startDate: DateTime.now(),
      templateIdsBySlot: {0: templateId, 1: templateId, 2: templateId},
    );
  }

  testWidgets('with no block it offers to build one', (tester) async {
    await pump(tester);

    expect(find.text('No training block yet'), findsOneWidget);
    expect(find.text('Build a block'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('an active block renders its name, split and week counter',
      (tester) async {
    await buildBlock();
    await pump(tester);

    expect(find.text('Test PPL'), findsOneWidget);
    expect(
      find.textContaining('Push / Pull / Legs'),
      findsOneWidget,
      reason: 'the header should name the split',
    );
    expect(find.textContaining('of 4'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('the week board shows real day names, not placeholders',
      (tester) async {
    await buildBlock();
    await pump(tester);

    // Real slot labels from the split generator — the old view hardcoded
    // every row's title to "Training Session".
    expect(find.text('Push'), findsOneWidget);
    expect(find.text('Pull'), findsOneWidget);
    expect(find.text('Legs'), findsOneWidget);
    expect(find.text('Training Session'), findsNothing);

    // All seven weekdays are laid out, with rest days marked as such.
    expect(find.text('Monday'), findsOneWidget);
    expect(find.text('Sunday'), findsOneWidget);
    expect(find.text('Rest day'), findsWidgets);

    await unmount(tester);
  });

  testWidgets('a template-less session is flagged as empty', (tester) async {
    await buildBlock();
    await pump(tester);

    expect(find.textContaining('No exercises yet'), findsWidgets);

    await unmount(tester);
  });

  testWidgets('a linked template shows its name and exercise count',
      (tester) async {
    final templateId = await db
        .into(db.workoutTemplates)
        .insert(WorkoutTemplatesCompanion.insert(name: 'Heavy Push'));
    final exerciseId = await db.into(db.exerciseCatalog).insert(
          ExerciseCatalogCompanion.insert(
            name: 'Test Bench',
            primaryMuscle: 'Chest',
            equipment: 'Barbell',
            mechanics: 'compound',
            force: 'push',
            plane: 'horizontal',
          ),
        );
    await db.into(db.templateExercises).insert(
          TemplateExercisesCompanion.insert(
            templateId: templateId,
            exerciseId: exerciseId,
            orderIndex: 0,
          ),
        );

    await buildBlock(templateId: templateId);
    await pump(tester);

    expect(find.textContaining('Heavy Push'), findsWidgets);
    expect(find.textContaining('1 exercise'), findsWidgets);
    expect(find.textContaining('No exercises yet'), findsNothing);

    await unmount(tester);
  });

  testWidgets('the Week/Month toggle switches to the calendar grid',
      (tester) async {
    await buildBlock();
    await pump(tester);

    // The dead 1/3/6-month filter is gone.
    expect(find.text('1 Month'), findsNothing);
    expect(find.text('3 Months'), findsNothing);

    expect(find.text('Week'), findsOneWidget);
    await tester.tap(find.text('Month'));
    await tester.pumpAndSettle();

    // Month grid renders its weekday header row rather than the week board.
    expect(find.text('Monday'), findsNothing);
    expect(find.byType(GridView), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('the view mode is remembered across rebuilds', (tester) async {
    await buildBlock();
    await pump(tester);

    await tester.tap(find.text('Month'));
    await tester.pumpAndSettle();
    expect(prefs.getString('blocks_view_mode'), 'month');

    await pump(tester);
    expect(find.byType(GridView), findsOneWidget);

    await unmount(tester);
  });
}
