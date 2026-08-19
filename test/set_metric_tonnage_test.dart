import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/analytics/data/analytics_repository.dart';
import 'package:herculex/features/analytics/domain/training_snapshot.dart';
import 'package:herculex/features/workouts/domain/session_summary.dart';

import 'support/test_database.dart';

/// EXR-05 acceptance gate: a set logged in seconds, metres or calories is real
/// work, but it is not tonnage and it is not reps. The exclusion is decided by
/// the exercise's `loggingMetric` and not by the NOT NULL zeros the row stores,
/// so this suite fails the moment `ResolvedSet.tonnageKg`, `SessionSummary` or
/// `AnalyticsRepository` goes back to reading `weightKg * reps` unconditionally.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<int> insertExercise(
    AppDatabase db, {
    required String name,
    required String loggingMetric,
    String modality = 'barbell',
    bool supportsWeightedBodyweight = false,
  }) {
    return db
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
            supportsWeightedBodyweight: Value(supportsWeightedBodyweight),
          ),
        );
  }

  Future<int> insertSession(AppDatabase db, DateTime startedAt) => db
      .into(db.workoutSessions)
      .insert(WorkoutSessionsCompanion.insert(startedAt: startedAt));

  Future<int> insertSet(
    AppDatabase db, {
    required int sessionId,
    required int exerciseId,
    required int orderIndex,
    double weightKg = 0,
    int reps = 0,
    int? durationSeconds,
    double? distanceM,
    int? calories,
    double? bodyweightKg,
  }) async {
    final weId = await db
        .into(db.workoutExercises)
        .insert(
          WorkoutExercisesCompanion.insert(
            sessionId: sessionId,
            exerciseId: exerciseId,
            orderIndex: orderIndex,
          ),
        );
    return db
        .into(db.setEntries)
        .insert(
          SetEntriesCompanion.insert(
            workoutExerciseId: weId,
            setIndex: 0,
            weightKg: weightKg,
            reps: reps,
            isCompleted: const Value(true),
            durationSeconds: Value(durationSeconds),
            distanceM: Value(distanceM),
            calories: Value(calories),
            bodyweightKg: Value(bodyweightKg),
          ),
        );
  }

  group('non-rep metrics are excluded from volume', () {
    test('a loaded sled push contributes no tonnage and no reps', () async {
      final db = await openTestDatabase();
      addTearDown(db.close);

      final sledId = await insertExercise(
        db,
        name: 'Test Sled Push',
        loggingMetric: 'weight_distance',
        modality: 'other',
      );
      final sessionId = await insertSession(db, DateTime(2026, 8, 18));
      await insertSet(
        db,
        sessionId: sessionId,
        exerciseId: sledId,
        orderIndex: 0,
        weightKg: 40,
        distanceM: 20,
      );

      final snapshot = await TrainingSnapshot.load(db);
      final sled = snapshot.sets.single;

      // The load itself is still resolved — the sled really was 40 kg.
      expect(sled.effectiveKg, 40);
      // It just is not tonnage, because there is no rep count to multiply by.
      expect(sled.tonnageKg, 0);
      expect(sled.countedReps, 0);
    });

    test('a rep-logged set in the same session still counts', () async {
      final db = await openTestDatabase();
      addTearDown(db.close);

      final squatId = await insertExercise(
        db,
        name: 'Test Back Squat',
        loggingMetric: 'weight_reps',
      );
      final sledId = await insertExercise(
        db,
        name: 'Test Sled Push',
        loggingMetric: 'weight_distance',
        modality: 'other',
      );
      final sessionId = await insertSession(db, DateTime(2026, 8, 18));
      await insertSet(
        db,
        sessionId: sessionId,
        exerciseId: squatId,
        orderIndex: 0,
        weightKg: 100,
        reps: 5,
      );
      await insertSet(
        db,
        sessionId: sessionId,
        exerciseId: sledId,
        orderIndex: 1,
        weightKg: 40,
        distanceM: 20,
      );

      final snapshot = await TrainingSnapshot.load(db);
      final summary = SessionSummary.fromSnapshot(
        snapshot: snapshot,
        sessionId: sessionId,
        name: 'Mixed',
        startedAt: DateTime(2026, 8, 18),
        endedAt: DateTime(2026, 8, 18, 1),
      );

      // Both sets are logged; only the squat is volume. The exclusion is per
      // set, not per session.
      expect(summary.totalSets, 2);
      expect(summary.tonnageKg, 500);
      expect(summary.totalReps, 5);
    });

    test('a timed hold contributes nothing but is still a set', () async {
      final db = await openTestDatabase();
      addTearDown(db.close);

      final plankId = await insertExercise(
        db,
        name: 'Test Plank',
        loggingMetric: 'time',
        modality: 'bodyweight',
      );
      final sessionId = await insertSession(db, DateTime(2026, 8, 18));
      await insertSet(
        db,
        sessionId: sessionId,
        exerciseId: plankId,
        orderIndex: 0,
        durationSeconds: 120,
      );

      final snapshot = await TrainingSnapshot.load(db);
      final summary = SessionSummary.fromSnapshot(
        snapshot: snapshot,
        sessionId: sessionId,
        name: 'Core',
        startedAt: DateTime(2026, 8, 18),
        endedAt: DateTime(2026, 8, 18, 1),
      );

      expect(summary.totalSets, 1);
      expect(summary.tonnageKg, 0);
      expect(summary.totalReps, 0);
      // The duration itself round-trips — nothing about the exclusion loses it.
      expect(snapshot.sets.single.set.durationSeconds, 120);
    });

    test('a bodyweight pull-up still contributes its own mass', () async {
      final db = await openTestDatabase();
      addTearDown(db.close);

      final pullUpId = await insertExercise(
        db,
        name: 'Test Pull-Up',
        loggingMetric: 'reps',
        modality: 'bodyweight',
        supportsWeightedBodyweight: true,
      );
      final sessionId = await insertSession(db, DateTime(2026, 8, 18));
      await insertSet(
        db,
        sessionId: sessionId,
        exerciseId: pullUpId,
        orderIndex: 0,
        reps: 8,
        bodyweightKg: 80,
      );

      final snapshot = await TrainingSnapshot.load(db);
      final pullUp = snapshot.sets.single;

      // The gate is isRepBased, not isLoaded: rep work with no external weight
      // is exactly what a pull-up is, and it must keep counting.
      expect(pullUp.tonnageKg, 640);
      expect(pullUp.countedReps, 8);
    });
  });

  group('AnalyticsRepository respects the metric', () {
    test('weeklyTonnage ignores a distance-logged set', () async {
      final db = await openTestDatabase();
      addTearDown(db.close);

      final squatId = await insertExercise(
        db,
        name: 'Test Back Squat',
        loggingMetric: 'weight_reps',
      );
      final sledId = await insertExercise(
        db,
        name: 'Test Sled Push',
        loggingMetric: 'weight_distance',
        modality: 'other',
      );
      final sessionId = await insertSession(db, DateTime.now());
      await insertSet(
        db,
        sessionId: sessionId,
        exerciseId: squatId,
        orderIndex: 0,
        weightKg: 100,
        reps: 5,
      );
      // A carry that someone also typed a rep count into: the numbers alone
      // would make this tonnage, the metric is what stops it.
      await insertSet(
        db,
        sessionId: sessionId,
        exerciseId: sledId,
        orderIndex: 1,
        weightKg: 40,
        reps: 3,
        distanceM: 20,
      );

      final weekly = await AnalyticsRepository(db).weeklyTonnage(weeks: 1);
      expect(weekly, hasLength(1));
      expect(weekly.single.tonnageKg, 500);
    });

    test('topOneRms offers no 1RM for a duration-only exercise', () async {
      final db = await openTestDatabase();
      addTearDown(db.close);

      final plankId = await insertExercise(
        db,
        name: 'Test Weighted Plank',
        loggingMetric: 'time',
        modality: 'bodyweight',
      );
      final squatId = await insertExercise(
        db,
        name: 'Test Back Squat',
        loggingMetric: 'weight_reps',
      );
      final sessionId = await insertSession(db, DateTime.now());
      // Deliberately given a weight and a rep count so the estimator *could*
      // produce a number if the metric were not consulted.
      await insertSet(
        db,
        sessionId: sessionId,
        exerciseId: plankId,
        orderIndex: 0,
        weightKg: 20,
        reps: 3,
        durationSeconds: 60,
      );
      await insertSet(
        db,
        sessionId: sessionId,
        exerciseId: squatId,
        orderIndex: 1,
        weightKg: 100,
        reps: 5,
      );

      final top = await AnalyticsRepository(db).topOneRms();
      expect(top.map((p) => p.exerciseId), isNot(contains(plankId)));
      expect(top.map((p) => p.exerciseId), contains(squatId));
    });
  });
}
