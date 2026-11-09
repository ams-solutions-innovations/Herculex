import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/data/local/exercise_importer.dart';
import 'package:herculex/design_system/theme/app_theme.dart';
import 'package:herculex/features/programs/data/programs_repository.dart';
import 'package:herculex/features/programs/data/smart_program_planner.dart';
import 'package:herculex/features/programs/domain/programming_models.dart';
import 'package:herculex/features/programs/domain/split_template.dart';
import 'package:herculex/features/programs/presentation/views/block_builder_view.dart';
import 'package:herculex/features/programs/presentation/views/program_review_view.dart';
import 'package:herculex/features/workouts/application/workouts_providers.dart';

import '../../support/test_database.dart';

Future<void> _disposeTree(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 10));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('builder step 5', () {
    late AppDatabase db;
    setUp(() async => db = await openTestDatabase());
    tearDown(() => db.close());

    Future<void> openStep5(WidgetTester tester) async {
      // Wide because the test font's square glyphs overflow a phone-width row
      // that real text fits; the assertion is about column alignment.
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appDatabaseProvider.overrideWithValue(db)],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: BlockBuilderView(autoRecommendExperience: false),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Guide me'));
      await tester.pump();
      for (var step = 1; step < 5; step++) {
        await tester.tap(find.text('Continue'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    testWidgets('every method card spans the column', (tester) async {
      await openStep5(tester);

      for (final day in const ['Upper A', 'Lower A', 'Upper B', 'Lower B']) {
        final rect = tester.getRect(find.byKey(ValueKey('main-method-$day')));
        expect(rect.left, 20, reason: day);
        expect(rect.right, 1060, reason: day);
      }
      expect(tester.takeException(), isNull);

      await _disposeTree(tester);
    });

    testWidgets('a day gets one picker row, and the sheet names the pyramid', (
      tester,
    ) async {
      await openStep5(tester);

      expect(find.text('Double Progression'), findsNothing);
      final tile = find.byKey(const ValueKey('main-method-Upper A'));
      await tester.ensureVisible(tile);
      await tester.pumpAndSettle();
      await tester.tap(tile);
      await tester.pumpAndSettle();

      expect(find.text('Upper A · main exercise'), findsOneWidget);
      expect(find.text(SlotTrainingMethod.pyramidUp.label), findsOneWidget);
      expect(
        find.text(SlotTrainingMethod.reversePyramid.description),
        findsOneWidget,
      );

      await _disposeTree(tester);
    });

    testWidgets('rotation starts off, with no Auto choice', (tester) async {
      await openStep5(tester);

      expect(find.text('Off'), findsOneWidget);
      expect(find.text('Every 2 weeks'), findsOneWidget);
      expect(find.text('Westside default'), findsNothing);
      expect(find.textContaining('The same exercises for all'), findsOneWidget);

      await _disposeTree(tester);
    });

    testWidgets('a novice sees Intensity with the reason it is off', (
      tester,
    ) async {
      await openStep5(tester);

      expect(find.text('Intensity'), findsOneWidget);
      expect(
        find.textContaining('Available from intermediate'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Intensity'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Intensity'));
      await tester.pump();
      // Still explaining rather than offering the prescription.
      expect(
        find.textContaining('Available from intermediate'),
        findsOneWidget,
      );

      await _disposeTree(tester);
    });
  });

  group('review screen', () {
    late AppDatabase db;
    setUp(() async {
      db = await openTestDatabase();
      await ExerciseImporter.runFromJson(
        db,
        File('assets/data/exercises.json').readAsStringSync(),
        movementsJson: File('assets/data/movements.json').readAsStringSync(),
        programmingMetadataJson: File(
          'assets/data/exercise_programming_metadata.json',
        ).readAsStringSync(),
      );
    });
    tearDown(() => db.close());

    Future<int> build(SmartProgramConfiguration configuration) async {
      final id = await ProgramsRepository(db).createProgramFromSplit(
        name: 'Fixture',
        weeks: 4,
        plan: SplitTemplates.generate(
          type: SplitType.upperLower,
          daysPerWeek: 4,
          distinctRepeatedDays: true,
        ),
        startDate: DateTime(2026, 9, 7),
        periodizationModel: 'linear',
        buildMode: ProgramBuildMode.guided,
        trainingGoal: configuration.goal,
        experienceLevel: configuration.experience,
      );
      await SmartProgramPlanner(db).populate(id, configuration);
      await (db.update(db.programs)..where((t) => t.id.equals(id))).write(
        const ProgramsCompanion(archived: Value(true)),
      );
      return id;
    }

    Future<void> open(WidgetTester tester, int programId) async {
      tester.view.physicalSize = const Size(600, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            recentExerciseIdsProvider.overrideWith((ref) async => <int>{}),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: ProgramReviewView(programId: programId),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('a reverse pyramid is named with its sets', (tester) async {
      final id = await tester.runAsync(
        () => build(
          const SmartProgramConfiguration(
            goal: TrainingGoal.hypertrophy,
            experience: ExperienceLevel.intermediate,
            mainMethodByDayLabel: {
              'Upper A': SlotTrainingMethod.reversePyramid,
              'Lower A': SlotTrainingMethod.pyramidUp,
            },
          ),
        ),
      );
      await open(tester, id!);

      expect(find.text('Reverse pyramid'), findsOneWidget);
      expect(find.text('Pyramid up'), findsOneWidget);
      expect(find.byIcon(Icons.trending_down_rounded), findsOneWidget);
      expect(find.byIcon(Icons.trending_up_rounded), findsOneWidget);
      expect(
        find.textContaining('1 × 4–6 → 1 × 6–8 → 1 × 8–10'),
        findsOneWidget,
      );

      await _disposeTree(tester);
    });

    testWidgets('intensity focus shows two hard sets and the warm-up', (
      tester,
    ) async {
      final id = await tester.runAsync(
        () => build(
          const SmartProgramConfiguration(
            goal: TrainingGoal.hypertrophy,
            experience: ExperienceLevel.intermediate,
            trainingFocus: TrainingFocus.intensity,
          ),
        ),
      );
      await open(tester, id!);

      expect(find.textContaining('2 × 4–6 · RPE 9+'), findsWidgets);
      expect(find.textContaining('warm-up ramp first'), findsWidgets);

      await _disposeTree(tester);
    });
  });
}
