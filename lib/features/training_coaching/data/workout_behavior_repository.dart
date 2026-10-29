import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:herculex/core/utils/clock.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/programs/domain/periodization.dart';
import 'package:herculex/features/workout_report/data/workout_report_repository.dart';
import 'package:herculex/features/workout_report/domain/workout_report.dart';
import 'package:herculex/features/workouts/data/portable_workout_plan.dart';
import 'package:uuid/enums.dart';
import 'package:uuid/uuid.dart';

class WorkoutBehaviorRepository {
  WorkoutBehaviorRepository(this.db, this.clock);
  final AppDatabase db;
  final Clock clock;

  Future<void> capture(int sessionId) => db.transaction(() async {
    final session = await (db.select(
      db.workoutSessions,
    )..where((s) => s.id.equals(sessionId))).getSingleOrNull();
    if (session?.endedAt == null || session!.deletedAt != null) return;
    final prior = await (db.select(
      db.workoutBehaviorSnapshots,
    )..where((s) => s.sessionId.equals(sessionId))).getSingleOrNull();
    if (prior != null &&
        (jsonDecode(prior.snapshotJson) as Map)['corrected'] == true)
      return;
    final original = await (db.select(
      db.workoutReportPlans,
    )..where((s) => s.sessionId.equals(sessionId))).getSingleOrNull();
    if (prior != null && original == null) return;
    final originalJson = original == null
        ? <String, dynamic>{}
        : jsonDecode(original.planJson) as Map<String, dynamic>;
    final schedule = await (db.select(
      db.scheduledWorkouts,
    )..where((s) => s.completedSessionId.equals(sessionId))).getSingleOrNull();
    final day = schedule?.programDayId == null
        ? null
        : await (db.select(db.programDays)
                ..where((d) => d.id.equals(schedule!.programDayId!)))
              .getSingleOrNull();
    final week = day == null
        ? null
        : await (db.select(
            db.programWeeks,
          )..where((w) => w.id.equals(day.programWeekId))).getSingleOrNull();
    final program = schedule?.programId == null
        ? null
        : await (db.select(
            db.programs,
          )..where((p) => p.id.equals(schedule!.programId!))).getSingleOrNull();
    final codec = PortableWorkoutPlan(db);
    final actual = <Map<String, Object?>>[];
    final rows =
        await (db.select(db.workoutExercises)
              ..where(
                (e) => e.sessionId.equals(sessionId) & e.deletedAt.isNull(),
              )
              ..orderBy([(e) => OrderingTerm.asc(e.orderIndex)]))
            .get();
    for (final row in rows) {
      final exercise = await (db.select(
        db.exerciseCatalog,
      )..where((e) => e.id.equals(row.exerciseId))).getSingle();
      final sets =
          await (db.select(db.setEntries)
                ..where(
                  (s) =>
                      s.workoutExerciseId.equals(row.id) &
                      s.isCompleted.equals(true) &
                      s.isWarmup.equals(false) &
                      s.deletedAt.isNull(),
                )
                ..orderBy([(s) => OrderingTerm.asc(s.setIndex)]))
              .get();
      if (sets.isEmpty) continue;
      actual.add({
        'row': row.syncUuid,
        'exercise': await codec.exerciseRef(exercise.id),
        'slot': await codec.slotRef(row.programExerciseSlotId),
        'name': exercise.name,
        'muscle': exercise.primaryMuscle,
        'order': row.orderIndex,
        'variant': row.equipmentVariant ?? exercise.modality,
        'machine': row.machineConfigJson,
        'method': row.plannedTrainingMethod ?? 'straight_sets',
        'role': row.plannedSlotRole ?? 'accessory',
        'completed': sets.length,
        'rest': row.targetRestSeconds ?? exercise.defaultRestSeconds,
        'sets': [
          for (final s in sets)
            {
              'load': s.weightKg,
              'reps': s.reps,
              'rpe': s.rpeX10,
              'min': s.plannedRepsMin,
              'max': s.plannedRepsMax,
              'type': s.setType,
              'duration': s.durationSeconds,
              'distance': s.distanceM,
              'calories': s.calories,
            },
        ],
      });
    }
    var known = originalJson['prescribed'] == true;
    final planned = <Map<String, Object?>>[];
    for (final raw in (originalJson['exercises'] as List? ?? []).cast<Map>()) {
      final exercise = await (db.select(
        db.exerciseCatalog,
      )..where((e) => e.id.equals(raw['exerciseId'] as int))).getSingleOrNull();
      if (exercise == null) {
        known = false;
        continue;
      }
      final row = await (db.select(
        db.workoutExercises,
      )..where((e) => e.id.equals(raw['rowId'] as int))).getSingleOrNull();
      final rowRef = raw['rowRef'] ?? row?.syncUuid;
      if (rowRef == null) known = false;
      planned.add({
        'row': rowRef,
        'exercise': await codec.exerciseRef(exercise.id),
        'slot':
            raw['slotRef'] ?? await codec.slotRef(row?.programExerciseSlotId),
        'name': exercise.name,
        'muscle': exercise.primaryMuscle,
        'order': raw['order'],
        'variant': raw['variant'] ?? exercise.modality,
        'machine': raw['machine'],
        'method':
            raw['method'] ?? row?.plannedTrainingMethod ?? 'straight_sets',
        'role': raw['role'] ?? row?.plannedSlotRole ?? 'accessory',
        'planned': (raw['sets'] as List? ?? []).length,
        'prescription': jsonEncode([
          for (final set in (raw['sets'] as List? ?? []).cast<Map>())
            [set['min'], set['max'], set['rpe'], set['rir'], set['type']],
        ]),
      });
    }
    final report = await (db.select(
      db.workoutReports,
    )..where((r) => r.sessionId.equals(sessionId))).getSingleOrNull();
    final context = report == null
        ? const ReportContext()
        : ReportContext.fromJson(
            jsonDecode(report.contextJson) as Map<String, dynamic>,
          );
    final events = await (db.select(
      db.workoutReportEvents,
    )..where((e) => e.sessionId.equals(sessionId))).get();
    final reason = events.any((e) => e.reason == 'pain')
        ? 'pain'
        : context.reason?.name ??
              events.map((e) => e.reason).nonNulls.lastOrNull;
    final policy =
        context.pain == true ||
            context.unusualFatigue == true ||
            events.any((e) => e.reason == 'fatigue' || e.reason == 'pain') ||
            reason == 'pain' ||
            reason == 'fatigue'
        ? 'do_not_catch_up'
        : switch (reason) {
            'time' => 'time',
            'equipment' => 'equipment',
            'preference' => 'preference',
            _ => 'unknown',
          };
    final overrides = schedule == null
        ? <TrainingCoachingOverrideData>[]
        : await (db.select(db.trainingCoachingOverrides)..where(
                (o) => o.scheduleId.equals(schedule.id) & o.deletedAt.isNull(),
              ))
              .get();
    final weekly = schedule == null
        ? <AdaptationOverrideData>[]
        : await (db.select(db.adaptationOverrides)..where(
                (o) => o.scheduleId.equals(schedule.id) & o.deletedAt.isNull(),
              ))
              .get();
    if (report != null) {
      final findings = WorkoutReport.decode(report.reportJson).findings;
      for (final e in actual) {
        e['declined'] = findings.any(
          (f) =>
              f.exerciseName == e['name'] &&
              ['PERFORMANCE-DOWN', 'PERFORMANCE-REPEATED'].contains(f.ruleId),
        );
      }
    }
    final gym = session.gymId == null
        ? null
        : await (db.select(
            db.gyms,
          )..where((g) => g.id.equals(session.gymId!))).getSingleOrNull();
    final json = jsonEncode({
      'version': 1,
      'session': session.syncUuid,
      'program': program?.syncUuid,
      'gym': gym?.syncUuid,
      'phase': week?.blockPhase ?? program?.periodizationModel,
      'day': day == null
          ? ''
          : '${day.cycleDayIndex ?? day.dayOfWeek}|${day.slotLabel ?? day.name}',
      'at': session.endedAt!.toUtc().toIso8601String(),
      'known': known,
      'trial':
          (prior != null &&
              (jsonDecode(prior.snapshotJson) as Map)['trial'] == true) ||
          overrides.isNotEmpty ||
          weekly.isNotEmpty ||
          schedule?.oneOffPlanJson != null,
      'deload':
          week != null &&
          program != null &&
          Periodization.isPlannedDeload(
            model: PeriodizationModel.fromId(program.periodizationModel),
            totalWeeks: program.weeks,
            weekIndex: week.weekIndex,
          ),
      'minutes': session.endedAt!
          .difference(session.startedAt)
          .inMinutes
          .clamp(0, 1440),
      'reasonDismissed': prior == null
          ? false
          : (jsonDecode(prior.snapshotJson) as Map)['reasonDismissed'] == true,
      'policy': policy,
      'original': planned,
      'actual': actual,
      'corrected': events.any((e) => e.kind == 'history_correction'),
    });
    if (prior?.snapshotJson == json) return;
    if (prior == null) {
      await db
          .into(db.workoutBehaviorSnapshots)
          .insert(
            WorkoutBehaviorSnapshotsCompanion.insert(
              sessionId: sessionId,
              snapshotJson: json,
              capturedAt: session.endedAt!,
              syncUuid: Value(
                const Uuid().v5(
                  Namespace.url.value,
                  'herculex:behavior:${session.syncUuid}',
                ),
              ),
            ),
          );
    } else {
      await (db.update(db.workoutBehaviorSnapshots)
            ..where((s) => s.id.equals(prior.id)))
          .write(WorkoutBehaviorSnapshotsCompanion(snapshotJson: Value(json)));
    }
  });

  Future<void> dismissReason(int sessionId) async {
    final row = await (db.select(
      db.workoutBehaviorSnapshots,
    )..where((s) => s.sessionId.equals(sessionId))).getSingle();
    final json = Map<String, dynamic>.from(jsonDecode(row.snapshotJson) as Map)
      ..['reasonDismissed'] = true;
    await (db.update(
      db.workoutBehaviorSnapshots,
    )..where((s) => s.id.equals(row.id))).write(
      WorkoutBehaviorSnapshotsCompanion(snapshotJson: Value(jsonEncode(json))),
    );
  }

  Future<void> saveReason(int sessionId, ReportReason reason) async {
    final reports = WorkoutReportRepository(db, clock);
    final previous = await reports.contextFor(sessionId);
    await reports.saveContext(
      sessionId,
      ReportContext(
        reason: reason,
        ateBefore: previous.ateBefore,
        stressed: previous.stressed,
        unusualFatigue: previous.unusualFatigue,
        pain: previous.pain,
        techniqueChanged: previous.techniqueChanged,
      ),
    );
    await capture(sessionId);
  }
}
