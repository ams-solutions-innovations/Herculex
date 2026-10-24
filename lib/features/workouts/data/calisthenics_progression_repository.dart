import 'package:drift/drift.dart';
import 'package:herculex/core/utils/clock.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/workouts/domain/calisthenics_progression.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CalisthenicsProgressionRepository {
  CalisthenicsProgressionRepository(this._db, this._clock);
  final AppDatabase _db;
  final Clock _clock;

  Stream<Map<String, CalisthenicsRecommendation>> watchRecommendations() => _db
      .customSelect(
        'SELECT 1',
        readsFrom: {
          _db.workoutSessions,
          _db.workoutExercises,
          _db.setEntries,
          _db.setBands,
          _db.exerciseCatalog,
        },
      )
      .watch()
      .asyncMap((_) => recommendations());

  Future<Map<String, CalisthenicsRecommendation>> recommendations({
    int? excludingSessionId,
  }) async {
    final now = _clock.now();
    final slugs = {
      ...calisthenicsPaths.expand((p) => p.slugs),
      'band-assisted-dip',
      'band-assisted-pull-up-wide-grip',
      'band-assisted-pull-up-neutral-grip',
    };
    final query = _db.select(_db.setEntries).join([
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
    ]);
    query.where(
      _db.exerciseCatalog.slug.isIn(slugs) &
          _db.exerciseCatalog.deletedAt.isNull() &
          _db.workoutExercises.deletedAt.isNull() &
          _db.workoutSessions.deletedAt.isNull() &
          _db.setEntries.deletedAt.isNull() &
          _db.setEntries.isCompleted.equals(true) &
          _db.setEntries.isWarmup.equals(false) &
          _db.workoutSessions.endedAt.isNotNull() &
          _db.workoutSessions.startedAt.isBiggerOrEqualValue(
            now.subtract(
              const Duration(days: CalisthenicsProgression.historyDays),
            ),
          ) &
          (excludingSessionId == null
              ? const Constant(true)
              : _db.workoutSessions.id.equals(excludingSessionId).not()),
    );
    final rows = await query.get();
    final setIds = rows.map((r) => r.readTable(_db.setEntries).id).toList();
    final bands = setIds.isEmpty
        ? <SetBandData>[]
        : await (_db.select(
                _db.setBands,
              )..where((t) => t.setEntryId.isIn(setIds) & t.deletedAt.isNull()))
              .get();
    final bySet = <int, List<String>>{};
    for (final band in bands) {
      bySet
          .putIfAbsent(band.setEntryId, () => [])
          .add('${band.bandId}:${band.count}:${band.mode}');
    }
    final grouped = <String, CalisthenicsPerformance>{};
    for (final row in rows) {
      final exercise = row.readTable(_db.exerciseCatalog);
      final we = row.readTable(_db.workoutExercises);
      final session = row.readTable(_db.workoutSessions);
      final set = row.readTable(_db.setEntries);
      final level = calisthenicsLevelFor(exercise.slug, we.equipmentVariant);
      // Kipping history deliberately cannot qualify a strict level.
      if (level == null) continue;
      final bandParts = bySet[set.id] ?? <String>[];
      bandParts.sort();
      final key = '${session.id}:${we.id}:${level.key}';
      final performance = grouped.putIfAbsent(
        key,
        () => CalisthenicsPerformance(
          sessionId: session.id,
          at: session.startedAt,
          levelKey: level.key,
          sets: [],
        ),
      );
      performance.sets.add(
        CalisthenicsSet(
          value: level.seconds ? set.durationSeconds ?? 0 : set.reps,
          load: set.weightKg,
          rpe: set.rpeX10,
          assistance: bandParts.join('|'),
          standard: set.setType == 'standard' && (set.chainsKg ?? 0) == 0,
        ),
      );
    }
    final history = grouped.values.toList();
    final prefs = await SharedPreferences.getInstance();
    final thresholdByPath = <String, double>{};
    for (final row in rows) {
      final exercise = row.readTable(_db.exerciseCatalog);
      if (exercise.slug?.startsWith('assisted-pull-up-machine-') ?? false) {
        final path = calisthenicsPathFor(exercise.slug);
        if (path != null)
          thresholdByPath[path.id] =
              prefs.getDouble('assistance_transition_${exercise.id}') ?? 6;
      }
    }
    return {
      for (final path in calisthenicsPaths)
        path.id: CalisthenicsProgression.recommend(
          path,
          history,
          now,
          machineTransitionKg: thresholdByPath[path.id] ?? 6,
        ),
    };
  }

  /// A crossing is derived from history, so reopening the picker does not
  /// announce it again and no extra unsynced readiness state is needed.
  Future<List<CalisthenicsRecommendation>> newlyReady(int sessionId) async {
    final before = await recommendations(excludingSessionId: sessionId);
    final after = await recommendations();
    return [
      for (final entry in after.entries)
        if (entry.value.ready && !(before[entry.key]?.ready ?? false))
          entry.value,
    ];
  }
}
