import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/analytics/domain/training_snapshot.dart';
import 'package:herculex/features/profile/domain/profile.dart';
import 'package:herculex/features/workouts/domain/session_summary.dart';
import 'package:herculex/features/workouts/domain/set_type.dart';
import 'package:herculex/features/workouts/domain/workout_energy_estimator.dart';

final start = DateTime(2026, 10, 28, 10);
const profile = Profile(
  goal: FitnessGoal.maintenance,
  activityLevel: ActivityLevel.active,
  weightKg: 80,
  heightCm: 180,
  ageYears: 30,
  sex: BiologicalSex.male,
);

ResolvedSet entry({
  int id = 1,
  int sessionId = 1,
  String name = 'Back Squat',
  String category = 'strength',
  String mechanics = 'compound',
  String muscle = 'Quads',
  String pattern = 'squat',
  String metric = 'weight_reps',
  String force = 'push',
  String type = 'standard',
  String? meta,
  int reps = 10,
  double weight = 80,
  int? duration,
  double? distance,
  int? calories,
  int? rpe = 80,
  bool completed = true,
  bool warmup = false,
  int? atSeconds = 60,
}) => ResolvedSet(
  session: WorkoutSessionData(id: sessionId, startedAt: start),
  workoutExercise: WorkoutExerciseData(
    id: id,
    sessionId: sessionId,
    exerciseId: id,
    orderIndex: id,
    plannedAllowsAdvancedTechniques: false,
  ),
  exercise: ExerciseCatalogData(
    id: id,
    name: name,
    primaryMuscle: muscle,
    equipment: 'barbell',
    mechanics: mechanics,
    force: force,
    plane: 'axial',
    defaultRestSeconds: 120,
    isCustom: false,
    category: category,
    movementPattern: pattern,
    modality: 'barbell',
    cnsScore: 3,
    recoveryImpact: 3,
    loggingMetric: metric,
    supportsWeightedBodyweight: false,
    isReviewed: true,
  ),
  set: SetEntryData(
    id: id,
    workoutExerciseId: id,
    setIndex: id,
    weightKg: weight,
    reps: reps,
    rpeX10: rpe,
    isWarmup: warmup,
    isCompleted: completed,
    completedAt: atSeconds == null
        ? null
        : start.add(Duration(seconds: atSeconds)),
    setType: type,
    setTypeMetaJson: meta,
    durationSeconds: duration,
    distanceM: distance,
    calories: calories,
  ),
  setType: SetType.fromId(type),
  bands: const [],
  accessoryNames: const [],
  forearmMultiplier: 1,
);

WorkoutEnergyEstimate estimate(
  List<ResolvedSet> sets, {
  int seconds = 3600,
  Profile? person = profile,
  double? bf,
  double? weight,
  List<WorkoutHeartRate> hr = const [],
}) => WorkoutEnergyEstimator.estimate(
  snapshot: TrainingSnapshot(sets: sets, exerciseMuscles: const []),
  sessionId: 1,
  startedAt: start,
  endedAt: start.add(Duration(seconds: seconds)),
  profile: person,
  bodyFatPercent: bf,
  userWeightKg: weight,
  heartRates: hr,
);

void main() {
  test('empty and incomplete sessions earn no calories or minimum bonus', () {
    expect(estimate([]).activeKcal, 0);
    expect(estimate([entry(completed: false)]).activeKcal, 0);
    expect(estimate([entry(reps: 0)]).activeKcal, 0);
    expect(estimate([entry()], seconds: 0).activeKcal, 0);
    expect(estimate([entry()], seconds: -1).activeKcal, 0);
  });

  test('leaving the app open does not accrue endless rest calories', () {
    final short = estimate([entry()], seconds: 300);
    final long = estimate([entry()], seconds: 7200);
    expect(long.workSeconds, 30);
    expect(long.restSeconds, 7170);
    expect(long.conservativeKcal, short.conservativeKcal);
    expect(long.activeKcal, lessThan(15));
  });

  test('more completed sets and repetitions increase actual work', () {
    final one = estimate([entry()]);
    expect(estimate([entry(reps: 20)]).workKcal, greaterThan(one.workKcal));
    expect(
      estimate([entry(), entry(id: 2, atSeconds: 240)]).workKcal,
      closeTo(one.workKcal * 2, 0.001),
    );
  });

  test('load and RPE have bounded effects, with no CNS multiplier', () {
    expect(
      estimate([entry(weight: 120)]).workKcal,
      greaterThan(estimate([entry(weight: 20)]).workKcal),
    );
    expect(
      estimate([entry(rpe: 100)]).workKcal,
      greaterThan(estimate([entry(rpe: 50)]).workKcal),
    );
    expect(
      estimate([entry(type: 'forced')]).workKcal,
      estimate([entry()]).workKcal,
    );
  });

  test('compound lower-body work exceeds arm isolation and static holds', () {
    final squat = estimate([entry()]);
    final curl = estimate([
      entry(mechanics: 'isolation', muscle: 'Biceps', pattern: 'isolation'),
    ]);
    final plank = estimate([
      entry(name: 'Plank', force: 'static', metric: 'time', duration: 30),
    ]);
    expect(squat.workKcal, greaterThan(curl.workKcal));
    expect(curl.workKcal, greaterThan(plank.workKcal));
  });

  test('completed warmups count, at reduced intensity', () {
    expect(estimate([entry(warmup: true)]).workKcal, greaterThan(0));
    expect(
      estimate([entry(warmup: true)]).workKcal,
      lessThan(estimate([entry()]).workKcal),
    );
  });

  test(
    'partial and pause reps affect work time without invented drop reps',
    () {
      expect(estimate([entry(type: 'partials')]).workSeconds, 15);
      expect(
        estimate([
          entry(type: 'pause', meta: '{"pauseSeconds":2}'),
        ]).workSeconds,
        50,
      );
      expect(
        estimate([entry(type: 'drop', meta: '{"drops":5}')]).workSeconds,
        30,
      );
      expect(estimate([entry(type: 'pause', meta: 'invalid')]).workSeconds, 30);
      expect(
        estimate([
          entry(type: 'myo_reps', meta: '{"miniSets":[3,3]}'),
        ]).workSeconds,
        48,
      );
    },
  );

  test(
    'unknown timestamps fit short sessions and never use all elapsed as work',
    () {
      final one = entry(atSeconds: null);
      final result = estimate([one]);
      expect(result.inferredTiming, isTrue);
      expect(result.workSeconds, 30);
      expect(estimate([one], seconds: 5).workSeconds, 5);
      expect(estimate([one], seconds: 7200).activeKcal, result.activeKcal);
    },
  );

  test(
    'overlapping sets and duplicate completion stamps do not double count',
    () {
      final result = estimate([entry(), entry(id: 2)]);
      expect(result.workSeconds, 30);
      expect(result.workKcal, estimate([entry()]).workKcal);
      expect(estimate([entry(sessionId: 2)]).activeKcal, 0);
      expect(estimate([entry(atSeconds: 3601)]).activeKcal, 0);
      expect(estimate([entry(atSeconds: -10)]).activeKcal, 0);
    },
  );

  test('negative or absent work cannot create a calorie estimate', () {
    expect(estimate([entry(reps: -5)]).workKcal, 0);
    expect(estimate([entry(metric: 'time', duration: -10)]).workKcal, 0);
    expect(
      estimate([entry(metric: 'distance', distance: double.nan)]).workKcal,
      0,
    );
  });

  test('resting baseline uses body composition or demographic predictors', () {
    double resting({Profile person = profile, double? bf}) =>
        WorkoutEnergyEstimator.restingKcalPerMinute(
          weightKg: 80,
          profile: person,
          bodyFatPercent: bf,
        );
    expect(resting(), closeTo(1780 / 1440, 0.00001));
    expect(
      resting(person: profile.copyWith(sex: BiologicalSex.female)),
      closeTo(1614 / 1440, 0.00001),
    );
    expect(resting(bf: 20), closeTo((19.7 * 64 + 413) / 1440, 0.00001));
    expect(resting(bf: 40), lessThan(resting(bf: 20)));
    expect(resting(bf: double.nan), resting());
  });

  test(
    'weight affects expenditure and invalid anthropometrics stay finite',
    () {
      expect(
        estimate([entry()], weight: 100).workKcal,
        greaterThan(estimate([entry()], weight: 60).workKcal),
      );
      for (final mass in [double.nan, double.infinity, -1.0, 10000.0]) {
        final result = estimate([entry()], weight: mass, bf: double.nan);
        expect(result.usedFallbackWeight, isTrue);
        expect(result.conservativeKcal.isFinite, isTrue);
        expect(result.activeKcal, greaterThanOrEqualTo(0));
      }
    },
  );

  test('console intervals do not replace or double count strength work', () {
    final bike = entry(
      id: 2,
      name: 'Bike',
      category: 'cardio',
      metric: 'time_calories',
      reps: 0,
      duration: 300,
      calories: 80,
      atSeconds: 600,
    );
    final strength = estimate([entry()]);
    final cardio = estimate([bike]);
    final mixed = estimate([entry(), bike]);
    expect(
      mixed.workKcal,
      closeTo(strength.workKcal + cardio.workKcal, 0.00001),
    );
    expect(mixed.workKcal, lessThan(80 + strength.workKcal));
    expect(estimate([entry(calories: 500)]).workKcal, strength.workKcal);
  });

  test(
    'a timed interval is capped by the session, even for absurd console kcal',
    () {
      final result = estimate([
        entry(
          name: 'Bike',
          category: 'cardio',
          metric: 'time_calories',
          duration: 3600,
          calories: 100000,
          atSeconds: 60,
        ),
      ], seconds: 60);
      expect(result.workSeconds, 60);
      expect(result.activeKcal, lessThan(15));
    },
  );

  test('sustained cardio uses dense HR data, but strength does not', () {
    final samples = [
      for (var i = 0; i < 300; i += 10)
        WorkoutHeartRate(start.add(Duration(seconds: i)), 150),
    ];
    final cardio = entry(
      name: 'Bike',
      category: 'cardio',
      metric: 'time',
      duration: 300,
      atSeconds: 300,
    );
    expect(estimate([cardio], hr: samples).usedHeartRate, isTrue);
    expect(
      estimate([cardio], hr: samples).workKcal,
      lessThanOrEqualTo(estimate([cardio]).workKcal * 1.1 + 0.0001),
    );
    final strength = entry(metric: 'reps_time', duration: 300, atSeconds: 300);
    expect(estimate([strength], hr: samples).usedHeartRate, isFalse);
    expect(
      estimate([strength], hr: samples).workKcal,
      estimate([strength]).workKcal,
    );
  });

  test(
    'sparse, duplicate, invalid or out-of-window HR is never extrapolated',
    () {
      final cardio = entry(
        name: 'Bike',
        category: 'cardio',
        metric: 'time',
        duration: 300,
        atSeconds: 300,
      );
      final sparse = [
        for (var i = 0; i < 100; i++) WorkoutHeartRate(start, 150),
      ];
      final invalid = [
        for (var i = 0; i < 300; i += 10)
          WorkoutHeartRate(start.add(Duration(seconds: i)), 999),
      ];
      expect(estimate([cardio], hr: sparse).usedHeartRate, isFalse);
      expect(estimate([cardio], hr: invalid).usedHeartRate, isFalse);
      expect(
        estimate(
          [cardio],
          hr: [WorkoutHeartRate(start.subtract(const Duration(days: 1)), 150)],
        ).usedHeartRate,
        isFalse,
      );
    },
  );

  test('rounds down once, to 5 kcal, after the conservative discount', () {
    const result = WorkoutEnergyEstimate(workKcal: 101.9, recoveryKcal: 10);
    expect(result.activeKcal, 100);
    expect(result.activeKcal, lessThanOrEqualTo(result.conservativeKcal));
    expect(const WorkoutEnergyEstimate(workKcal: 4).activeKcal, 0);
  });

  test('saved zero stays zero and old summaries use the same estimator', () {
    final snapshot = TrainingSnapshot(
      sets: [entry()],
      exerciseMuscles: const [],
    );
    SessionSummary summary(int? saved) => SessionSummary.fromSnapshot(
      snapshot: snapshot,
      sessionId: 1,
      name: 'Test',
      startedAt: start,
      endedAt: start.add(const Duration(hours: 1)),
      userWeightKg: 80,
      savedCalories: saved,
    );
    expect(summary(0).caloriesBurned, 0);
    expect(
      summary(null).caloriesBurned,
      estimate([entry()], person: null, weight: 80).activeKcal,
    );
  });
}
