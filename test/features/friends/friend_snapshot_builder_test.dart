import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/analytics/domain/training_snapshot.dart';
import 'package:herculex/features/friends/domain/friend_snapshot_builder.dart';
import 'package:herculex/features/gamification/domain/level_progress.dart';
import 'package:herculex/features/gamification/domain/strength_standards.dart';
import 'package:herculex/features/gamification/domain/strength_tier_evaluator.dart';
import 'package:herculex/features/profile/domain/profile.dart';
import 'package:herculex/features/workouts/domain/set_type.dart';

ExerciseCatalogData _ex(int id, String name, {String? slug}) =>
    ExerciseCatalogData(
      id: id,
      name: name,
      slug: slug,
      primaryMuscle: 'Chest',
      equipment: 'Barbell',
      mechanics: 'compound',
      force: 'push',
      plane: 'horizontal',
      defaultRestSeconds: 120,
      isCustom: false,
      category: 'strength',
      modality: 'barbell',
      cnsScore: 5,
      recoveryImpact: 3,
      loggingMetric: 'weight_reps',
      supportsWeightedBodyweight: false,
      isReviewed: true,
    );

final _bench = _ex(1, 'Bench Press', slug: 'barbell-bench-press');
final _row = _ex(2, 'Barbell Row');

var _id = 0;

ResolvedSet _set(
  ExerciseCatalogData ex,
  DateTime at, {
  double kg = 100,
  int reps = 5,
  String? buddy,
}) {
  final id = ++_id;
  return ResolvedSet(
    session: WorkoutSessionData(
      id: id,
      startedAt: at,
      name: 'S$id',
      buddySessionId: buddy,
    ),
    workoutExercise: WorkoutExerciseData(
      id: id,
      sessionId: id,
      exerciseId: ex.id,
      orderIndex: 0,
      plannedAllowsAdvancedTechniques: false,
    ),
    exercise: ex,
    set: SetEntryData(
      id: id,
      workoutExerciseId: id,
      setIndex: 0,
      weightKg: kg,
      reps: reps,
      isWarmup: false,
      isCompleted: true,
      completedAt: at,
      setType: 'standard',
    ),
    setType: SetType.standard,
    bands: const [],
    accessoryNames: const [],
    forearmMultiplier: 1,
  );
}

void main() {
  const builder = FriendSnapshotBuilder();
  final now = DateTime(2026, 10, 9, 18);
  DateTime daysAgo(int d) => now.subtract(Duration(days: d));

  StrengthAssessment strength(double benchRatio) => StrengthAssessment(
    tier: LevelBand.novice,
    sex: BiologicalSex.male,
    bests: {
      StrengthLift.bench: LiftBest(
        lift: StrengthLift.bench,
        logged: benchRatio,
      ),
    },
  );

  test('a PR must beat history; a first attempt is not a PR', () {
    final training = TrainingSnapshot(
      exerciseMuscles: const [],
      sets: [
        _set(_bench, daysAgo(40), kg: 100),
        _set(_bench, daysAgo(3), kg: 110), // PR
        _set(_row, daysAgo(2), kg: 80), // first ever row
      ],
    );
    final s = builder.build(
      training: training,
      strength: strength(1.3),
      levelTitle: 'Intermediate I',
      completedWorkouts: 3,
      asOf: now,
    );
    expect(s.recentPrs.map((p) => p.exercise), ['Bench Press']);
    expect(s.lifts.single.lift, StrengthLift.bench);
    // 110 × 5: the average of Epley and Brzycki.
    expect(s.lifts.single.e1rmKg, greaterThan(120));
    expect(s.lifts.single.lifterTopPct, isNotNull);
  });

  test('groups buddy sessions with tonnage and the top set', () {
    final training = TrainingSnapshot(
      exerciseMuscles: const [],
      sets: [
        _set(_bench, daysAgo(1), kg: 100, reps: 5, buddy: 'b1'),
        _set(_row, daysAgo(1), kg: 60, reps: 10, buddy: 'b1'),
        _set(_bench, daysAgo(1), kg: 50, reps: 10),
      ],
    );
    final s = builder.build(
      training: training,
      strength: StrengthAssessment.empty,
      levelTitle: '',
      completedWorkouts: 0,
      asOf: now,
    );
    final b = s.buddySessions.single;
    expect(b.buddySessionId, 'b1');
    expect(b.sets, 2);
    expect(b.tonnageKg, 500 + 600);
    expect(b.topExercise, 'Bench Press');
    expect(b.topKg, 100);
  });

  test('goal only when start, current and target are all known', () {
    final empty = TrainingSnapshot(sets: const [], exerciseMuscles: const []);
    final none = builder.build(
      training: empty,
      strength: StrengthAssessment.empty,
      levelTitle: '',
      completedWorkouts: 0,
      asOf: now,
      currentBodyweightKg: 80,
    );
    expect(none.goal, isNull);
    final some = builder.build(
      training: empty,
      strength: StrengthAssessment.empty,
      levelTitle: '',
      completedWorkouts: 0,
      asOf: now,
      goalStartKg: 90,
      currentBodyweightKg: 85,
      goalTargetKg: 80,
    );
    expect(some.goal!.progress, closeTo(0.5, 1e-9));
  });
}
