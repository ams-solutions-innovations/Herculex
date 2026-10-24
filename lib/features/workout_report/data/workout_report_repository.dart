import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:herculex/core/utils/clock.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/analytics/domain/training_snapshot.dart';
import 'package:herculex/features/programs/domain/session_completion.dart';
import 'package:herculex/features/workout_report/domain/workout_report.dart';
import 'package:herculex/features/workout_report/domain/workout_report_engine.dart';

/// Local-only, reproducible reports. Never sends health-derived facts to AI or sync.
class WorkoutReportRepository {
  WorkoutReportRepository(this.db, this.clock);
  final AppDatabase db;
  final Clock clock;

  Stream<WorkoutReportData?> watch(int sessionId) => db
      .customSelect(
        'SELECT 1',
        readsFrom: {
          db.workoutReports,
          db.workoutSessions,
          db.workoutExercises,
          db.setEntries,
          db.workoutReportEvents,
          db.workoutReportPlans,
          db.healthSamples,
          db.setAccessories,
          db.setBands,
          db.exerciseCatalog,
        },
      )
      .watch()
      .asyncMap((_) async {
        await generate(sessionId);
        return row(sessionId);
      });

  /// Completion ratio of every trained scheduled session, keyed by
  /// scheduled workout id. Only sessions whose report exists appear; callers
  /// treat a missing entry as fully completed.
  Stream<Map<int, double>> watchScheduleCompletion() => db
      .customSelect(
        'SELECT s.id AS schedule_id, r.report_json AS report_json '
        'FROM scheduled_workouts s '
        'JOIN workout_reports r ON r.session_id = s.completed_session_id '
        'WHERE s.deleted_at IS NULL',
        readsFrom: {db.scheduledWorkouts, db.workoutReports},
      )
      .watch()
      .map((rows) {
        final result = <int, double>{};
        for (final row in rows) {
          final report = WorkoutReport.decode(row.read<String>('report_json'));
          result[row.read<int>('schedule_id')] = SessionCompletion.ratio(
            completed: report.completedSets,
            planned: report.plannedSets,
          );
        }
        return result;
      });

  Future<ReportContext> contextFor(int sessionId) async {
    final saved = await row(sessionId);
    return saved == null
        ? const ReportContext()
        : ReportContext.fromJson(
            jsonDecode(saved.contextJson) as Map<String, dynamic>,
          );
  }

  Future<WorkoutReportData?> row(int sessionId) => (db.select(
    db.workoutReports,
  )..where((r) => r.sessionId.equals(sessionId))).getSingleOrNull();

  Future<void> saveContext(int sessionId, ReportContext context) async {
    await generate(sessionId, context: context);
  }

  Future<void> setEventReason(int eventId, String? reason) async {
    await (db.update(db.workoutReportEvents)
          ..where((e) => e.id.equals(eventId)))
        .write(WorkoutReportEventsCompanion(reason: Value(reason)));
  }

  Future<List<WorkoutReportEventData>> events(int sessionId) =>
      (db.select(db.workoutReportEvents)
            ..where(
              (e) =>
                  e.sessionId.equals(sessionId) &
                  e.kind.isNotValue('finish_plan'),
            )
            ..orderBy([(e) => OrderingTerm.asc(e.id)]))
          .get();

  Future<WorkoutReport?> generate(
    int sessionId, {
    ReportContext? context,
  }) => db.transaction(() async {
    final session =
        await (db.select(db.workoutSessions)
              ..where((s) => s.id.equals(sessionId) & s.deletedAt.isNull()))
            .getSingleOrNull();
    if (session == null || session.endedAt == null) return null;
    final existing = await row(sessionId);
    final checkIn =
        context ??
        (existing == null
            ? const ReportContext()
            : ReportContext.fromJson(
                jsonDecode(existing.contextJson) as Map<String, dynamic>,
              ));
    final planRow = await (db.select(
      db.workoutReportPlans,
    )..where((p) => p.sessionId.equals(sessionId))).getSingleOrNull();
    final initial = planRow == null
        ? <String, dynamic>{}
        : jsonDecode(planRow.planJson) as Map<String, dynamic>;
    final allEvents =
        await (db.select(db.workoutReportEvents)
              ..where((e) => e.sessionId.equals(sessionId))
              ..orderBy([(e) => OrderingTerm.asc(e.id)]))
            .get();
    final finish = allEvents.where((e) => e.kind == 'finish_plan').lastOrNull;
    final eventReasons = allEvents
        .map(
          (e) =>
              ReportReason.values.where((r) => r.name == e.reason).firstOrNull,
        )
        .whereType<ReportReason>()
        .toList();
    final effectiveContext = ReportContext(
      reason: eventReasons.contains(ReportReason.pain)
          ? ReportReason.pain
          : checkIn.reason ?? eventReasons.lastOrNull,
      pain: checkIn.pain,
      ateBefore: checkIn.ateBefore,
      stressed: checkIn.stressed,
      unusualFatigue: checkIn.unusualFatigue,
      techniqueChanged: checkIn.techniqueChanged,
    );
    final planned = finish == null
        ? initial
        : jsonDecode(finish.detailJson) as Map<String, dynamic>;
    // Only inputs available before/currently inside the session are used.
    final snapshot = await TrainingSnapshot.load(
      db,
      from: session.startedAt.subtract(const Duration(days: 84)),
      until: session.endedAt,
    );
    final current = snapshot.sets
        .where((s) => s.session.id == sessionId)
        .toList();
    final history = snapshot.sets
        .where(
          (s) =>
              s.session.id != sessionId &&
              s.session.endedAt != null &&
              !s.session.endedAt!.isAfter(session.startedAt) &&
              s.session.startedAt.isBefore(session.startedAt),
        )
        .toList();
    final healthDate = _iso(session.startedAt);
    final health =
        await (db.select(db.healthSamples)..where(
              (h) =>
                  h.kind.equals('sleep_hours') &
                  h.dateIso.isBiggerOrEqualValue(
                    _iso(session.startedAt.subtract(const Duration(days: 28))),
                  ) &
                  h.dateIso.isSmallerOrEqualValue(healthDate),
            ))
            .get();
    final sleep = health
        .where((h) => h.dateIso == healthDate && h.value > 0 && h.value <= 24)
        .lastOrNull
        ?.value;
    final priorSleep =
        health
            .where(
              (h) =>
                  h.dateIso.compareTo(healthDate) < 0 &&
                  h.value > 0 &&
                  h.value <= 24,
            )
            .map((h) => h.value)
            .toList()
          ..sort();
    final usual = priorSleep.length >= 7
        ? priorSleep[priorSleep.length ~/ 2]
        : null;
    final fingerprint = sha256
        .convert(
          utf8.encode(
            jsonEncode({
              'rules': 'blueprint-2-report-1',
              'start': session.startedAt.toIso8601String(),
              'end': session.endedAt!.toIso8601String(),
              'plan': initial,
              'planned': planned,
              'context': checkIn.toJson(),
              'sets': current.map(_setFingerprint).toList(),
              'history': history.map(_setFingerprint).toList(),
              'sleep': sleep,
              'usual': usual,
              'events': allEvents
                  .map((e) => [e.id, e.kind, e.detailJson, e.reason])
                  .toList(),
            }),
          ),
        )
        .toString();
    if (existing?.fingerprint == fingerprint) {
      try {
        return WorkoutReport.decode(existing!.reportJson);
      } on FormatException {
        /* rebuild */
      }
    }
    final byExercise = <int, List<ResolvedSet>>{};
    for (final s in current) {
      byExercise.putIfAbsent(s.workoutExercise.id, () => []).add(s);
    }
    final observations = <ReportExercise>[];
    for (final sets in byExercise.values) {
      sets.sort((a, b) => a.set.setIndex.compareTo(b.set.setIndex));
      final first = sets.first;
      final earlier = <int, List<ResolvedSet>>{};
      for (final h in history.where((h) => _setup(h) == _setup(first))) {
        earlier.putIfAbsent(h.session.id, () => []).add(h);
      }
      final sessions = earlier.values.toList()
        ..sort(
          (a, b) =>
              b.first.session.startedAt.compareTo(a.first.session.startedAt),
        );
      final oldRow = _exercises(
        initial,
      ).where((e) => e['rowId'] == first.workoutExercise.id).firstOrNull;
      observations.add(
        ReportExercise(
          name: first.exercise.name,
          muscle: first.exercise.primaryMuscle,
          sets: sets.map(_reportSet).toList(),
          previous: sessions
              .take(4)
              .map((s) => s.map(_reportSet).toList())
              .toList(),
          repBased: first.metric.isRepBased,
          newSetup:
              oldRow != null &&
              (oldRow['exerciseId'] != first.exercise.id ||
                  (oldRow['variant'] ?? first.exercise.modality) !=
                      first.equipmentVariant ||
                  (oldRow['machine'] != null &&
                      oldRow['machine'] !=
                          first.workoutExercise.machineConfigJson) ||
                  oldRow['order'] != first.workoutExercise.orderIndex),
          superset: first.workoutExercise.supersetGroup != null,
          plannedSets:
              _exercises(planned)
                  .where((e) => e['rowId'] == first.workoutExercise.id)
                  .map((e) => (e['sets'] as List).length)
                  .firstOrNull ??
              0,
        ),
      );
    }
    final before = initial['originalMuscles'] == null
        ? _muscleCounts(initial)
        : Map<String, int>.from(initial['originalMuscles'] as Map);
    final after = <String, int>{};
    final priorMuscles = <String, int>{};
    for (final s in current) {
      after.update(s.exercise.primaryMuscle, (n) => n + 1, ifAbsent: () => 1);
    }
    for (final s in history.where(
      (s) => !s.session.startedAt.isBefore(
        session.startedAt.subtract(const Duration(days: 7)),
      ),
    )) {
      priorMuscles.update(
        s.exercise.primaryMuscle,
        (n) => n + 1,
        ifAbsent: () => 1,
      );
    }
    final changes = <String>[];
    for (final event in allEvents.where((e) => e.kind != 'finish_plan')) {
      final detail = jsonDecode(event.detailJson) as Map<String, dynamic>;
      final suffix = event.reason == null ? '' : ' · ${event.reason}';
      changes.add(switch (event.kind) {
        'remove_set' => '${detail['name']}: working set removed$suffix',
        'remove_exercise' => '${detail['name']}: exercise removed$suffix',
        'substitute' => '${detail['name']} → ${detail['newName']}$suffix',
        'add_set' => '${detail['name']}: set added$suffix',
        'reorder' => 'Exercise order changed$suffix',
        'setup' => '${detail['name']}: setup changed$suffix',
        'adapted_plan' => 'Started the confirmed adjusted plan$suffix',
        _ => 'Workout plan edited$suffix',
      });
    }
    final report = WorkoutReportEngine.evaluate(
      ReportInput(
        exercises: observations,
        plannedSets: _count(planned),
        originalSets: (initial['originalSets'] as int?) ?? _count(initial),
        planKnown: initial['prescribed'] == true,
        minutes: session.endedAt!
            .difference(session.startedAt)
            .inMinutes
            .clamp(0, 1440),
        context: effectiveContext,
        sleepHours: sleep,
        usualSleepHours: usual,
        muscleChanges: {
          if (initial['prescribed'] == true)
            for (final m in {...before.keys, ...after.keys})
              if ((after[m] ?? 0) != (before[m] ?? 0))
                m: (after[m] ?? 0) - (before[m] ?? 0),
        },
        priorMuscleSets: priorMuscles,
        changes: changes,
        revision: (existing?.revision ?? 0) + 1,
      ),
    );
    await db
        .into(db.workoutReports)
        .insertOnConflictUpdate(
          WorkoutReportsCompanion.insert(
            sessionId: Value(sessionId),
            fingerprint: fingerprint,
            reportJson: report.encode(),
            contextJson: Value(jsonEncode(checkIn.toJson())),
            revision: Value(report.revision),
            generatedAt: clock.now(),
          ),
        );
    return report;
  });

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  static List<Map<String, dynamic>> _exercises(Map<String, dynamic> p) =>
      (p['exercises'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
  static int _count(Map<String, dynamic> p) =>
      _exercises(p).fold(0, (n, e) => n + (e['sets'] as List).length);
  static Map<String, int> _muscleCounts(Map<String, dynamic> p) {
    final result = <String, int>{};
    for (final e in _exercises(p)) {
      result.update(
        e['muscle'] as String,
        (n) => n + (e['sets'] as List).length,
        ifAbsent: () => (e['sets'] as List).length,
      );
    }
    return result;
  }

  static String _setup(ResolvedSet s) => jsonEncode([
    s.exercise.id,
    s.equipmentVariant,
    s.session.gymId,
    s.workoutExercise.machineConfigJson,
    s.accessoryCombo,
  ]);
  static Object _setFingerprint(ResolvedSet s) => [
    s.set.id,
    s.session.id,
    s.session.startedAt.toIso8601String(),
    _setup(s),
    s.set.isCompleted,
    s.effectiveKg,
    s.set.reps,
    s.set.rpeX10,
    s.set.setType,
    s.set.setTypeMetaJson,
    s.set.durationSeconds,
    s.set.distanceM,
    s.set.calories,
    s.set.setIndex,
    s.set.plannedRepsMin,
    s.set.plannedRepsMax,
    s.set.plannedRpeX10,
    s.set.plannedRir,
    s.set.plannedWeightKg,
    s.exercise.name,
    s.exercise.primaryMuscle,
    s.metric.toString(),
  ];
  static ReportSet _reportSet(ResolvedSet s) => ReportSet(
    load: s.effectiveKg,
    reps: s.set.reps,
    rpe: s.set.rpeX10 == null ? null : s.set.rpeX10! / 10,
    targetMin: s.set.plannedRepsMin,
    targetMax: s.set.plannedRepsMax,
    targetRpe: s.set.plannedRpeX10 == null
        ? (s.set.plannedRir == null ? null : 10.0 - s.set.plannedRir!)
        : s.set.plannedRpeX10! / 10,
    standard: s.set.setType == 'standard',
  );
}
