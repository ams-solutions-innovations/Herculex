import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/design_system/theme/app_theme.dart';
import 'package:herculex/features/programs/presentation/sheets/exercise_replacement_sheet.dart';
import 'package:herculex/features/programs/presentation/views/block_detail_view.dart';
import 'package:herculex/features/workouts/application/workouts_providers.dart';

import 'support/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() async {
    db = await openTestDatabase();
  });

  tearDown(() => db.close());

  Future<int> exercise(String name) => db
      .into(db.exerciseCatalog)
      .insert(
        ExerciseCatalogCompanion.insert(
          name: name,
          primaryMuscle: 'Quads',
          equipment: 'barbell',
          mechanics: 'compound',
          force: 'push',
          plane: 'axial',
        ),
      );

  /// Program with 4 weeks, one day per week sharing the same slot label, and
  /// a `main`-role slot whose rotation assignments produce A,A,B,B across
  /// weeks 0-3 — the same rotating-fixture shape as
  /// `test/program_exercise_replacement_scope_test.dart`.
  Future<
    ({
      int programId,
      int slotId,
      List<int> dayIds,
      List<int> rowIds,
      int exerciseA,
      int exerciseB,
    })
  >
  seedRotatingProgram() async {
    final exerciseA = await exercise('Exercise A');
    final exerciseB = await exercise('Exercise B');
    final programId = await db
        .into(db.programs)
        .insert(
          ProgramsCompanion.insert(name: 'Wave Test', weeks: const Value(4)),
        );
    final slotId = await db
        .into(db.programExerciseSlots)
        .insert(
          ProgramExerciseSlotsCompanion.insert(
            programId: programId,
            slotKey: 'main-lift',
            daySlotLabel: 'Day A',
            orderIndex: 0,
            role: const Value('main'),
          ),
        );
    final dayIds = <int>[];
    final rowIds = <int>[];
    for (var weekIndex = 0; weekIndex < 4; weekIndex++) {
      final weekId = await db
          .into(db.programWeeks)
          .insert(
            ProgramWeeksCompanion.insert(
              programId: programId,
              weekIndex: weekIndex,
            ),
          );
      final dayId = await db
          .into(db.programDays)
          .insert(
            ProgramDaysCompanion.insert(
              programWeekId: weekId,
              dayOfWeek: 1,
              name: 'Day A',
              slotLabel: const Value('Day A'),
            ),
          );
      dayIds.add(dayId);
      final exerciseId = weekIndex < 2 ? exerciseA : exerciseB;
      rowIds.add(
        await db
            .into(db.programDayExercises)
            .insert(
              ProgramDayExercisesCompanion.insert(
                programDayId: dayId,
                exerciseId: exerciseId,
                orderIndex: 0,
                programExerciseSlotId: Value(slotId),
              ),
            ),
      );
      await db
          .into(db.rotationAssignments)
          .insert(
            RotationAssignmentsCompanion.insert(
              slotId: slotId,
              exerciseId: exerciseId,
              weekIndex: weekIndex,
              reason: 'Planned rotation',
            ),
          );
    }
    return (
      programId: programId,
      slotId: slotId,
      dayIds: dayIds,
      rowIds: rowIds,
      exerciseA: exerciseA,
      exerciseB: exerciseB,
    );
  }

  /// A block whose slot has no rotation at all (single exercise, all weeks
  /// share the same assignment) — used to prove the wave-strip line still
  /// renders a valid single-wave label rather than being omitted, since
  /// `WaveLabel.compute` always resolves for a fully-assigned slot.
  Future<int> seedSingleWaveProgram() async {
    final exerciseId = await exercise('Solo Exercise');
    final programId = await db
        .into(db.programs)
        .insert(
          ProgramsCompanion.insert(name: 'Solo Test', weeks: const Value(4)),
        );
    final slotId = await db
        .into(db.programExerciseSlots)
        .insert(
          ProgramExerciseSlotsCompanion.insert(
            programId: programId,
            slotKey: 'main-lift',
            daySlotLabel: 'Day A',
            orderIndex: 0,
            role: const Value('main'),
          ),
        );
    for (var weekIndex = 0; weekIndex < 4; weekIndex++) {
      final weekId = await db
          .into(db.programWeeks)
          .insert(
            ProgramWeeksCompanion.insert(
              programId: programId,
              weekIndex: weekIndex,
            ),
          );
      final dayId = await db
          .into(db.programDays)
          .insert(
            ProgramDaysCompanion.insert(
              programWeekId: weekId,
              dayOfWeek: 1,
              name: 'Day A',
              slotLabel: const Value('Day A'),
            ),
          );
      await db
          .into(db.programDayExercises)
          .insert(
            ProgramDayExercisesCompanion.insert(
              programDayId: dayId,
              exerciseId: exerciseId,
              orderIndex: 0,
              programExerciseSlotId: Value(slotId),
            ),
          );
      await db
          .into(db.rotationAssignments)
          .insert(
            RotationAssignmentsCompanion.insert(
              slotId: slotId,
              exerciseId: exerciseId,
              weekIndex: weekIndex,
              reason: 'Planned rotation',
            ),
          );
    }
    return programId;
  }

  Widget harness(int programId) => ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      recentExerciseIdsProvider.overrideWith((ref) async => <int>{}),
    ],
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      home: BlockDetailView(programId: programId),
    ),
  );

  testWidgets(
    'shows exactly one active week behind a Week dropdown, not a scrollable stack',
    (tester) async {
      final fixture = await seedRotatingProgram();

      await tester.pumpWidget(harness(fixture.programId));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump();

      expect(find.text('Week 1 of 4'), findsOneWidget);
      // Only one week's volume slider is ever mounted — the old all-weeks
      // scrollable stack would have rendered four.
      expect(find.byType(Slider), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 50));
    },
  );

  testWidgets(
    'the Week dropdown label and the wave-strip caption are separate Text widgets (D-05)',
    (tester) async {
      final fixture = await seedRotatingProgram();

      await tester.pumpWidget(harness(fixture.programId));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump();

      final weekFinder = find.text('Week 1 of 4');
      final waveFinder = find.textContaining('Exercise wave');
      expect(weekFinder, findsOneWidget);
      expect(waveFinder, findsOneWidget);

      final weekText = tester.widget<Text>(weekFinder).data!;
      final waveText = tester.widget<Text>(waveFinder).data!;
      expect(weekText.contains(waveText), isFalse);
      expect(waveText.contains(weekText), isFalse);
      expect(waveText, 'Exercise wave 1 of 2 · Weeks 1–2');

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 50));
    },
  );

  testWidgets(
    'selecting week 3 from the dropdown updates the wave-strip label',
    (tester) async {
      final fixture = await seedRotatingProgram();

      await tester.pumpWidget(harness(fixture.programId));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump();

      await tester.tap(find.text('Week 1 of 4'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Week 3 of 4').last);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Exercise wave 2 of 2 · Weeks 3–4'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 50));
    },
  );

  testWidgets(
    'a block with no rotation still shows a valid single-wave label',
    (tester) async {
      final programId = await seedSingleWaveProgram();

      await tester.pumpWidget(harness(programId));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump();

      expect(find.text('Exercise wave 1 of 1 · Weeks 1–4'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 50));
    },
  );

  testWidgets(
    'the day-level link icon and the per-exercise replace icon are both present (D-03)',
    (tester) async {
      final fixture = await seedRotatingProgram();

      await tester.pumpWidget(harness(fixture.programId));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump();

      expect(find.byIcon(Icons.link_rounded), findsOneWidget);
      expect(find.byTooltip('Replace this exercise'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 50));
    },
  );

  testWidgets(
    'replacing an exercise opens the shared sheet and updates the live exercise list',
    (tester) async {
      final fixture = await seedRotatingProgram();
      final replacement = await exercise('Replacement Exercise');

      await tester.pumpWidget(harness(fixture.programId));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump();

      expect(find.text('Exercise A'), findsOneWidget);

      await tester.ensureVisible(find.byTooltip('Replace this exercise'));
      await tester.pump();
      await tester.tap(find.byTooltip('Replace this exercise'));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(ExerciseReplacementSheet), findsOneWidget);

      // The seeded catalog has hundreds of pre-existing exercises that may
      // out-rank a freshly-created one, pushing it past the sheet's lazily
      // built list window — search narrows to just this candidate, exactly
      // as a real user would.
      await tester.enterText(find.byType(TextField), 'Replacement Exercise');
      await tester.pump();

      final resultTile = find.widgetWithText(ListTile, 'Replacement Exercise');
      expect(resultTile, findsOneWidget);

      await tester.tap(resultTile);
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(ExerciseReplacementSheet), findsNothing);
      expect(find.text('Replacement Exercise'), findsOneWidget);
      expect(find.text('Exercise A'), findsNothing);
      expect(replacement, isPositive);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 50));
    },
  );

  testWidgets(
    'replacing the anchor slot exercise refreshes the wave-strip label (no stale reading)',
    (tester) async {
      final fixture = await seedRotatingProgram();
      await exercise('Anchor Replacement');

      await tester.pumpWidget(harness(fixture.programId));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump();

      expect(find.text('Exercise wave 1 of 2 · Weeks 1–2'), findsOneWidget);

      await tester.ensureVisible(find.byTooltip('Replace this exercise'));
      await tester.pump();
      await tester.tap(find.byTooltip('Replace this exercise'));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      // Select "Entire block" so the replacement actually changes the wave
      // boundaries (the sheet's default "This wave" scope would replace the
      // whole existing weeks-1-2 wave together, leaving the label's week
      // range and count identical before and after — not a useful proof of
      // "no stale reading").
      await tester.tap(find.text('Entire block'));
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'Anchor Replacement');
      await tester.pump();

      await tester.tap(find.widgetWithText(ListTile, 'Anchor Replacement'));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(ExerciseReplacementSheet), findsNothing);

      // "Entire block" replaces every week's assignment with the same
      // exercise, collapsing the anchor slot to a single wave spanning the
      // whole program — a clearly different reading than the original
      // "1 of 2 · Weeks 1–2", proving the invalidation refreshed it.
      expect(find.text('Exercise wave 1 of 1 · Weeks 1–4'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 50));
    },
  );
}
