import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/workouts/presentation/views/workout_finish_view.dart';
import 'package:herculex/features/workouts/presentation/views/workouts_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/test_database.dart';

/// Regression guard for the finish-workout red screen.
///
/// The bug: `WorkoutsView` renders `ActiveWorkoutView` only while
/// `activeSessionProvider` (a stream over `ended_at IS NULL`) has a session.
/// `endSession` flips that column, so the widget is **disposed mid-handler**,
/// while its Finish dialog is still on the Navigator stack. Riverpod's `ref`
/// throws a real `StateError` once its element is disposed — in release as
/// well as debug — so:
///
///  * the `ref.read(wearWorkoutSyncServiceProvider)` that ran *after* the
///    `endSession` await threw uncaught, which meant the dialog was never
///    popped and the finish screen never opened, and
///  * the dialog's `StatefulBuilder` did `ref.watch(...)` in its **build**
///    phase, so the next rebuild threw during build → red `ErrorWidget`.
///
/// Both are asserted here through the public surface: tap Finish, and expect
/// no error to reach `FlutterError.onError` while the session is really ended.
///
/// This test fails on the pre-fix code.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    db = await openTestDatabase();
  });

  tearDown(() => db.close());

  /// `pumpAndSettle` is unusable here: `ActiveWorkoutView` runs a
  /// `Timer.periodic(1s)` calling `setState` for its elapsed-time readout, so
  /// the frame queue never drains and the test times out after ten minutes.
  /// A bounded number of pumps is enough to flush the drift streams and the
  /// dialog transition.
  Future<void> settle(WidgetTester tester, {int frames = 12}) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<int> seedActiveSession() async {
    final exerciseId = await db
        .into(db.exerciseCatalog)
        .insert(
          ExerciseCatalogCompanion.insert(
            name: 'Back Squat',
            primaryMuscle: 'Quads',
            equipment: 'barbell',
            mechanics: 'compound',
            force: 'push',
            plane: 'axial',
          ),
        );
    final sessionId = await db
        .into(db.workoutSessions)
        .insert(
          WorkoutSessionsCompanion.insert(
            startedAt: DateTime.now().subtract(const Duration(minutes: 45)),
          ),
        );
    final weId = await db
        .into(db.workoutExercises)
        .insert(
          WorkoutExercisesCompanion.insert(
            sessionId: sessionId,
            exerciseId: exerciseId,
            orderIndex: 0,
          ),
        );
    await db
        .into(db.setEntries)
        .insert(
          SetEntriesCompanion.insert(
            workoutExerciseId: weId,
            setIndex: 0,
            weightKg: 100,
            reps: 5,
            isCompleted: const Value(true),
          ),
        );
    return sessionId;
  }

  Future<void> pumpWorkouts(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          appDatabaseProvider.overrideWithValue(db),
        ],
        child: const MaterialApp(home: Scaffold(body: WorkoutsView())),
      ),
    );
    await settle(tester);
  }

  /// Disposing the scope cancels drift's watch streams, which schedule a
  /// zero-duration cleanup timer; left to framework teardown it trips the
  /// "timer still pending" assertion.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  }

  testWidgets('finishing a workout ends the session and raises no error', (
    tester,
  ) async {
    final sessionId = await seedActiveSession();

    await pumpWorkouts(tester);
    expect(
      find.text('Finish'),
      findsOneWidget,
      reason: 'the active workout screen should be showing its Finish action',
    );

    await tester.tap(find.text('Finish'));
    await settle(tester);

    // The confirm dialog is up; its Finish button is the one in the actions
    // row, i.e. the last one rendered.
    expect(find.text('Finish Workout'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Finish').last);
    await settle(tester);

    // Drain rather than take one: the finish dialog also trips Flutter's
    // debug-only "ListTile background color or ink splashes may be invisible"
    // advisory (a DecoratedBox between the tile and its Material), which is a
    // real but cosmetic pre-existing issue and not what this test guards.
    final raised = <Object>[];
    for (
      var e = tester.takeException();
      e != null;
      e = tester.takeException()
    ) {
      raised.add(e);
    }
    expect(
      raised.whereType<StateError>(),
      isEmpty,
      reason:
          'finishing must not raise a StateError — "Cannot use ref after the '
          'widget was disposed" here is the red screen this test guards. '
          'Raised: $raised',
    );

    final session = await (db.select(
      db.workoutSessions,
    )..where((t) => t.id.equals(sessionId))).getSingleOrNull();
    expect(session, isNotNull);
    expect(
      session!.endedAt,
      isNotNull,
      reason: 'endSession must have stamped ended_at',
    );
    expect(
      session.caloriesBurned,
      isNotNull,
      reason: 'the MET estimate is written as part of finishing',
    );
    expect(
      session.name,
      isNotNull,
      reason: 'the workout is named on finish, not left blank',
    );

    await unmount(tester);
  });

  testWidgets('the active workout screen builds without a backend', (
    tester,
  ) async {
    // `Env.hasSupabase` is a compile-time constant and no test passes the
    // dart-defines, so this is the credential-less path by construction.
    //
    // `buddyGatewayProvider` used to `throw StateError` in exactly this case,
    // and `ActiveWorkoutView.build` watches it transitively through
    // `buddySessionControllerProvider` — a synchronous throw out of `ref.watch`
    // during build, i.e. an instant red screen on the app's most-used screen
    // in every credential-less build.
    await seedActiveSession();
    await pumpWorkouts(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Finish'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('finish screen keeps secondary details collapsed by default', (
    tester,
  ) async {
    final sessionId = await seedActiveSession();
    await (db.update(
      db.workoutSessions,
    )..where((row) => row.id.equals(sessionId))).write(
      WorkoutSessionsCompanion(
        name: const Value('Leg day'),
        endedAt: Value(DateTime.now()),
        caloriesBurned: const Value(320),
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          appDatabaseProvider.overrideWithValue(db),
        ],
        child: MaterialApp(home: WorkoutFinishView(sessionId: sessionId)),
      ),
    );
    await settle(tester, frames: 36);

    expect(find.text('Workout Complete'), findsOneWidget);
    expect(find.text('Leg day'), findsWidgets);
    expect(find.bySemanticsLabel('Share workout'), findsOneWidget);
    expect(find.text('More details'), findsOneWidget);
    expect(find.text('SHARE CARD STYLE'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Done'), findsOneWidget);

    await tester.ensureVisible(find.text('More details'));
    await tester.tap(find.text('More details'));
    await settle(tester);

    expect(find.text('SHARE CARD STYLE'), findsOneWidget);
    expect(find.text('WORKOUT PHOTO'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('Done returns from the finish screen', (tester) async {
    final sessionId = await seedActiveSession();
    await (db.update(db.workoutSessions)
          ..where((row) => row.id.equals(sessionId)))
        .write(WorkoutSessionsCompanion(endedAt: Value(DateTime.now())));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          appDatabaseProvider.overrideWithValue(db),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => WorkoutFinishView.show(context, sessionId),
                  child: const Text('Open finish'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open finish'));
    await settle(tester, frames: 36);
    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await settle(tester);

    expect(find.text('Open finish'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('keyboard excludes active-workout actions from every surface', (
    tester,
  ) async {
    await seedActiveSession();
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    addTearDown(tester.view.resetViewInsets);
    tester.binding.handleMetricsChanged();

    await pumpWorkouts(tester);

    final actionBar = find.ancestor(
      of: find.text('Finish'),
      matching: find.byType(ExcludeSemantics),
    );
    expect(actionBar, findsOneWidget);
    expect(tester.widget<ExcludeSemantics>(actionBar).excluding, isTrue);

    final pointerGate = find.descendant(
      of: actionBar,
      matching: find.byType(IgnorePointer),
    );
    expect(tester.widget<IgnorePointer>(pointerGate).ignoring, isTrue);

    final fade = find
        .descendant(of: actionBar, matching: find.byType(AnimatedOpacity))
        .first;
    expect(tester.widget<AnimatedOpacity>(fade).opacity, 0);

    tester.view.resetViewInsets();
    tester.binding.handleMetricsChanged();
    expect(tester.view.viewInsets.bottom, 0);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(tester.widget<ExcludeSemantics>(actionBar).excluding, isFalse);
    expect(tester.widget<IgnorePointer>(pointerGate).ignoring, isFalse);
    expect(tester.widget<AnimatedOpacity>(fade).opacity, 1);

    await unmount(tester);
  });
}
