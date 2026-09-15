import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/analytics/domain/muscle_volume_details.dart';
import 'package:herculex/features/analytics/domain/training_snapshot.dart';
import 'package:herculex/features/workouts/domain/set_type.dart';

ExerciseCatalogData _ex(
  int id, {
  String name = 'Bench Press',
  String primaryMuscle = 'Chest',
  int cns = 5,
  bool weightedBw = false,
}) => ExerciseCatalogData(
  id: id,
  name: name,
  primaryMuscle: primaryMuscle,
  equipment: 'Barbell',
  mechanics: 'compound',
  force: 'push',
  plane: 'horizontal',
  defaultRestSeconds: 120,
  isCustom: false,
  category: 'strength',
  modality: 'barbell',
  cnsScore: cns,
  recoveryImpact: 3,
  loggingMetric: 'weight_reps',
  supportsWeightedBodyweight: weightedBw,
  isReviewed: true,
);

WorkoutSessionData _session(
  int id,
  DateTime startedAt, {
  String name = 'Push Day',
}) => WorkoutSessionData(id: id, startedAt: startedAt, name: name);

WorkoutExerciseData _we(int id, int exerciseId, {int sessionId = 1}) =>
    WorkoutExerciseData(
      id: id,
      sessionId: sessionId,
      exerciseId: exerciseId,
      orderIndex: 0,
      plannedAllowsAdvancedTechniques: false,
    );

SetEntryData _set(
  int id,
  int weId, {
  double weightKg = 100,
  int reps = 10,
  int? rpeX10 = 80,
  DateTime? completedAt,
  String setType = 'standard',
}) => SetEntryData(
  id: id,
  workoutExerciseId: weId,
  setIndex: id,
  weightKg: weightKg,
  reps: reps,
  rpeX10: rpeX10,
  isWarmup: false,
  isCompleted: true,
  completedAt: completedAt,
  setType: setType,
);

ResolvedSet _resolve({
  required WorkoutSessionData session,
  required WorkoutExerciseData we,
  required ExerciseCatalogData ex,
  required SetEntryData set,
}) => ResolvedSet(
  session: session,
  workoutExercise: we,
  exercise: ex,
  set: set,
  setType: SetType.fromId(set.setType),
  bands: const [],
  accessoryNames: const [],
  forearmMultiplier: 1.0,
);

void main() {
  group('MuscleVolumeAnalyticsEngine', () {
    final now = DateTime(2026, 8, 22, 10, 0); // Saturday

    test('computes overview across muscle groups correctly', () {
      final session1 = _session(
        1,
        now.subtract(const Duration(days: 1)),
        name: 'Chest & Back',
      );
      final weBench = _we(1, 101, sessionId: 1);
      final exBench = _ex(
        101,
        name: 'Barbell Bench Press',
        primaryMuscle: 'Chest',
      );
      final set1 = _set(
        1,
        1,
        weightKg: 100,
        reps: 10,
        completedAt: now.subtract(const Duration(days: 1)),
      );
      final set2 = _set(
        2,
        1,
        weightKg: 100,
        reps: 10,
        completedAt: now.subtract(const Duration(days: 1)),
      );

      final weRow = _we(2, 102, sessionId: 1);
      final exRow = _ex(102, name: 'Barbell Row', primaryMuscle: 'Back');
      final set3 = _set(
        3,
        2,
        weightKg: 80,
        reps: 10,
        completedAt: now.subtract(const Duration(days: 1)),
      );

      final snapshot = TrainingSnapshot(
        sets: [
          _resolve(session: session1, we: weBench, ex: exBench, set: set1),
          _resolve(session: session1, we: weBench, ex: exBench, set: set2),
          _resolve(session: session1, we: weRow, ex: exRow, set: set3),
        ],
        exerciseMuscles: [
          const ExerciseMuscleData(
            id: 1,
            exerciseId: 101,
            muscle: 'Chest',
            role: 'primary',
            contribution: 1.0,
          ),
          const ExerciseMuscleData(
            id: 2,
            exerciseId: 101,
            muscle: 'Triceps',
            role: 'secondary',
            contribution: 1.0,
          ),
          const ExerciseMuscleData(
            id: 3,
            exerciseId: 102,
            muscle: 'Back',
            role: 'primary',
            contribution: 1.0,
          ),
        ],
      );

      final overview = MuscleVolumeAnalyticsEngine.computeOverview(
        snapshot: snapshot,
        asOf: now,
        timeframe: VolumeTimeframe.thisWeek,
      );

      expect(overview.totalSets, equals(3));
      expect(
        overview.totalTonnageKg,
        equals(2800.0),
      ); // (100*10)*2 + (80*10) = 2000 + 800 = 2800

      final chest = overview.groups.firstWhere((g) => g.muscle == 'Chest');
      expect(chest.tonnageKg, equals(2000.0));
      expect(chest.sets, equals(2.0));
      expect(chest.rawSets, equals(2));
      expect(chest.workoutCount, equals(1));
      expect(chest.exerciseCount, equals(1));
      expect(chest.region, equals(MuscleRegion.upper));

      final triceps = overview.groups.firstWhere((g) => g.muscle == 'Triceps');
      expect(triceps.tonnageKg, equals(1000.0)); // 2000 * 0.5 = 1000
      expect(triceps.sets, equals(1.0)); // 2 * 0.5 = 1.0
      expect(triceps.rawSets, equals(2));

      final back = overview.groups.firstWhere((g) => g.muscle == 'Back');
      expect(back.tonnageKg, equals(800.0));
      expect(back.sets, equals(1.0));
    });

    test('filters out sets outside timeframe', () {
      final oldDate = now.subtract(const Duration(days: 40));
      final recentDate = now.subtract(const Duration(days: 2));

      final sessionOld = _session(1, oldDate, name: 'Old Workout');
      final sessionRecent = _session(2, recentDate, name: 'Recent Workout');

      final weOld = _we(1, 101, sessionId: 1);
      final weRecent = _we(2, 101, sessionId: 2);
      final ex = _ex(101, name: 'Squat', primaryMuscle: 'Quads');

      final setOld = _set(1, 1, weightKg: 100, reps: 5, completedAt: oldDate);
      final setRecent = _set(
        2,
        2,
        weightKg: 120,
        reps: 5,
        completedAt: recentDate,
      );

      final snapshot = TrainingSnapshot(
        sets: [
          _resolve(session: sessionOld, we: weOld, ex: ex, set: setOld),
          _resolve(
            session: sessionRecent,
            we: weRecent,
            ex: ex,
            set: setRecent,
          ),
        ],
        exerciseMuscles: [
          const ExerciseMuscleData(
            id: 1,
            exerciseId: 101,
            muscle: 'Quads',
            role: 'primary',
            contribution: 1.0,
          ),
        ],
      );

      final overviewWeek = MuscleVolumeAnalyticsEngine.computeOverview(
        snapshot: snapshot,
        asOf: now,
        timeframe: VolumeTimeframe.thisWeek,
      );
      final quadsWeek = overviewWeek.groups.firstWhere(
        (g) => g.muscle == 'Quads',
      );
      expect(quadsWeek.sets, equals(1.0));
      expect(quadsWeek.tonnageKg, equals(600.0)); // 120 * 5

      final overviewAllTime = MuscleVolumeAnalyticsEngine.computeOverview(
        snapshot: snapshot,
        asOf: now,
        timeframe: VolumeTimeframe.allTime,
      );
      final quadsAllTime = overviewAllTime.groups.firstWhere(
        (g) => g.muscle == 'Quads',
      );
      expect(quadsAllTime.sets, equals(2.0));
      expect(quadsAllTime.tonnageKg, equals(1100.0)); // (100*5) + (120*5)
    });

    test('computes muscle detail with multiple sessions chronologically', () {
      final date1 = now.subtract(const Duration(days: 5));
      final date2 = now.subtract(const Duration(days: 1));

      final session1 = _session(1, date1, name: 'Chest Day 1');
      final session2 = _session(2, date2, name: 'Chest Day 2');

      final we1 = _we(1, 101, sessionId: 1);
      final we2 = _we(2, 102, sessionId: 2);

      final exBench = _ex(101, name: 'Bench Press', primaryMuscle: 'Chest');
      final exIncline = _ex(
        102,
        name: 'Incline Dumbbell Press',
        primaryMuscle: 'Chest',
      );

      final set1 = _set(
        1,
        1,
        weightKg: 100,
        reps: 8,
        rpeX10: 80,
        completedAt: date1,
      );
      final set2 = _set(
        2,
        2,
        weightKg: 30,
        reps: 10,
        rpeX10: 90,
        completedAt: date2,
      );

      final snapshot = TrainingSnapshot(
        sets: [
          _resolve(session: session1, we: we1, ex: exBench, set: set1),
          _resolve(session: session2, we: we2, ex: exIncline, set: set2),
        ],
        exerciseMuscles: [
          const ExerciseMuscleData(
            id: 1,
            exerciseId: 101,
            muscle: 'Chest',
            role: 'primary',
            contribution: 1.0,
          ),
          const ExerciseMuscleData(
            id: 2,
            exerciseId: 102,
            muscle: 'Chest',
            role: 'primary',
            contribution: 1.0,
          ),
        ],
      );

      final detail = MuscleVolumeAnalyticsEngine.computeMuscleDetail(
        snapshot: snapshot,
        muscle: 'Chest',
        asOf: now,
        timeframe: VolumeTimeframe.allTime,
      );

      expect(detail.muscle, equals('Chest'));
      expect(detail.workoutsCount, equals(2));
      expect(detail.distinctExercisesCount, equals(2));
      expect(detail.totalReps, equals(18)); // 8 + 10
      expect(detail.totalTonnageKg, equals(1100.0)); // (100*8) + (30*10)

      // Newest session first
      expect(detail.workouts.first.sessionId, equals(2));
      expect(detail.workouts.first.sessionName, equals('Chest Day 2'));
      expect(
        detail.workouts.first.exercises.first.exerciseName,
        equals('Incline Dumbbell Press'),
      );
      expect(detail.workouts.first.exercises.first.sets.first.reps, equals(10));
      expect(
        detail.workouts.first.exercises.first.sets.first.rpeX10,
        equals(90),
      );

      expect(detail.workouts.last.sessionId, equals(1));
      expect(detail.workouts.last.sessionName, equals('Chest Day 1'));
    });
  });
}
