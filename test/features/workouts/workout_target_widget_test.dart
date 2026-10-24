import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/core/notifications/in_app_notification_overlay.dart';
import 'package:herculex/core/utils/clock.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/workouts/application/workout_target_providers.dart';
import 'package:herculex/features/workouts/application/workouts_providers.dart';
import 'package:herculex/features/workouts/data/workout_targets_repository.dart';
import 'package:herculex/features/workouts/data/workouts_repository.dart';
import 'package:herculex/features/workouts/domain/progression_engine.dart';
import 'package:herculex/features/workouts/domain/workout_target_resolver.dart';
import 'package:herculex/features/workouts/presentation/widgets/active_exercise_card.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../support/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  late AppDatabase db;
  late WorkoutsRepository repo;
  late int weId, secondId;
  late ExerciseCatalogData exercise;
  late WorkoutExerciseData we;
  late List<SetEntryData> rows;
  late Map<int, WorkoutTarget> resolved;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    db = await openTestDatabase();
    repo = WorkoutsRepository(db, const SystemClock());
    final exerciseId = await db
        .into(db.exerciseCatalog)
        .insert(
          ExerciseCatalogCompanion.insert(
            name: 'Target Test Press',
            primaryMuscle: 'Chest',
            equipment: 'Barbell',
            mechanics: 'compound',
            force: 'push',
            plane: 'horizontal',
            modality: const Value('barbell'),
            isCustom: const Value(true),
          ),
        );
    final sessionId = await repo.startSession();
    weId = await repo.addExerciseToSession(
      sessionId: sessionId,
      exerciseId: exerciseId,
    );
    final first = (await repo.watchSetsForWorkoutExercise(weId).first).single;
    await repo.updateSet(
      setId: first.id,
      weightKg: 100,
      reps: 4,
      rpeX10: 95,
      isCompleted: true,
    );
    secondId = await repo.addSet(
      workoutExerciseId: weId,
      weightKg: 110,
      reps: 0,
    );
    await (db.update(
      db.setEntries,
    )..where((t) => t.workoutExerciseId.equals(weId))).write(
      const SetEntriesCompanion(
        plannedWeightKg: Value(100),
        plannedRepsMin: Value(5),
        plannedRepsMax: Value(5),
        plannedRpeX10: Value(80),
      ),
    );
    exercise = await (db.select(
      db.exerciseCatalog,
    )..where((t) => t.id.equals(exerciseId))).getSingle();
    we = (await repo.watchSessionExercises(sessionId).first).single;
    rows = await repo.watchSetsForWorkoutExercise(weId).first;
    resolved = await WorkoutTargetsRepository(
      db,
      const SystemClock(),
      prefs,
    ).resolve(exercise: exercise, workoutExercise: we, sets: rows);
  });

  testWidgets(
    'Adaptive ghost hints preserve logged values and do not invent actual RPE',
    (tester) async {
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          sharedPreferencesProvider.overrideWithValue(prefs),
          workoutProgressionGoalProvider.overrideWithValue(
            ProgressionGoal.muscleGain,
          ),
          workoutTargetsProvider(
            weId,
          ).overrideWith((ref) => Stream.value(resolved)),
          setsForWorkoutExerciseProvider(
            weId,
          ).overrideWith((ref) => Stream.value(rows)),
          lastPerformanceProvider(
            exercise.id,
          ).overrideWith((ref) async => null),
          accessoriesProvider.overrideWith((ref) => Stream.value([])),
          bandsProvider.overrideWith((ref) => Stream.value([])),
          setAccessoriesProvider.overrideWith((ref, id) => Stream.value([])),
          setBandsProvider.overrideWith((ref, id) => Stream.value([])),
        ],
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(() async {
          container.dispose();
          await db.close();
        });
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            builder: (context, child) => InAppNotificationHost(child: child!),
            home: Scaffold(
              body: SingleChildScrollView(
                child: ActiveExerciseCard(
                  workoutExercise: we,
                  exercise: exercise,
                  onRemove: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('Target 2nd set:'), findsOneWidget);
      final fields = tester
          .widgetList<TextField>(find.byType(TextField))
          .toList();
      expect(
        fields.any(
          (f) =>
              f.controller?.text == '110' && f.decoration?.hintText == '92.5',
        ),
        true,
      );
      expect(
        fields.any(
          (f) => f.controller?.text == '' && f.decoration?.hintText == '5',
        ),
        true,
      );
      final savedRows = await tester.runAsync(
        () => repo.watchSetsForWorkoutExercise(weId).first,
      );
      final actual = savedRows!.firstWhere((s) => s.id == secondId);
      expect(actual.weightKg, 110);
      expect(actual.reps, 0);
      expect(actual.rpeX10, isNull);
      expect(actual.plannedWeightKg, 100);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'phone typing and remote weight/reps edits preserve both fields',
    (tester) async {
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          sharedPreferencesProvider.overrideWithValue(prefs),
          workoutProgressionGoalProvider.overrideWithValue(
            ProgressionGoal.muscleGain,
          ),
          workoutTargetsProvider(
            weId,
          ).overrideWith((ref) => Stream.value(resolved)),
          lastPerformanceProvider(
            exercise.id,
          ).overrideWith((ref) async => null),
          accessoriesProvider.overrideWith((ref) => Stream.value([])),
          bandsProvider.overrideWith((ref) => Stream.value([])),
          setAccessoriesProvider.overrideWith((ref, id) => Stream.value([])),
          setBandsProvider.overrideWith((ref, id) => Stream.value([])),
        ],
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(() async {
          container.dispose();
          await db.close();
        });
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            builder: (context, child) => InAppNotificationHost(child: child!),
            home: Scaffold(
              body: SingleChildScrollView(
                child: ActiveExerciseCard(
                  workoutExercise: we,
                  exercise: exercise,
                  onRemove: () {},
                ),
              ),
            ),
          ),
        ),
      );
      Future<void> settle() async {
        for (var i = 0; i < 15; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump(const Duration(milliseconds: 50));
        }
      }

      await settle();
      final weight = find.byWidgetPredicate(
        (w) => w is TextField && w.controller?.text == '110',
      );
      await tester.ensureVisible(weight);
      await tester.enterText(weight, '115');
      // A watch reps update lands before the phone's 600 ms debounce.
      await tester.runAsync(() => repo.updateSet(setId: secondId, reps: 9));
      await settle();
      var saved = (await tester.runAsync(
        () => repo.watchSetsForWorkoutExercise(weId).first,
      ))!.firstWhere((s) => s.id == secondId);
      expect(saved.weightKg, 115);
      expect(saved.reps, 9);
      final reps = find.byWidgetPredicate(
        (w) => w is TextField && w.controller?.text == '9',
      );
      await tester.ensureVisible(reps);
      await tester.enterText(reps, '11');
      await tester.runAsync(
        () => repo.updateSet(setId: secondId, weightKg: 120),
      );
      await settle();
      saved = (await tester.runAsync(
        () => repo.watchSetsForWorkoutExercise(weId).first,
      ))!.firstWhere((s) => s.id == secondId);
      expect(saved.weightKg, 120);
      expect(saved.reps, 11);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 2));
    },
  );
}
