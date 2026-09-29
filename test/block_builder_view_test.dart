import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/design_system/components/components.dart';
import 'package:herculex/features/programs/presentation/views/block_builder_view.dart';
import 'package:herculex/features/programs/presentation/views/program_review_view.dart';

import 'support/test_database.dart';

/// Pumps [BlockBuilderView] with the given in-memory [db] wired in, at the
/// same large logical viewport the rest of this file uses so every step's
/// content lays out without needing to scroll to find a tap target.
Future<void> _pumpBuilder(WidgetTester tester, AppDatabase db) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: const MaterialApp(
        home: BlockBuilderView(autoRecommendExperience: false),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

/// Taps the pinned "Continue" footer button and settles the resulting step
/// transition, mirroring the tap/pump/pump(100ms) pattern already used by
/// every other test in this file.
Future<void> _continue(WidgetTester tester) async {
  await tester.tap(find.text('Continue'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

/// Taps "Create block" and pumps enough frames for the async `_create()` to
/// run to completion (either the caught-StateError SnackBar path, or a
/// successful navigation to `ProgramReviewView`).
Future<void> _createBlock(WidgetTester tester) async {
  await tester.tap(find.text('Create block'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets('builder 6-step multi-screen flow', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: BlockBuilderView(autoRecommendExperience: false),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Step 1: Build mode & muscle priorities
    expect(find.text('Build it for me'), findsOneWidget);
    expect(find.text('Guide me'), findsOneWidget);
    expect(find.text('Start from scratch'), findsOneWidget);
    expect(find.text('MUSCLE PRIORITY'), findsOneWidget);
    expect(find.text('Dream Physique priorities'), findsOneWidget);
    expect(find.text('Muscle priorities & weekly sets'), findsOneWidget);

    // Verify footer does NOT contain 'Back' button
    expect(find.text('Back'), findsNothing);

    // Tap Continue -> Step 2: Exercise pools
    await tester.tap(find.text('Continue'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Exercise pools'), findsOneWidget);
    expect(find.text('Exercise preferences'), findsOneWidget);
    expect(find.text('Available equipment'), findsOneWidget);
    expect(find.text('Review'), findsOneWidget);
    expect(find.text('Configure'), findsOneWidget);

    // Tap Continue -> Step 3: Training parameters
    await tester.tap(find.text('Continue'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Training parameters'), findsOneWidget);
    expect(find.text('Target workout time'), findsOneWidget);
    expect(find.text('Primary lift specialization'), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget);
    expect(find.text('PERIODIZATION'), findsOneWidget);

    // Tap Continue -> Step 4: Split
    await tester.tap(find.text('Continue'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Split'), findsOneWidget);
    expect(find.text('Full Body Linear'), findsOneWidget);
    expect(find.text('Push / Pull / Legs'), findsOneWidget);
    expect(find.text('Upper / Lower'), findsOneWidget);

    // Tap Continue -> Step 5: Workout content & methods
    await tester.tap(find.text('Continue'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Workout content & methods'), findsOneWidget);
    expect(find.text('WORKOUT TEMPLATES'), findsOneWidget);
    expect(find.text('Program rhythm'), findsOneWidget);
    expect(find.text('MAIN EXERCISE METHOD'), findsOneWidget);

    // Tap Continue -> Step 6: Schedule & Launch
    await tester.tap(find.text('Continue'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Schedule'), findsOneWidget);
    expect(find.text('Start date'), findsOneWidget);
    expect(find.text('Create block'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('step 3 controls: slider, info dialog, and specialization modal', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: BlockBuilderView(autoRecommendExperience: false),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Advance from Step 1 to Step 3
    await tester.tap(find.text('Continue')); // -> Step 2
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('Continue')); // -> Step 3
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Verify slider and initial duration
    expect(find.text('60 min'), findsWidgets);
    expect(find.byType(Slider), findsOneWidget);

    // Verify Auto warm-up sets toggle and info dialog
    expect(find.text('Auto warm-up sets'), findsOneWidget);
    expect(find.byIcon(Icons.local_fire_department_rounded), findsOneWidget);
    await tester.tap(find.byTooltip('Auto warm-up sets info'));
    await tester.pumpAndSettle();
    expect(find.text('Auto Warm-up Sets'), findsOneWidget);
    expect(find.text('Got it'), findsOneWidget);
    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();

    // Verify Time-saving sets toggle and info dialog
    expect(find.text('Time-saving sets'), findsOneWidget);
    expect(find.byIcon(Icons.bolt_rounded), findsOneWidget);
    await tester.tap(find.byTooltip('Time-saving sets info'));
    await tester.pumpAndSettle();
    expect(find.text('Time-saving Sets'), findsOneWidget);
    expect(find.text('Got it'), findsOneWidget);
    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();

    // Verify specialization info dialog
    expect(find.byIcon(Icons.help_outline_rounded), findsWidgets);
    await tester.tap(find.byTooltip('Specialization info'));
    await tester.pumpAndSettle();

    expect(find.text('Lift Specialization'), findsOneWidget);
    expect(find.text('Got it'), findsOneWidget);
    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();

    // Toggle specialization ON opens configuration modal
    await tester.tap(find.byKey(const ValueKey('specialization-switch')));
    await tester.pumpAndSettle();

    expect(find.text('Target lift'), findsOneWidget);
    expect(find.text('Where does the lift slow down?'), findsOneWidget);
    expect(find.text('Apply'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);

    // Enter load and apply
    await tester.enterText(find.widgetWithText(TextField, 'Current load (kg)'), '100');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    // Verify specialization summary card appears
    expect(find.text('Squat Specialization'), findsOneWidget);
    expect(find.textContaining('Current: 100 kg'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('step 1 muscle priorities card interaction', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: BlockBuilderView(autoRecommendExperience: false),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Dream Physique priorities'), findsOneWidget);
    expect(find.text('Muscle priorities & weekly sets'), findsOneWidget);

    // Tap manual muscle priorities card opens the sheet
    await tester.tap(find.text('Set myself'));
    await tester.pumpAndSettle();

    expect(find.text('Set my muscle priorities'), findsOneWidget);
    await tester.tap(find.text('Chest'));
    await tester.pumpAndSettle();

    expect(find.text('Use these priorities'), findsOneWidget);
    await tester.tap(find.text('Use these priorities'));
    await tester.pumpAndSettle();

    // Now Manual priorities card has 'Active' status and 'Edit' button
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('step 3 luxury picker tiles open HxSheet modals and update values', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: BlockBuilderView(autoRecommendExperience: false),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Advance to Step 3
    await tester.tap(find.text('Continue')); // -> Step 2
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('Continue')); // -> Step 3
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Initial state: default goal is Hypertrophy
    expect(find.text('Hypertrophy'), findsOneWidget);

    // Tap Primary Goal tile to open bottom sheet
    await tester.tap(find.byKey(const ValueKey('picker-goal')));
    await tester.pumpAndSettle();

    // Verify sheet opened
    expect(find.text('Primary Goal'), findsOneWidget);
    expect(find.text('Strength'), findsOneWidget);
    expect(find.text('Powerbuilding'), findsOneWidget);
    expect(find.text('Athletic performance'), findsOneWidget);

    // Select 'Strength'
    await tester.tap(find.text('Strength'));
    await tester.pumpAndSettle();

    // Sheet dismissed, Strength is now selected
    expect(find.text('Primary Goal'), findsNothing);
    expect(find.text('Strength'), findsOneWidget);

    // Tap Training Experience tile
    await tester.tap(find.byKey(const ValueKey('picker-experience')));
    await tester.pumpAndSettle();

    // Verify Experience sheet
    expect(
      find.descendant(of: find.byType(HxSheet), matching: find.text('Novice')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: find.byType(HxSheet), matching: find.text('Intermediate')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: find.byType(HxSheet), matching: find.text('Advanced')),
      findsOneWidget,
    );

    // Select 'Advanced'
    await tester.tap(
      find.descendant(of: find.byType(HxSheet), matching: find.text('Advanced')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Advanced'), findsOneWidget);

    // Tap Block Length tile
    await tester.tap(find.byKey(const ValueKey('picker-length')));
    await tester.pumpAndSettle();

    // Verify Block Length sheet
    expect(find.text('Block Length'), findsOneWidget);
    expect(
      find.descendant(of: find.byType(HxSheet), matching: find.text('12 weeks')),
      findsOneWidget,
    );

    // Select '12 weeks'
    await tester.tap(
      find.descendant(of: find.byType(HxSheet), matching: find.text('12 weeks')),
    );
    await tester.pumpAndSettle();

    expect(find.text('12 weeks'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  });

  // D-07 characterization: _create()'s two inline guardrail StateError
  // throws (Max-Effort-per-week > 2, and 6-day-PPL + Max Effort) are pinned
  // here BEFORE plan 27-08 extracts them into
  // ProgramGuardrails.validateConfiguration(), so a message-text or
  // trigger-condition change during that refactor is caught immediately.
  // Both throws are gated on `_buildMode != ProgramBuildMode.manual`, so the
  // manual-mode cases assert the opposite: no throw, successful creation.
  group('D-07 characterization: _create() inline guardrail throws', () {
    late AppDatabase db;

    setUp(() async {
      db = await openTestDatabase();
    });

    tearDown(() => db.close());

    const maxEffortPerWeekMessage =
        'A Smart program can use at most two Max Effort patterns per week.';
    const sixDayPplMessage =
        'A six-day PPL would create three Max Effort days. Use per-slot Max '
        'Effort or choose a Conjugate 3–4 day structure.';

    /// Drives Step 1 (mode) -> Step 4 (split) with an A/B/C split (3 distinct
    /// day slots, not PPL) so Step 5 offers exactly 3 "Max Effort" tap
    /// targets, one per slot, without also tripping the 6-day-PPL condition.
    Future<void> selectModeAndAbcSplit(
      WidgetTester tester,
      String modeLabel,
    ) async {
      await tester.tap(find.text(modeLabel));
      await tester.pump();
      await _continue(tester); // Step 1 -> Step 2 (exercise pools)
      await _continue(tester); // Step 2 -> Step 3 (training parameters)
      await _continue(tester); // Step 3 -> Step 4 (split)

      await tester.tap(find.text('A / B / C'));
      await tester.pump();
      await _continue(tester); // Step 4 -> Step 5 (content & methods)
    }

    /// Drives Step 1 (mode) -> Step 5 with a 6-day Push/Pull/Legs split and
    /// the Max Effort periodization model selected, leaving every day's main
    /// exercise method at its Auto default so only the split+model condition
    /// can trip, never the per-day Max-Effort-count condition.
    Future<void> selectModeAndSixDayPplMaxEffort(
      WidgetTester tester,
      String modeLabel,
    ) async {
      await tester.tap(find.text(modeLabel));
      await tester.pump();
      await _continue(tester); // Step 1 -> Step 2 (exercise pools)
      await _continue(tester); // Step 2 -> Step 3 (training parameters)

      await tester.tap(find.text('Max Effort — Westside (Conjugate)'));
      await tester.pump();
      await _continue(tester); // Step 3 -> Step 4 (split)

      await tester.tap(find.text('Push / Pull / Legs'));
      await tester.pump();
      await _continue(tester); // Step 4 -> Step 5 (content & methods)
    }

    testWidgets('smart mode: >2 Max Effort days throws and shows the '
        'per-week message', (tester) async {
      await _pumpBuilder(tester, db);
      await selectModeAndAbcSplit(tester, 'Build it for me');

      // Select "Max Effort" as the main exercise method for all 3 slots
      // (A, B, C) - one "Max Effort" choice chip renders per slot card.
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.text('Max Effort').at(i));
        await tester.pump();
      }

      await _continue(tester); // Step 5 -> Step 6 (schedule)
      await _createBlock(tester);

      expect(find.textContaining(maxEffortPerWeekMessage), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 10));
    });

    testWidgets('smart mode: 6-day PPL + Max Effort throws and shows the '
        'PPL message', (tester) async {
      await _pumpBuilder(tester, db);
      await selectModeAndSixDayPplMaxEffort(tester, 'Build it for me');

      await _continue(tester); // Step 5 -> Step 6 (schedule)
      await _createBlock(tester);

      expect(find.textContaining(sixDayPplMessage), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 10));
    });

    testWidgets('guided mode: >2 Max Effort days throws and shows the '
        'per-week message', (tester) async {
      await _pumpBuilder(tester, db);
      await selectModeAndAbcSplit(tester, 'Guide me');

      for (var i = 0; i < 3; i++) {
        await tester.tap(find.text('Max Effort').at(i));
        await tester.pump();
      }

      await _continue(tester); // Step 5 -> Step 6 (schedule)
      await _createBlock(tester);

      expect(find.textContaining(maxEffortPerWeekMessage), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 10));
    });

    testWidgets('guided mode: 6-day PPL + Max Effort throws and shows the '
        'PPL message', (tester) async {
      await _pumpBuilder(tester, db);
      await selectModeAndSixDayPplMaxEffort(tester, 'Guide me');

      await _continue(tester); // Step 5 -> Step 6 (schedule)
      await _createBlock(tester);

      expect(find.textContaining(sixDayPplMessage), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 10));
    });

    testWidgets(
      'manual mode: >2 Max Effort days does NOT throw - manual is exempt '
      'and the block is created successfully',
      (tester) async {
        await _pumpBuilder(tester, db);
        await selectModeAndAbcSplit(tester, 'Start from scratch');

        for (var i = 0; i < 3; i++) {
          await tester.tap(find.text('Max Effort').at(i));
          await tester.pump();
        }

        await _continue(tester); // Step 5 -> Step 6 (schedule)
        await _createBlock(tester);
        await tester.pumpAndSettle();

        expect(find.textContaining('Could not create the block'), findsNothing);
        expect(find.byType(ProgramReviewView), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 10));
      },
    );

    testWidgets(
      'manual mode: 6-day PPL + Max Effort does NOT throw - manual is '
      'exempt and the block is created successfully',
      (tester) async {
        await _pumpBuilder(tester, db);
        await selectModeAndSixDayPplMaxEffort(tester, 'Start from scratch');

        await _continue(tester); // Step 5 -> Step 6 (schedule)
        await _createBlock(tester);
        await tester.pumpAndSettle();

        expect(find.textContaining('Could not create the block'), findsNothing);
        expect(find.byType(ProgramReviewView), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 10));
      },
    );
  });
}
