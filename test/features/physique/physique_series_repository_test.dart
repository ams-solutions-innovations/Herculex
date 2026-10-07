import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/physique/data/physique_series_repository.dart';

import '../../support/test_database.dart';

void main() {
  late AppDatabase db;
  late PhysiqueSeriesRepository repo;

  setUp(() async {
    db = await openTestDatabase();
    repo = PhysiqueSeriesRepository(db);
  });
  tearDown(() => db.close());

  Future<int> exId(String slug, {bool weightedBw = false}) => db
      .into(db.exerciseCatalog)
      .insert(
        ExerciseCatalogCompanion.insert(
          slug: Value(slug),
          name: slug,
          primaryMuscle: 'Back',
          equipment: 'Barbell',
          mechanics: 'compound',
          force: 'pull',
          plane: 'horizontal',
          supportsWeightedBodyweight: Value(weightedBw),
        ),
      );

  Future<int> session({DateTime? start, DateTime? end, bool deleted = false}) =>
      db
          .into(db.workoutSessions)
          .insert(
            WorkoutSessionsCompanion.insert(
              startedAt: start ?? DateTime(2026, 9, 1, 10),
              endedAt: Value(end),
              deletedAt: Value(deleted ? DateTime(2026, 9, 2) : null),
            ),
          );

  Future<int> workoutEx(
    int sessionId,
    int exerciseId, {
    bool deleted = false,
  }) => db
      .into(db.workoutExercises)
      .insert(
        WorkoutExercisesCompanion.insert(
          sessionId: sessionId,
          exerciseId: exerciseId,
          orderIndex: 0,
          deletedAt: Value(deleted ? DateTime(2026, 9, 2) : null),
        ),
      );

  Future<int> setRow(
    int weId, {
    double kg = 100,
    int reps = 5,
    bool completed = true,
    bool warmup = false,
    String type = 'standard',
    bool deleted = false,
    DateTime? completedAt,
    double? bodyweight,
  }) => db
      .into(db.setEntries)
      .insert(
        SetEntriesCompanion.insert(
          workoutExerciseId: weId,
          setIndex: 0,
          weightKg: kg,
          reps: reps,
          isCompleted: Value(completed),
          isWarmup: Value(warmup),
          setType: Value(type),
          completedAt: Value(completedAt),
          bodyweightKg: Value(bodyweight),
          deletedAt: Value(deleted ? DateTime(2026, 9, 2) : null),
        ),
      );

  test(
    'watchWeightLogs: bodyweight only, undeleted, oldest first, since',
    () async {
      Future<void> m(String d, String metric, double v, {bool del = false}) =>
          db
              .into(db.bodyMeasurements)
              .insert(
                BodyMeasurementsCompanion.insert(
                  dateIso: d,
                  metric: metric,
                  value: v,
                  deletedAt: Value(del ? DateTime(2026, 9, 9) : null),
                ),
              );
      await m('2026-09-10', 'bodyweight', 81);
      await m('2026-09-01', 'bodyweight', 82);
      await m('2026-09-05', 'waist', 90);
      await m('2026-09-06', 'bodyweight', 99, del: true);

      final all = await repo.watchWeightLogs().first;
      expect(all.map((w) => w.kg), [82, 81]);
      expect(all.first.date, DateTime(2026, 9, 1));
      final since = await repo
          .watchWeightLogs(since: DateTime(2026, 9, 5))
          .first;
      expect(since.map((w) => w.kg), [81]);
    },
  );

  test('watchStrengthSamples keeps only qualifying canonical sets', () async {
    final squat = await exId('barbell-back-squat');
    final pullUp = await exId('pull-up', weightedBw: true);
    final curl = await exId('some-curl');
    final s = await session();
    final weSquat = await workoutEx(s, squat);
    final wePull = await workoutEx(s, pullUp);
    final weOther = await workoutEx(s, curl);

    await setRow(
      weSquat,
      kg: 140,
      reps: 5,
      completedAt: DateTime(2026, 9, 1, 11),
    );
    await setRow(weSquat, warmup: true);
    await setRow(weSquat, completed: false);
    await setRow(weSquat, type: 'drop');
    await setRow(weSquat, deleted: true);
    await setRow(weOther, kg: 50);
    await setRow(wePull, kg: 10, reps: 8, bodyweight: 80);

    final deadSession = await session(deleted: true);
    await setRow(await workoutEx(deadSession, squat));
    await setRow(await workoutEx(s, squat, deleted: true));

    final samples = await repo.watchStrengthSamples().first;
    expect(samples, hasLength(2));
    final sq = samples.firstWhere(
      (x) => x.exerciseSlug == 'barbell-back-squat',
    );
    expect(sq.weightKg, 140);
    expect(sq.reps, 5);
    expect(sq.date, DateTime(2026, 9, 1, 11));
    expect(sq.includesBodyweight, isFalse);
    final pu = samples.firstWhere((x) => x.exerciseSlug == 'pull-up');
    expect(pu.bodyweightKg, 80);
    expect(pu.includesBodyweight, isTrue);
    // No completedAt: falls back to the session start.
    expect(pu.date, DateTime(2026, 9, 1, 10));
  });

  test(
    'watchSessionDates: finished, undeleted sessions oldest first',
    () async {
      await session(start: DateTime(2026, 9, 3), end: DateTime(2026, 9, 3, 1));
      await session(start: DateTime(2026, 9, 1), end: DateTime(2026, 9, 1, 1));
      await session(start: DateTime(2026, 9, 2));
      await session(
        start: DateTime(2026, 9, 4),
        end: DateTime(2026, 9, 4, 1),
        deleted: true,
      );
      expect(await repo.watchSessionDates().first, [
        DateTime(2026, 9, 1),
        DateTime(2026, 9, 3),
      ]);
    },
  );

  test(
    'watchStrengthSamples emits again when a qualifying set arrives',
    () async {
      final squat = await exId('barbell-back-squat');
      final we = await workoutEx(await session(), squat);
      final emissions = <int>[];
      final sub = repo.watchStrengthSamples().listen(
        (l) => emissions.add(l.length),
      );
      await pumpEventQueue();
      await setRow(we);
      await pumpEventQueue();
      await sub.cancel();
      expect(emissions.first, 0);
      expect(emissions.last, 1);
    },
  );
}
