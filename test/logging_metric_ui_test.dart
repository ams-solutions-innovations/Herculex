import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/core/units.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/profile/domain/profile.dart';
import 'package:herculex/features/workouts/domain/logging_metric.dart';
import 'package:herculex/features/workouts/domain/set_metric_format.dart';
import 'package:herculex/features/workouts/presentation/active_exercise_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/test_database.dart';

/// EXR-05, the user-facing half: the set row asks for the units the exercise is
/// actually measured in. Before this, `active_exercise_card.dart` rendered a
/// fixed weight/reps/RPE row for every exercise in the catalogue, so a Plank
/// was logged as kilograms × repetitions.
///
/// The column headers are the assertion surface because they are derived from
/// the same `metric.fields` list the inputs are — if the header says TIME, the
/// field under it is the duration controller.
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

  Future<ExerciseCatalogData> seedExercise({
    required String name,
    required String loggingMetric,
    String modality = 'barbell',
  }) async {
    final id = await db
        .into(db.exerciseCatalog)
        .insert(
          ExerciseCatalogCompanion.insert(
            name: name,
            primaryMuscle: 'Full Body',
            equipment: modality,
            mechanics: 'compound',
            force: 'push',
            plane: 'axial',
            modality: Value(modality),
            loggingMetric: Value(loggingMetric),
          ),
        );
    return (db.select(db.exerciseCatalog)..where((t) => t.id.equals(id)))
        .getSingle();
  }

  /// A session with one exercise and one empty set, ready to be logged into.
  Future<(WorkoutExerciseData, int)> seedSession(int exerciseId) async {
    final sessionId = await db
        .into(db.workoutSessions)
        .insert(WorkoutSessionsCompanion.insert(startedAt: DateTime(2026, 8)));
    final weId = await db
        .into(db.workoutExercises)
        .insert(
          WorkoutExercisesCompanion.insert(
            sessionId: sessionId,
            exerciseId: exerciseId,
            orderIndex: 0,
          ),
        );
    final setId = await db
        .into(db.setEntries)
        .insert(
          SetEntriesCompanion.insert(
            workoutExerciseId: weId,
            setIndex: 0,
            weightKg: 0,
            reps: 0,
          ),
        );
    final we = await (db.select(
      db.workoutExercises,
    )..where((t) => t.id.equals(weId))).getSingle();
    return (we, setId);
  }

  Future<void> pumpCard(
    WidgetTester tester, {
    required WorkoutExerciseData workoutExercise,
    required ExerciseCatalogData exercise,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          appDatabaseProvider.overrideWithValue(db),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ActiveExerciseCard(
                workoutExercise: workoutExercise,
                exercise: exercise,
                onRemove: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Disposing the scope cancels drift's watch streams, which schedule a
  /// zero-duration cleanup timer; left to framework teardown it trips the
  /// "timer still pending" assertion.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 10));
  }

  group('the set row renders its exercise\'s metric', () {
    testWidgets('weight_reps still renders weight, reps and RPE', (
      tester,
    ) async {
      final exercise = await seedExercise(
        name: 'Test Back Squat',
        loggingMetric: 'weight_reps',
      );
      final (we, _) = await seedSession(exercise.id);
      await pumpCard(tester, workoutExercise: we, exercise: exercise);

      expect(find.text('KG'), findsOneWidget);
      expect(find.text('REPS'), findsOneWidget);
      // Twice: the column header, and the empty RPE cell's own placeholder.
      expect(find.text('RPE'), findsNWidgets(2));
      expect(find.text('TIME'), findsNothing);
      expect(find.text('M'), findsNothing);
      // Two metric inputs plus the RPE cell, which is not a TextField.
      expect(find.byType(TextField), findsNWidgets(2));

      await unmount(tester);
    });

    testWidgets('time renders a duration field and no weight or reps', (
      tester,
    ) async {
      final exercise = await seedExercise(
        name: 'Test Plank',
        loggingMetric: 'time',
        modality: 'bodyweight',
      );
      final (we, _) = await seedSession(exercise.id);
      await pumpCard(tester, workoutExercise: we, exercise: exercise);

      expect(find.text('TIME'), findsOneWidget);
      expect(find.text('KG'), findsNothing);
      expect(find.text('REPS'), findsNothing);
      expect(find.byType(TextField), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('weight_distance renders weight and metres', (tester) async {
      final exercise = await seedExercise(
        name: 'Test Sled Push',
        loggingMetric: 'weight_distance',
        modality: 'other',
      );
      final (we, _) = await seedSession(exercise.id);
      await pumpCard(tester, workoutExercise: we, exercise: exercise);

      expect(find.text('KG'), findsOneWidget);
      expect(find.text('M'), findsOneWidget);
      expect(find.text('REPS'), findsNothing);
      expect(find.byType(TextField), findsNWidgets(2));

      await unmount(tester);
    });

    testWidgets('time_calories renders a duration and a calorie field', (
      tester,
    ) async {
      final exercise = await seedExercise(
        name: 'Test Air Bike',
        loggingMetric: 'time_calories',
        modality: 'other',
      );
      final (we, _) = await seedSession(exercise.id);
      await pumpCard(tester, workoutExercise: we, exercise: exercise);

      expect(find.text('TIME'), findsOneWidget);
      expect(find.text('KCAL'), findsOneWidget);
      expect(find.text('KG'), findsNothing);

      await unmount(tester);
    });
  });

  group('a non-rep set round-trips to the database', () {
    testWidgets('a plank typed as 2:00 stores 120 seconds and nothing else', (
      tester,
    ) async {
      final exercise = await seedExercise(
        name: 'Test Plank',
        loggingMetric: 'time',
        modality: 'bodyweight',
      );
      final (we, setId) = await seedSession(exercise.id);
      await pumpCard(tester, workoutExercise: we, exercise: exercise);

      await tester.enterText(find.byType(TextField), '2:00');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      final stored = await (db.select(
        db.setEntries,
      )..where((t) => t.id.equals(setId))).getSingle();

      expect(stored.durationSeconds, 120);
      // The metric declares no distance and no calories, so the row must not
      // have acquired a zero for either — null is what "not measured this way"
      // looks like, and analytics depends on the difference.
      expect(stored.distanceM, isNull);
      expect(stored.calories, isNull);
      // The NOT NULL columns keep their placeholder zeros.
      expect(stored.weightKg, 0);
      expect(stored.reps, 0);

      await unmount(tester);
    });

    testWidgets('a sled push stores its load and its distance', (tester) async {
      final exercise = await seedExercise(
        name: 'Test Sled Push',
        loggingMetric: 'weight_distance',
        modality: 'other',
      );
      final (we, setId) = await seedSession(exercise.id);
      await pumpCard(tester, workoutExercise: we, exercise: exercise);

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), '40');
      await tester.enterText(fields.at(1), '20');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      final stored = await (db.select(
        db.setEntries,
      )..where((t) => t.id.equals(setId))).getSingle();

      expect(stored.weightKg, 40);
      expect(stored.distanceM, 20);
      expect(stored.durationSeconds, isNull);
      expect(stored.reps, 0);

      await unmount(tester);
    });
  });

  group('SetMetricFormat', () {
    test('durations parse the way people type them', () {
      expect(SetMetricFormat.parseDuration('90'), 90);
      expect(SetMetricFormat.parseDuration('90s'), 90);
      expect(SetMetricFormat.parseDuration('1:30'), 90);
      expect(SetMetricFormat.parseDuration('1:02:30'), 3750);
      expect(SetMetricFormat.parseDuration(''), isNull);
      expect(SetMetricFormat.parseDuration('abc'), isNull);
    });

    test('durations render as seconds below a minute and clock above', () {
      expect(SetMetricFormat.formatDuration(45), '45s');
      expect(SetMetricFormat.formatDuration(90), '1:30');
      expect(SetMetricFormat.formatDuration(725), '12:05');
      expect(SetMetricFormat.formatDuration(3750), '1:02:30');
    });

    test('a duration field re-renders exactly what it would re-parse', () {
      for (final seconds in [45, 90, 725, 3750]) {
        final text = SetMetricFormat.durationFieldText(seconds);
        expect(SetMetricFormat.parseDuration(text), seconds);
      }
    });

    test('a weight_reps summary is unchanged from the old hardcoded string', () {
      final set = SetEntryData(
        id: 1,
        workoutExerciseId: 1,
        setIndex: 0,
        weightKg: 60,
        reps: 8,
        isWarmup: false,
        isCompleted: true,
        setType: 'standard',
      );
      expect(
        SetMetricFormat.summariseSet(
          set,
          metric: LoggingMetric.weightReps,
          weight: const WeightFormat(MeasurementUnit.metric),
          distance: const DistanceFormat(MeasurementUnit.metric),
        ),
        '60 kg × 8',
      );
    });

    test('a non-rep summary reads in its own units', () {
      final sled = SetEntryData(
        id: 1,
        workoutExerciseId: 1,
        setIndex: 0,
        weightKg: 40,
        reps: 0,
        distanceM: 20,
        isWarmup: false,
        isCompleted: true,
        setType: 'standard',
      );
      expect(
        SetMetricFormat.summariseSet(
          sled,
          metric: LoggingMetric.weightDistance,
          weight: const WeightFormat(MeasurementUnit.metric),
          distance: const DistanceFormat(MeasurementUnit.metric),
        ),
        '40 kg · 20 m',
      );

      final plank = SetEntryData(
        id: 2,
        workoutExerciseId: 1,
        setIndex: 1,
        weightKg: 0,
        reps: 0,
        durationSeconds: 120,
        isWarmup: false,
        isCompleted: true,
        setType: 'standard',
      );
      expect(
        SetMetricFormat.summariseSet(
          plank,
          metric: LoggingMetric.time,
          weight: const WeightFormat(MeasurementUnit.metric),
          distance: const DistanceFormat(MeasurementUnit.metric),
        ),
        '2:00',
      );
    });
  });
}
