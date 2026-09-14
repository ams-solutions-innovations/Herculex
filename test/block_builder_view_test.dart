import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/design_system/components/components.dart';
import 'package:herculex/features/programs/presentation/views/block_builder_view.dart';

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
}
