import 'package:drift/drift.dart';
import 'package:herculex/core/utils/clock.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/analytics/domain/training_snapshot.dart';
import 'package:herculex/features/health/data/health_service.dart';
import 'package:herculex/features/profile/domain/profile.dart';
import 'package:herculex/features/workouts/domain/workout_energy_estimator.dart';

/// Loads only this session, including actual completed warmups. No health
/// permissions are requested here and raw heart-rate data stays on the device.
class WorkoutEnergyService {
  final AppDatabase _db;
  final Clock _clock;
  final HealthService? _health;

  WorkoutEnergyService(this._db, this._clock, [this._health]);

  Future<WorkoutEnergyEstimate> estimate({
    required WorkoutSessionData session,
    Profile? profile,
    DateTime? endedAt,
    bool readHeartRate = false,
  }) async {
    final end = endedAt ?? session.endedAt ?? _clock.now();
    final snapshot = await TrainingSnapshot.load(
      _db,
      sessionId: session.id,
      includeWarmups: true,
    );
    final reference = session.startedAt;
    final day =
        '${reference.year.toString().padLeft(4, '0')}-'
        '${reference.month.toString().padLeft(2, '0')}-'
        '${reference.day.toString().padLeft(2, '0')}';
    final measurements =
        await (_db.select(_db.bodyMeasurements)
              ..where(
                (t) =>
                    t.deletedAt.isNull() &
                    t.dateIso.isSmallerOrEqualValue(day) &
                    t.metric.isIn(const ['bodyweight', 'body_fat']),
              )
              ..orderBy([
                (t) => OrderingTerm.desc(t.dateIso),
                (t) => OrderingTerm.desc(t.id),
              ]))
            .get();
    double? weight;
    double? bf;
    for (final row in measurements) {
      final date = DateTime.tryParse(row.dateIso);
      if (date == null || !row.value.isFinite) continue;
      final age = DateTime(
        reference.year,
        reference.month,
        reference.day,
      ).difference(date).inDays;
      if (age < 0) continue;
      if (row.metric == 'bodyweight' &&
          age <= 180 &&
          weight == null &&
          WorkoutEnergyEstimator.validWeight(row.value)) {
        weight = row.value;
      }
      if (row.metric == 'body_fat' &&
          age <= 90 &&
          bf == null &&
          row.value >= 3 &&
          row.value <= 65) {
        bf = row.value;
      }
    }
    // A bodyweight recorded with the set is preferable to today's profile
    // when estimating an old session without a dated weight measurement.
    final recordedWeights =
        snapshot.sets
            .map((s) => s.set.bodyweightKg)
            .where(WorkoutEnergyEstimator.validWeight)
            .cast<double>()
            .toList()
          ..sort();
    weight ??= recordedWeights.isEmpty
        ? profile?.weightKg
        : recordedWeights[recordedWeights.length ~/ 2];
    final heartRates =
        readHeartRate &&
            _health != null &&
            snapshot.sets.any((s) => s.exercise.category == 'cardio')
        ? await _health.readWorkoutHeartRates(session.startedAt, end)
        : const <WorkoutHeartRate>[];
    return WorkoutEnergyEstimator.estimate(
      snapshot: snapshot,
      sessionId: session.id,
      startedAt: session.startedAt,
      endedAt: end,
      profile: profile,
      userWeightKg: weight,
      bodyFatPercent: bf,
      heartRates: heartRates,
    );
  }
}
