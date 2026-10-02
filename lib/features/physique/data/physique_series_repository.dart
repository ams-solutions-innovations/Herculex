import 'package:drift/drift.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/nutrition/domain/tdee_trend.dart';
import 'package:herculex/features/physique/domain/physique_strength_series.dart';
import 'package:herculex/features/programs/domain/primary_lift_specialization.dart';
import 'package:herculex/features/workouts/domain/logging_metric.dart';

/// Read-only chart data for the physique progress screen: bodyweight logs,
/// canonical-lift strength samples and session history (PHYS-08).
class PhysiqueSeriesRepository {
  PhysiqueSeriesRepository(this._db);

  final AppDatabase _db;

  static final Set<String> _canonicalSlugs = {
    for (final lift in PrimaryLift.values) ...lift.preferredSlugs,
  };

  static String _dayKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  Stream<List<WeightLog>> watchWeightLogs({DateTime? since}) {
    final q = _db.select(_db.bodyMeasurements)
      ..where((t) {
        var cond = t.metric.equals('bodyweight') & t.deletedAt.isNull();
        if (since != null) {
          cond = cond & t.dateIso.isBiggerOrEqualValue(_dayKey(since));
        }
        return cond;
      })
      ..orderBy([(t) => OrderingTerm.asc(t.dateIso)]);
    return q.watch().map(
      (rows) => [
        for (final r in rows) WeightLog(DateTime.parse(r.dateIso), r.value),
      ],
    );
  }

  Stream<List<StrengthSample>> watchStrengthSamples({DateTime? since}) {
    final q =
        _db.select(_db.setEntries).join([
          innerJoin(
            _db.workoutExercises,
            _db.workoutExercises.id.equalsExp(_db.setEntries.workoutExerciseId),
          ),
          innerJoin(
            _db.workoutSessions,
            _db.workoutSessions.id.equalsExp(_db.workoutExercises.sessionId),
          ),
          innerJoin(
            _db.exerciseCatalog,
            _db.exerciseCatalog.id.equalsExp(_db.workoutExercises.exerciseId),
          ),
        ])..where(
          _db.setEntries.isCompleted.equals(true) &
              _db.setEntries.isWarmup.equals(false) &
              _db.setEntries.setType.equals('standard') &
              _db.setEntries.deletedAt.isNull() &
              _db.workoutExercises.deletedAt.isNull() &
              _db.workoutSessions.deletedAt.isNull() &
              _db.exerciseCatalog.deletedAt.isNull() &
              _db.exerciseCatalog.slug.isIn(_canonicalSlugs),
        );
    return q.watch().map((rows) {
      final out = <StrengthSample>[];
      for (final r in rows) {
        final set = r.readTable(_db.setEntries);
        final session = r.readTable(_db.workoutSessions);
        final ex = r.readTable(_db.exerciseCatalog);
        final slug = ex.slug;
        if (slug == null) continue;
        final metric = LoggingMetric.fromId(ex.loggingMetric);
        if (!metric.isRepBased || !metric.isLoaded) continue;
        final date = set.completedAt ?? session.startedAt;
        if (since != null && date.isBefore(since)) continue;
        out.add(
          StrengthSample(
            date: date,
            exerciseSlug: slug,
            weightKg: set.weightKg,
            reps: set.reps,
            bodyweightKg: set.bodyweightKg,
            includesBodyweight: ex.supportsWeightedBodyweight,
          ),
        );
      }
      out.sort((a, b) => a.date.compareTo(b.date));
      return out;
    });
  }

  Stream<List<DateTime>> watchSessionDates() {
    final q = _db.select(_db.workoutSessions)
      ..where((s) => s.deletedAt.isNull() & s.endedAt.isNotNull())
      ..orderBy([(s) => OrderingTerm.asc(s.startedAt)]);
    return q.watch().map((rows) => [for (final s in rows) s.startedAt]);
  }
}
