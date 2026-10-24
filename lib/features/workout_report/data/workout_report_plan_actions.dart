import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:herculex/core/utils/clock.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/programs/data/weekly_adaptation_repository.dart';
import 'package:herculex/features/programs/domain/schedule_status.dart';
import 'package:herculex/features/workout_report/data/workout_report_repository.dart';
import 'package:herculex/features/workout_report/domain/workout_report.dart';
import 'package:herculex/features/workouts/data/planned_session_resolver.dart';

class ReportPlanPreview {
  const ReportPlanPreview(
    this.proposal,
    this.guard,
    this.sessionId,
    this.reportFingerprint,
    this.beforeSets,
    this.exerciseNames,
    this.dates,
  );
  final StoredAdaptationProposal proposal;
  final Map<int, String> guard;
  final int sessionId;
  final String reportFingerprint;
  final Map<int, int> beforeSets;
  final Map<int, String> exerciseNames;
  final Map<int, String> dates;
}

/// Only user-confirmed proposals can touch the existing adaptation layer.
class WorkoutReportPlanActions {
  WorkoutReportPlanActions(this.db, this.clock, this.adaptations);
  final AppDatabase db;
  final Clock clock;
  final WeeklyAdaptationRepository adaptations;

  Future<ReportPlanPreview?> preview(int sessionId) async {
    final reports = WorkoutReportRepository(db, clock);
    final report = await reports.generate(sessionId);
    final row = await reports.row(sessionId);
    if (report == null || row == null) return null;
    final context = ReportContext.fromJson(
      jsonDecode(row.contextJson) as Map<String, dynamic>,
    );
    if (context.pain == true || context.reason == ReportReason.pain) {
      return null;
    }
    final source = await (db.select(
      db.scheduledWorkouts,
    )..where((s) => s.completedSessionId.equals(sessionId))).getSingleOrNull();
    if (source?.programId == null) return null;
    StoredAdaptationProposal? proposal;
    if (report.findings.any((f) => f.ruleId == 'RECOVERY-ADJUST-01')) {
      final upcoming =
          await (db.select(db.scheduledWorkouts)
                ..where(
                  (s) =>
                      s.programId.equals(source!.programId!) &
                      s.deletedAt.isNull() &
                      s.status.isIn([
                        ScheduleStatus.planned,
                        ScheduleStatus.moved,
                      ]) &
                      s.completedSessionId.isNull() &
                      s.dateIso.isBiggerOrEqualValue(_today()),
                )
                ..orderBy([(s) => OrderingTerm.asc(s.dateIso)]))
              .get();
      if (upcoming.isNotEmpty) {
        proposal = await adaptations.proposeForLowRecovery(
          upcoming.first.id,
          volumeFactor: .8,
          reason:
              'Repeated benchmark declines and reported fatigue: preview a modest accessory reduction, then reassess.',
        );
      }
    } else if (report.completedSets < report.plannedSets &&
        context.reason == ReportReason.time) {
      // Catch-up is opt-in and only for a confirmed time constraint, never
      // automatically offered after intentional fatigue/pain reduction.
      proposal = await adaptations.proposeForIncompleteSession(sessionId);
    }
    if (proposal == null || !proposal.proposal.hasChanges) return null;
    final guard = <int, String>{};
    final beforeSets = <int, int>{};
    final dates = <int, String>{};
    for (final change in proposal.proposal.changes) {
      guard[change.scheduleId] = await _guard(change.scheduleId);
      final schedule = await (db.select(
        db.scheduledWorkouts,
      )..where((s) => s.id.equals(change.scheduleId))).getSingle();
      final before = await PlannedSessionResolver(
        db,
      ).resolveScheduledWorkout(schedule);
      beforeSets[change.scheduleId] = before.exercises.fold<int>(
        0,
        (n, e) => n + e.sets.where((s) => !s.isWarmup).length,
      );
      dates[change.scheduleId] = schedule.dateIso;
    }
    final exerciseIds = proposal.proposal.changes
        .expand((c) => c.plan.exercises.map((e) => e.exerciseId))
        .toList();
    final catalog = await (db.select(
      db.exerciseCatalog,
    )..where((e) => e.id.isIn(exerciseIds))).get();
    return ReportPlanPreview(
      proposal,
      guard,
      sessionId,
      row.fingerprint,
      beforeSets,
      {for (final e in catalog) e.id: e.name},
      dates,
    );
  }

  Future<void> accept(ReportPlanPreview preview) => db.transaction(() async {
    final reports = WorkoutReportRepository(db, clock);
    await reports.generate(preview.sessionId);
    if ((await reports.row(preview.sessionId))?.fingerprint !=
        preview.reportFingerprint) {
      throw StateError('This report changed. Reopen the preview.');
    }
    for (final entry in preview.guard.entries) {
      if (await _guard(entry.key) != entry.value) {
        throw StateError(
          'The schedule or prescription changed. Reopen the preview.',
        );
      }
    }
    await adaptations.accept(preview.proposal.id);
  });

  Future<String> _guard(int id) async {
    final schedule = await (db.select(
      db.scheduledWorkouts,
    )..where((s) => s.id.equals(id))).getSingle();
    if (!ScheduleStatus.isOpen(schedule.status) ||
        schedule.status == ScheduleStatus.inProgress ||
        schedule.deletedAt != null ||
        schedule.completedSessionId != null ||
        schedule.dateIso.compareTo(_today()) < 0) {
      throw StateError('This workout is no longer available for adaptation.');
    }
    final plan = await PlannedSessionResolver(
      db,
    ).resolveScheduledWorkout(schedule);
    return jsonEncode([
      schedule.toJson(),
      plan.name,
      [
        for (final e in plan.exercises)
          [
            e.exerciseId,
            e.orderIndex,
            e.equipmentVariant,
            e.restSeconds,
            e.trainingMethod,
            [
              for (final s in e.sets)
                [
                  s.index,
                  s.isWarmup,
                  s.setType,
                  s.repsMin,
                  s.repsMax,
                  s.weightKg,
                  s.rpeX10,
                  s.rir,
                  s.setTypeMetaJson,
                ],
            ],
          ],
      ],
    ]);
  }

  String _today() {
    final d = clock.now();
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }
}
