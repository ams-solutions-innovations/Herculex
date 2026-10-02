import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/design_system/components/components.dart';
import 'package:herculex/features/programs/data/herculex_ai_brief_service.dart';
import 'package:herculex/features/programs/domain/program_brief.dart';
import 'package:herculex/features/programs/domain/split_template.dart';
import 'package:herculex/features/programs/presentation/views/block_builder_view.dart';
import 'package:herculex/features/programs/presentation/views/program_review_view.dart';
import 'package:herculex/features/programs/presentation/widgets/ai_brief_rejection_banner.dart';
import 'package:herculex/services/ai/gemini_backend_service.dart';

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

/// Pumps [BlockBuilderView] with both [db] and a fake [GeminiBackend] wired
/// in, so Herculex AI's `generateBrief()` calls resolve against a canned
/// response/error instead of a real network call (27-11).
Future<void> _pumpBuilderWithBackend(
  WidgetTester tester,
  AppDatabase db,
  GeminiBackend backend,
) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        geminiBackendProvider.overrideWithValue(backend),
      ],
      child: const MaterialApp(
        home: BlockBuilderView(autoRecommendExperience: false),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

/// A minimal `GeminiBackend` fake whose only implemented method is
/// `generateProgramBrief` (configurable per test); every other method throws
/// `UnimplementedError`. Mirrors `_FakeGeminiBackend` in
/// `test/herculex_ai_brief_service_test.dart`.
class _FakeHerculexGeminiBackend implements GeminiBackend {
  _FakeHerculexGeminiBackend({this.result, this.error, this.delay});

  Map<String, dynamic>? result;
  Object? error;
  Duration? delay;
  int callCount = 0;

  static Map<String, dynamic> _defaultResult() => {
    'splitType': 'upper_lower',
    'periodizationModel': 'linear',
    'dayRoles': [
      {
        'dayIndex': 0,
        'role': 'intensity',
        'focus': 'Upper body heavy pressing',
        'rationale': 'Front-loads the week while recovery is freshest.',
      },
    ],
    'musclePriorities': [
      {
        'muscleId': 'chest',
        'priority': 'high',
        'confidence': 0.8,
        'rationale': 'Lagging relative to back.',
        'uncertainties': <String>[],
      },
    ],
    'phaseIntent': 'Build upper body symmetry ahead of the next block.',
  };

  @override
  Future<(Map<String, dynamic> result, Map<String, dynamic> provenance)>
  generateProgramBrief({
    required Map<String, dynamic> profileInputs,
    String? userNote,
  }) async {
    callCount++;
    if (delay != null) await Future<void>.delayed(delay!);
    if (error != null) throw error!;
    return (result ?? _defaultResult(), const <String, dynamic>{});
  }

  @override
  Future<Map<String, dynamic>> analyzeFoodPhoto({
    required List<int> imageBytes,
    required String mimeType,
    String? userNote,
  }) => throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> analyzeNutritionLabel({
    required List<int> imageBytes,
    required String mimeType,
    required String ocrText,
  }) => throw UnimplementedError();

  @override
  Future<String> identifyExercise({
    required List<int> imageBytes,
    required String mimeType,
  }) => throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> identifyExerciseDetailed({
    required List<int> imageBytes,
    required String mimeType,
  }) => throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> analyzeSupplementPhoto({
    required List<int> imageBytes,
    required String mimeType,
    String? userNote,
  }) => throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> analyzeBarcodeProduct({
    required List<int> imageBytes,
    required String mimeType,
    required String barcode,
    String? userNote,
  }) => throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> estimateBodyFat({
    required List<Map<String, dynamic>> images,
    Map<String, dynamic>? biometrics,
    String? userNote,
  }) => throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> analyzeDreamPhysique({
    required List<Map<String, dynamic>> currentImages,
    required List<Map<String, dynamic>> targetImages,
    Map<String, dynamic>? biometrics,
    String? userNote,
  }) => throw UnimplementedError();

  @override
  Future<Map<String, dynamic>> analyzeRamblerText({
    required String text,
    String? preferredMealKey,
  }) => throw UnimplementedError();
}

/// A [HerculexAiBriefService] whose `persistBrief()` always throws, so tests
/// can verify `_create()` tolerates a non-fatal persistence failure (27-13,
/// D-08, T-27-20) without needing to break the in-memory drift database
/// itself. `generateBrief()` and every other method are inherited unchanged
/// from the real service.
class _ThrowingPersistHerculexAiBriefService extends HerculexAiBriefService {
  _ThrowingPersistHerculexAiBriefService(super.backend, super.db, super.clock);

  @override
  Future<void> persistBrief({
    required int programId,
    required ProgramBrief brief,
    required Map<String, dynamic> provenance,
  }) {
    throw Exception('simulated persistBrief failure (27-13 test)');
  }
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

  testWidgets(
    'Weeks picker: no specialization active, tapping a value sets it exactly (regression)',
    (tester) async {
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

      await tester.tap(find.text('Continue')); // -> Step 2
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Continue')); // -> Step 3
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byKey(const ValueKey('picker-length')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('6 weeks'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Not enough time'), findsNothing);
      expect(find.text('6 weeks'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 10));
    },
  );

  testWidgets(
    'Weeks picker: specialization active, tapping a value shorter than the '
    'recommendation auto-adjusts and warns (D-08-D-10)',
    (tester) async {
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

      await tester.tap(find.text('Continue')); // -> Step 2
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Continue')); // -> Step 3
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byKey(const ValueKey('specialization-switch')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Current load (kg)'),
        '100',
      );
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      // Current 100 -> target 140 (default), novice (default experience):
      // a 40kg increase recommends 24 weeks. Tapping 4 weeks is a shortfall.
      await tester.tap(find.byKey(const ValueKey('picker-length')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('4 weeks'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.textContaining('Not enough time to progress safely'),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('picker-length')),
          matching: find.text('24 weeks'),
        ),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 10));
    },
  );

  testWidgets(
    'Weeks picker: specialization active, tapping a value at/above the '
    'recommendation sets it exactly with no warning',
    (tester) async {
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

      await tester.tap(find.text('Continue')); // -> Step 2
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Continue')); // -> Step 3
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byKey(const ValueKey('specialization-switch')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Current load (kg)'),
        '100',
      );
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      // Recommendation is 24 weeks (see previous test); 24 is >= 24. Apply
      // already set _weeks to 24, so the background "Block length" tile also
      // reads "24 weeks" - scope the tap to the open sheet to disambiguate.
      await tester.tap(find.byKey(const ValueKey('picker-length')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(HxSheet),
          matching: find.text('24 weeks'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.textContaining('Not enough time'), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('picker-length')),
          matching: find.text('24 weeks'),
        ),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 10));
    },
  );

  testWidgets(
    'specialization keeps a compatible existing split (default Upper/Lower)',
    (tester) async {
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

      await tester.tap(find.text('Continue')); // -> Step 2
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Continue')); // -> Step 3
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byKey(const ValueKey('specialization-switch')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Current load (kg)'),
        '100',
      );
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Continue')); // -> Step 4
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Continue')); // -> Step 5
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Upper'), findsWidgets);
      expect(find.text('Lower'), findsWidgets);
      expect(find.text('Full Body A'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 10));
    },
  );

  testWidgets(
    'specialization resets an incompatible split (Bro Split) to Full Body',
    (tester) async {
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

      await tester.tap(find.text('Continue')); // -> Step 2
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Continue')); // -> Step 3
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Continue')); // -> Step 4
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('Bro Split'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Navigate back to Step 3 via the header back affordance.
      await tester.tap(find.byTooltip('Back'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byKey(const ValueKey('specialization-switch')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Current load (kg)'),
        '100',
      );
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Continue')); // -> Step 4 (now Full Body)
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Continue')); // -> Step 5
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Full Body A'), findsWidgets);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 10));
    },
  );

  testWidgets(
    'specialization modal shows per-lift assistanceFocus copy (bench press, off the chest)',
    (tester) async {
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

      await tester.tap(find.text('Continue')); // -> Step 2
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Continue')); // -> Step 3
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byKey(const ValueKey('specialization-switch')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Squat'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bench press').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Not sure yet'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Off the chest').last);
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Chest volume and stable pressing technique are prioritised.',
        ),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 10));
    },
  );

  testWidgets(
    'specialization modal shows per-lift default sticking-point copy (overhead press, unknown)',
    (tester) async {
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

      await tester.tap(find.text('Continue')); // -> Step 2
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Continue')); // -> Step 3
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byKey(const ValueKey('specialization-switch')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Squat'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Overhead press').last);
      await tester.pumpAndSettle();

      // Leave sticking-point dropdown at its default ("Not sure yet").
      expect(
        find.text('Triceps and upper-back assistance are prioritised.'),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 10));
    },
  );

  testWidgets(
    'specialization summary card shows computed exposures for Upper/Lower (2x)',
    (tester) async {
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

      await tester.tap(find.text('Continue')); // -> Step 2
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Continue')); // -> Step 3
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Default split is Upper/Lower; default specialization lift is Squat
      // (matches "lower"), so Squat appears on exactly 2 of the 4 days.
      await tester.tap(find.byKey(const ValueKey('specialization-switch')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Current load (kg)'),
        '100',
      );
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      expect(find.textContaining('2 exposures / week'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 10));
    },
  );

  testWidgets(
    'specialization summary card shows computed exposures for Full Body (3x)',
    (tester) async {
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

      await tester.tap(find.text('Continue')); // -> Step 2
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Continue')); // -> Step 3
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Continue')); // -> Step 4
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('Bro Split'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byTooltip('Back')); // -> Step 3
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byKey(const ValueKey('specialization-switch')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Current load (kg)'),
        '100',
      );
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      // Bro Split is incompatible, so Apply resets to Full Body (3 days, all
      // slots match "full") -- same numeric value as before this task, now
      // computed rather than literal.
      expect(find.textContaining('3 exposures / week'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 10));
    },
  );

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

  // 27-11: the Herculex AI mode tile, its explicit Generate/Regenerate
  // action (D-04 - never auto-fired on mode selection), and the 3-way
  // success/rejection/degradation state machine (D-05, AIP-05).
  group('Herculex AI mode (27-11)', () {
    late AppDatabase db;

    setUp(() async {
      db = await openTestDatabase();
    });

    tearDown(() => db.close());

    const rejectionHeading = "Herculex AI suggestion couldn't be used";
    const rejectionFooter =
        'Showing the recommended Smart/Guided setup instead — you can '
        'still adjust anything below.';
    const offlineMessage =
        "Herculex AI isn't available right now — continuing with the "
        'Smart/Guided recommendation.';
    const quotaMessage =
        "Today's Herculex AI program briefs are used up — try again "
        'tomorrow. Continuing with the Smart/Guided recommendation.';

    Future<void> selectHerculexAiTile(WidgetTester tester) async {
      await tester.tap(find.text('Herculex AI'));
      await tester.pump();
    }

    testWidgets(
      'selecting the tile alone does not trigger generateBrief (D-04)',
      (tester) async {
        final backend = _FakeHerculexGeminiBackend();
        await _pumpBuilderWithBackend(tester, db, backend);

        await selectHerculexAiTile(tester);
        await tester.pump(const Duration(milliseconds: 200));

        expect(backend.callCount, 0);
        expect(find.text('Generating…'), findsNothing);
        expect(find.byType(AiBriefRejectionBanner), findsNothing);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 10));
      },
    );

    testWidgets(
      'tapping Generate calls generateBrief exactly once and shows the '
      'disabled-by-noop loading state',
      (tester) async {
        final backend = _FakeHerculexGeminiBackend(
          delay: const Duration(milliseconds: 200),
        );
        await _pumpBuilderWithBackend(tester, db, backend);
        await selectHerculexAiTile(tester);
        await tester.pump();

        await tester.tap(find.text('Generate with Herculex AI'));
        await tester.pump();

        expect(backend.callCount, 1);
        expect(find.text('Generating…'), findsOneWidget);

        await tester.pump(const Duration(milliseconds: 250));
        expect(backend.callCount, 1);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 10));
      },
    );

    testWidgets(
      'a successful brief that passes guardrails shows Applied + Regenerate, '
      'no rejection banner',
      (tester) async {
        final backend = _FakeHerculexGeminiBackend();
        await _pumpBuilderWithBackend(tester, db, backend);
        await selectHerculexAiTile(tester);
        await tester.pump();

        await tester.tap(find.text('Generate with Herculex AI'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('Applied'), findsOneWidget);
        expect(find.text('Regenerate'), findsOneWidget);
        expect(find.byType(AiBriefRejectionBanner), findsNothing);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 10));
      },
    );

    testWidgets(
      'a brief whose implied configuration fails guardrail validation shows '
      'the rejection banner verbatim and does not apply',
      (tester) async {
        final backend = _FakeHerculexGeminiBackend(
          result: {
            'splitType': 'ppl',
            'periodizationModel': 'max_effort',
            'dayRoles': [
              {
                'dayIndex': 0,
                'role': 'intensity',
                'focus': 'Push day',
                'rationale': 'Front-loads pressing volume.',
              },
            ],
            'musclePriorities': [
              {
                'muscleId': 'chest',
                'priority': 'high',
                'confidence': 0.8,
                'rationale': 'Lagging.',
                'uncertainties': <String>[],
              },
            ],
            'phaseIntent': 'Build pressing strength.',
          },
        );
        await _pumpBuilderWithBackend(tester, db, backend);
        await selectHerculexAiTile(tester);
        await tester.pump();

        await tester.tap(find.text('Generate with Herculex AI'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text(rejectionHeading), findsOneWidget);
        expect(
          find.textContaining(
            'A six-day PPL would create three Max Effort days.',
          ),
          findsOneWidget,
        );
        expect(find.text(rejectionFooter), findsOneWidget);
        expect(find.text('Applied'), findsNothing);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 10));
      },
    );

    testWidgets(
      'an offline/unconfigured failure shows the exact AIP-05 degradation '
      'copy',
      (tester) async {
        final backend = _FakeHerculexGeminiBackend(
          error: Exception('AI analysis is not configured.'),
        );
        await _pumpBuilderWithBackend(tester, db, backend);
        await selectHerculexAiTile(tester);
        await tester.pump();

        await tester.tap(find.text('Generate with Herculex AI'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text(offlineMessage), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 10));
      },
    );

    testWidgets(
      'an over-quota failure shows the exact AIP-05 quota degradation copy',
      (tester) async {
        final backend = _FakeHerculexGeminiBackend(
          error: Exception(
            "Today's Herculex AI program briefs (10/day) are used up — try "
            'again tomorrow.',
          ),
        );
        await _pumpBuilderWithBackend(tester, db, backend);
        await selectHerculexAiTile(tester);
        await tester.pump();

        await tester.tap(find.text('Generate with Herculex AI'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text(quotaMessage), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 10));
      },
    );

    testWidgets(
      'tapping Regenerate after a prior success re-fires exactly one new '
      'call (D-04)',
      (tester) async {
        final backend = _FakeHerculexGeminiBackend();
        await _pumpBuilderWithBackend(tester, db, backend);
        await selectHerculexAiTile(tester);
        await tester.pump();

        await tester.tap(find.text('Generate with Herculex AI'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(backend.callCount, 1);
        expect(find.text('Regenerate'), findsOneWidget);

        await tester.tap(find.text('Regenerate'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(backend.callCount, 2);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 10));
      },
    );
  });

  // 27-13: pre-fill wiring - musclePriorities through the existing Dream
  // Physique tuning seam (D-01, zero new apply logic) and
  // split/periodizationModel/phaseIntent into the corresponding Step 1-5
  // fields (D-03, no new screen) - plus persistBrief() on "Create block"
  // (D-08).
  group('Herculex AI pre-fill and persistence (27-13)', () {
    late AppDatabase db;

    setUp(() async {
      db = await openTestDatabase();
    });

    tearDown(() => db.close());

    Future<void> selectHerculexAiTile(WidgetTester tester) async {
      await tester.tap(find.text('Herculex AI'));
      await tester.pump();
    }

    Future<void> generate(WidgetTester tester) async {
      await tester.tap(find.text('Generate with Herculex AI'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets(
      'a successful generate applies musclePriorities through the existing '
      'Dream Physique tuning seam (D-01), and phaseIntent is visible before '
      'confirmation (AIP-04)',
      (tester) async {
        final backend = _FakeHerculexGeminiBackend();
        await _pumpBuilderWithBackend(tester, db, backend);
        await selectHerculexAiTile(tester);
        await generate(tester);

        expect(find.text('Applied'), findsOneWidget);
        // D-01: the SAME rendering every Dream Physique priorities load
        // already drives (dreamPrioritiesActive = dreamPrioritiesSaved &&
        // !_useManualMusclePlan) - proof _dreamPhysiquePriorities was
        // populated and _useManualMusclePlan was cleared, with zero new
        // apply logic.
        expect(
          find.text('AI-analyzed priorities applied to program volume.'),
          findsOneWidget,
        );
        // phaseIntent surfaced verbatim (the fake backend's default
        // phrase), satisfying AIP-04's "visible before confirmation".
        expect(
          find.textContaining(
            'Build upper body symmetry ahead of the next block.',
          ),
          findsOneWidget,
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 10));
      },
    );

    testWidgets(
      "the brief's splitType/periodizationModel set _split/_model directly "
      '(D-03) - no new screen, visible in the existing schedule summary',
      (tester) async {
        final backend = _FakeHerculexGeminiBackend(
          result: {
            'splitType': 'ppl',
            'periodizationModel': 'concurrent',
            'dayRoles': [
              {
                'dayIndex': 0,
                'role': 'intensity',
                'focus': 'Push day',
                'rationale': 'Front-loads pressing volume.',
              },
            ],
            'musclePriorities': [
              {
                'muscleId': 'chest',
                'priority': 'high',
                'confidence': 0.8,
                'rationale': 'Lagging relative to back.',
                'uncertainties': <String>[],
              },
            ],
            'phaseIntent': 'Build pressing volume ahead of the next block.',
          },
        );
        await _pumpBuilderWithBackend(tester, db, backend);
        await selectHerculexAiTile(tester);
        await generate(tester);
        expect(find.text('Applied'), findsOneWidget);

        // Both differ from the builder's own defaults (upper_lower/linear),
        // so seeing them on Step 6 proves direct assignment happened, not
        // an unrelated default.
        for (var i = 0; i < 5; i++) {
          await _continue(tester);
        }
        expect(find.textContaining('Push / Pull / Legs'), findsWidgets);
        expect(find.textContaining('Concurrent'), findsWidgets);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 10));
      },
    );

    testWidgets(
      'the user can still hand-edit the pre-filled split via the existing '
      'Step 4 picker after a successful generate, and it sticks (no '
      're-lock/override on rebuild)',
      (tester) async {
        final backend = _FakeHerculexGeminiBackend(); // upper_lower/linear
        await _pumpBuilderWithBackend(tester, db, backend);
        await selectHerculexAiTile(tester);
        await generate(tester);
        expect(find.text('Applied'), findsOneWidget);

        await _continue(tester); // Step 1 -> Step 2
        await _continue(tester); // Step 2 -> Step 3
        await _continue(tester); // Step 3 -> Step 4 (split)

        expect(find.text('Split'), findsOneWidget);
        await tester.tap(find.text('Push / Pull / Legs'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        await _continue(tester); // Step 4 -> Step 5
        await _continue(tester); // Step 5 -> Step 6

        expect(find.textContaining('Push / Pull / Legs'), findsWidgets);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 10));
      },
    );

    testWidgets(
      'Create block persists the accepted brief exactly once via '
      'HerculexAiBriefService.persistBrief() (D-08)',
      (tester) async {
        final backend = _FakeHerculexGeminiBackend();
        await _pumpBuilderWithBackend(tester, db, backend);
        await selectHerculexAiTile(tester);
        await generate(tester);
        expect(find.text('Applied'), findsOneWidget);

        for (var i = 0; i < 5; i++) {
          await _continue(tester);
        }
        await _createBlock(tester);
        await tester.pumpAndSettle();

        expect(
          find.textContaining('Could not create the block'),
          findsNothing,
        );
        expect(find.byType(ProgramReviewView), findsOneWidget);
        final review = tester.widget<ProgramReviewView>(
          find.byType(ProgramReviewView),
        );

        final rows = await db.select(db.herculexAiProgramBriefs).get();
        expect(rows, hasLength(1));
        expect(rows.single.programId, review.programId);
        expect(rows.single.source, 'herculex_ai');
        expect(rows.single.active, true);
        final decoded = ProgramBrief.fromJson(
          jsonDecode(rows.single.briefJson) as Map<String, dynamic>,
        );
        expect(decoded.splitType, SplitType.upperLower);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 10));
      },
    );

    testWidgets(
      'Create block never calls persistBrief() for non-Herculex-AI build '
      'modes - no HerculexAiProgramBriefs row is written',
      (tester) async {
        await _pumpBuilder(tester, db);
        await tester.tap(find.text('Build it for me'));
        await tester.pump();

        for (var i = 0; i < 5; i++) {
          await _continue(tester);
        }
        await _createBlock(tester);
        await tester.pumpAndSettle();

        expect(
          find.textContaining('Could not create the block'),
          findsNothing,
        );
        expect(find.byType(ProgramReviewView), findsOneWidget);

        final rows = await db.select(db.herculexAiProgramBriefs).get();
        expect(rows, isEmpty);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 10));
      },
    );

    testWidgets(
      'Create block with Herculex AI mode selected but no accepted brief '
      'does not call persistBrief() and does not throw',
      (tester) async {
        final backend = _FakeHerculexGeminiBackend();
        await _pumpBuilderWithBackend(tester, db, backend);
        await selectHerculexAiTile(tester);
        // Never tap Generate - _acceptedHerculexBrief stays null (the user
        // switched to Herculex AI mode but never successfully generated).

        for (var i = 0; i < 5; i++) {
          await _continue(tester);
        }
        await _createBlock(tester);
        await tester.pumpAndSettle();

        expect(
          find.textContaining('Could not create the block'),
          findsNothing,
        );
        expect(find.byType(ProgramReviewView), findsOneWidget);
        expect(backend.callCount, 0);

        final rows = await db.select(db.herculexAiProgramBriefs).get();
        expect(rows, isEmpty);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 10));
      },
    );

    testWidgets(
      'a persistBrief() failure does not prevent the program from being '
      'created - swallowed, program creation proceeds normally',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final backend = _FakeHerculexGeminiBackend();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appDatabaseProvider.overrideWithValue(db),
              geminiBackendProvider.overrideWithValue(backend),
              herculexAiBriefServiceProvider.overrideWith(
                (ref) => _ThrowingPersistHerculexAiBriefService(
                  ref.watch(geminiBackendProvider),
                  ref.watch(appDatabaseProvider),
                  ref.watch(clockProvider),
                ),
              ),
            ],
            child: const MaterialApp(
              home: BlockBuilderView(autoRecommendExperience: false),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        await selectHerculexAiTile(tester);
        await generate(tester);
        expect(find.text('Applied'), findsOneWidget);

        for (var i = 0; i < 5; i++) {
          await _continue(tester);
        }
        await _createBlock(tester);
        await tester.pumpAndSettle();

        expect(
          find.textContaining('Could not create the block'),
          findsNothing,
        );
        expect(find.byType(ProgramReviewView), findsOneWidget);

        final rows = await db.select(db.herculexAiProgramBriefs).get();
        expect(rows, isEmpty);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 10));
      },
    );
  });
}
