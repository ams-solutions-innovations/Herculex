import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/design_system/components/hx_nav_bar.dart';
import 'package:herculex/features/shell/main_scaffold.dart';
import 'package:herculex/features/workouts/application/workouts_providers.dart';
import 'package:herculex/services/platform/app_shortcuts_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/test_database.dart';

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

  Future<void> settle(WidgetTester tester, {int frames = 10}) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<int> seedActiveSession() async {
    final exerciseId = await db
        .into(db.exerciseCatalog)
        .insert(
          ExerciseCatalogCompanion.insert(
            name: 'Barbell Bench Press',
            primaryMuscle: 'Chest',
            equipment: 'barbell',
            mechanics: 'compound',
            force: 'push',
            plane: 'horizontal',
          ),
        );
    final sessionId = await db
        .into(db.workoutSessions)
        .insert(
          WorkoutSessionsCompanion.insert(
            name: const Value('Chest & Triceps'),
            startedAt: DateTime.now().subtract(const Duration(minutes: 15)),
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
            weightKg: 80,
            reps: 8,
            isCompleted: const Value(false),
          ),
        );
    return sessionId;
  }

  testWidgets(
    'workoutInputFocusedProvider synchronizes hiding and ignoring of nav bar and workout action bar',
    (tester) async {
      await seedActiveSession();

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          appDatabaseProvider.overrideWithValue(db),
          mainTabIndexProvider.overrideWith((ref) => 2),
          appShortcutsControllerProvider.overrideWithValue(null),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: MainScaffold()),
        ),
      );
      await settle(tester);

      expect(find.byType(HxNavBar), findsOneWidget);
      expect(find.text('Finish'), findsOneWidget);

      // Initially, controls are visible (bottom: 0) and interactive (ignoring: false)
      final initialNavPos = tester.widget<AnimatedPositioned>(
        find.ancestor(
          of: find.byType(HxNavBar),
          matching: find.byType(AnimatedPositioned),
        ),
      );
      expect(initialNavPos.bottom, 0);

      final initialFinishPos = tester.widget<AnimatedPositioned>(
        find.ancestor(
          of: find.text('Finish'),
          matching: find.byType(AnimatedPositioned),
        ),
      );
      expect(initialFinishPos.bottom, 0);

      final initialNavIgnore = tester.widget<IgnorePointer>(
        find
            .ancestor(
              of: find.byType(HxNavBar),
              matching: find.byType(IgnorePointer),
            )
            .first,
      );
      expect(initialNavIgnore.ignoring, isFalse);

      final initialFinishIgnore = tester.widget<IgnorePointer>(
        find
            .ancestor(
              of: find.text('Finish'),
              matching: find.byType(IgnorePointer),
            )
            .first,
      );
      expect(initialFinishIgnore.ignoring, isFalse);

      // Simulate keyboard / input focus
      container.read(workoutInputFocusedProvider.notifier).state = true;
      await settle(tester, frames: 3);

      final hiddenNavPos = tester.widget<AnimatedPositioned>(
        find.ancestor(
          of: find.byType(HxNavBar),
          matching: find.byType(AnimatedPositioned),
        ),
      );
      expect(hiddenNavPos.bottom, -120);

      final hiddenFinishPos = tester.widget<AnimatedPositioned>(
        find.ancestor(
          of: find.text('Finish'),
          matching: find.byType(AnimatedPositioned),
        ),
      );
      expect(hiddenFinishPos.bottom, -140);

      final hiddenNavIgnore = tester.widget<IgnorePointer>(
        find
            .ancestor(
              of: find.byType(HxNavBar),
              matching: find.byType(IgnorePointer),
            )
            .first,
      );
      expect(hiddenNavIgnore.ignoring, isTrue);

      final hiddenFinishIgnore = tester.widget<IgnorePointer>(
        find
            .ancestor(
              of: find.text('Finish'),
              matching: find.byType(IgnorePointer),
            )
            .first,
      );
      expect(hiddenFinishIgnore.ignoring, isTrue);

      // Focus released -> controls animate back to 0 and become interactive again
      container.read(workoutInputFocusedProvider.notifier).state = false;
      await settle(tester, frames: 3);

      final restoredNavPos = tester.widget<AnimatedPositioned>(
        find.ancestor(
          of: find.byType(HxNavBar),
          matching: find.byType(AnimatedPositioned),
        ),
      );
      expect(restoredNavPos.bottom, 0);

      final restoredFinishPos = tester.widget<AnimatedPositioned>(
        find.ancestor(
          of: find.text('Finish'),
          matching: find.byType(AnimatedPositioned),
        ),
      );
      expect(restoredFinishPos.bottom, 0);

      final restoredNavIgnore = tester.widget<IgnorePointer>(
        find
            .ancestor(
              of: find.byType(HxNavBar),
              matching: find.byType(IgnorePointer),
            )
            .first,
      );
      expect(restoredNavIgnore.ignoring, isFalse);

      final restoredFinishIgnore = tester.widget<IgnorePointer>(
        find
            .ancestor(
              of: find.text('Finish'),
              matching: find.byType(IgnorePointer),
            )
            .first,
      );
      expect(restoredFinishIgnore.ignoring, isFalse);

      // Tear down safely before canceling stream timers
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 50));
    },
  );
}
