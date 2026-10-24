import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:herculex/core/utils/clock.dart';
import 'package:herculex/data/local/database.dart';

/// Captures intent before destructive workout edits and end-session cleanup.
class WorkoutReportJournal {
  WorkoutReportJournal(this.db, this.clock);
  final AppDatabase db;
  final Clock clock;

  Future<Map<String, Object?>> currentPlan(
    int sessionId, {
    bool prescribed = false,
  }) async {
    final exercises =
        await (db.select(db.workoutExercises)
              ..where(
                (e) => e.sessionId.equals(sessionId) & e.deletedAt.isNull(),
              )
              ..orderBy([(e) => OrderingTerm.asc(e.orderIndex)]))
            .get();
    final ids = exercises.map((e) => e.id).toList();
    final sets = ids.isEmpty
        ? <SetEntryData>[]
        : await (db.select(db.setEntries)..where(
                (s) => s.workoutExerciseId.isIn(ids) & s.deletedAt.isNull(),
              ))
              .get();
    final catalog = exercises.isEmpty
        ? <ExerciseCatalogData>[]
        : await (db.select(
            db.exerciseCatalog,
          )..where((e) => e.id.isIn(exercises.map((e) => e.exerciseId)))).get();
    final byId = {for (final e in catalog) e.id: e};
    return {
      'prescribed': prescribed,
      'exercises': [
        for (final e in exercises)
          {
            'rowId': e.id,
            'exerciseId': e.exerciseId,
            'name': byId[e.exerciseId]?.name ?? 'Exercise',
            'muscle': byId[e.exerciseId]?.primaryMuscle ?? 'Unknown',
            'order': e.orderIndex,
            'variant': e.equipmentVariant ?? byId[e.exerciseId]?.modality,
            'machine': e.machineConfigJson,
            'sets': [
              for (final s in sets.where(
                (s) => s.workoutExerciseId == e.id && !s.isWarmup,
              ))
                {
                  'id': s.id,
                  'min': s.plannedRepsMin,
                  'max': s.plannedRepsMax,
                  'weight': s.plannedWeightKg,
                  'rpe': s.plannedRpeX10,
                },
            ],
          },
      ],
    };
  }

  Future<void> capture(int sessionId, {bool prescribed = false}) async {
    final existing = await (db.select(
      db.workoutReportPlans,
    )..where((p) => p.sessionId.equals(sessionId))).getSingleOrNull();
    if (existing != null) return;
    await db
        .into(db.workoutReportPlans)
        .insert(
          WorkoutReportPlansCompanion.insert(
            sessionId: Value(sessionId),
            planJson: jsonEncode(
              await currentPlan(sessionId, prescribed: prescribed),
            ),
            capturedAt: clock.now(),
          ),
          mode: InsertMode.insertOrIgnore,
        );
  }

  Future<void> record(
    int sessionId,
    String kind,
    Map<String, Object?> details, {
    String? reason,
  }) async {
    await capture(sessionId);
    await db
        .into(db.workoutReportEvents)
        .insert(
          WorkoutReportEventsCompanion.insert(
            sessionId: sessionId,
            kind: kind,
            detailJson: jsonEncode(details),
            occurredAt: clock.now(),
            reason: Value(reason),
          ),
        );
  }

  Future<void> beforeFinish(int sessionId) async {
    await capture(sessionId);
    final session = await (db.select(
      db.workoutSessions,
    )..where((s) => s.id.equals(sessionId))).getSingle();
    final prior =
        await (db.select(db.workoutReportEvents)..where(
              (e) =>
                  e.sessionId.equals(sessionId) & e.kind.equals('finish_plan'),
            ))
            .getSingleOrNull();
    if (session.endedAt != null && prior != null) return;
    await db.transaction(() async {
      await (db.delete(db.workoutReportEvents)..where(
            (e) => e.sessionId.equals(sessionId) & e.kind.equals('finish_plan'),
          ))
          .go();
      await record(sessionId, 'finish_plan', await currentPlan(sessionId));
    });
  }

  Future<void> forExercise(
    int rowId,
    String kind, {
    Map<String, Object?> details = const {},
    String? reason,
  }) async {
    final e = await (db.select(
      db.workoutExercises,
    )..where((e) => e.id.equals(rowId))).getSingleOrNull();
    if (e == null) return;
    final catalog = await (db.select(
      db.exerciseCatalog,
    )..where((c) => c.id.equals(e.exerciseId))).getSingleOrNull();
    await record(e.sessionId, kind, {
      'rowId': rowId,
      'exerciseId': e.exerciseId,
      'name': catalog?.name ?? 'Exercise',
      ...details,
    }, reason: reason);
  }
}
