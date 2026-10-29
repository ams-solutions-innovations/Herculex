import 'dart:convert';
import 'dart:math' as math;
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:health/health.dart';
import 'package:herculex/core/utils/clock.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/analytics/domain/cns_trends.dart';
import 'package:herculex/features/analytics/domain/muscle_recovery_v3.dart';
import 'package:herculex/features/analytics/domain/training_snapshot.dart';
import 'package:herculex/features/health/data/health_service.dart';
import 'package:herculex/features/programs/domain/periodization.dart';
import 'package:herculex/features/programs/domain/slot_prescription.dart';
import 'package:herculex/features/programs/domain/slot_prescription_codec.dart';
import 'package:herculex/features/programs/domain/volume_bands.dart';
import 'package:herculex/features/recovery/data/joint_pain_repository.dart';
import 'package:herculex/features/recovery/domain/deload_urgency.dart';
import 'package:herculex/features/recovery/domain/joint_model.dart';
import 'package:herculex/features/recovery/domain/muscle_deload_advisor.dart';
import 'package:herculex/features/training_coaching/data/workout_behavior_repository.dart';
import 'package:herculex/features/training_coaching/domain/training_coaching.dart';
import 'package:herculex/features/workout_report/data/workout_report_repository.dart';
import 'package:herculex/features/workout_report/domain/workout_report.dart';
import 'package:herculex/features/workouts/data/planned_session_resolver.dart';
import 'package:herculex/features/workouts/data/portable_workout_plan.dart';
import 'package:herculex/features/workouts/data/templates_repository.dart';
import 'package:herculex/features/workouts/domain/equipment_variants.dart';
import 'package:herculex/features/workouts/domain/calisthenics_set_plan.dart';
import 'package:herculex/features/workouts/domain/set_type.dart';
import 'package:herculex/features/workouts/domain/workout_duration_estimator.dart';
import 'package:uuid/enums.dart';
import 'package:uuid/uuid.dart';

part 'training_coaching_repository/preview.dart';
part 'training_coaching_repository/safety.dart';
part 'training_coaching_repository/actions.dart';
part 'training_coaching_repository/feedback.dart';
part 'training_coaching_repository/planning.dart';
part 'training_coaching_repository/persistence.dart';

class CoachingPlanChange {
  const CoachingPlanChange({
    required this.date,
    required this.before,
    required this.after,
    this.scheduleId,
    this.startsAt,
    this.beforeVolume = const {},
    this.afterVolume = const {},
    this.beforeMinutes,
    this.afterMinutes,
  });
  final int? scheduleId;
  final DateTime date;
  final DateTime? startsAt;
  final PlannedSessionSnapshot before, after;
  final Map<String, double> beforeVolume, afterVolume;
  final int? beforeMinutes, afterMinutes;
}

class CoachingPreview {
  const CoachingPreview({
    required this.proposalId,
    required this.signal,
    required this.changes,
    required this.fingerprint,
    required this.evidenceFingerprint,
    required this.exerciseNames,
    required this.availableMinutes,
    this.extraAt,
    this.permanent = false,
  });
  final int proposalId, availableMinutes;
  final CoachingSignal signal;
  final List<CoachingPlanChange> changes;
  final String fingerprint, evidenceFingerprint;
  final Map<int, String> exerciseNames;
  final DateTime? extraAt;
  final bool permanent;
}

/// Owns proposals, previews and reversible trial changes. UI never writes plans.
class TrainingCoachingRepository {
  TrainingCoachingRepository(this.db, this.clock, {this.health});
  final AppDatabase db;
  final Clock clock;
  final HealthService? health;
  final _capturedInputs = <int, String>{};
  Future<void>? _refreshing;
  bool _refreshRequested = false;
  PortableWorkoutPlan get codec => PortableWorkoutPlan(db);
  WorkoutBehaviorRepository get behavior =>
      WorkoutBehaviorRepository(db, clock);
  static String hash(Object value) =>
      sha256.convert(utf8.encode(jsonEncode(value))).toString();
  static String iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<CoachingPreview> preview(
    int id, {
    int availableMinutes = 30,
    DateTime? extraAt,
  }) => _preview(id, availableMinutes: availableMinutes, extraAt: extraAt);
  Future<void> accept(CoachingPreview reviewed) => _accept(reviewed);
  Future<void> cancelTrial(int id) => _cancelTrial(id);
  Future<CoachingPreview> permanentPreview(int id) => _permanentPreview(id);
  Future<CoachingTrialFeedback?> feedback(int id) => _feedback(id);
  Future<void> saveFeedback(
    int id, {
    required bool tiring,
    bool pain = false,
  }) => _saveFeedback(id, tiring: tiring, pain: pain);
  Future<int> adjustTrial(int id, {int? targetSets}) =>
      _adjustTrial(id, targetSets: targetSets);

  Stream<List<TrainingCoachingProposalData>> watch({int? sessionId}) => db
      .customSelect(
        'SELECT 1',
        readsFrom: {
          db.workoutSessions,
          db.workoutReportPlans,
          db.workoutReports,
          db.workoutBehaviorSnapshots,
          db.trainingCoachingProposals,
          db.trainingCoachingOverrides,
          db.scheduledWorkouts,
          db.physiqueProgrammingProfiles,
        },
      )
      .watch()
      .asyncMap((_) async {
        await refresh();
        final rows =
            await (db.select(db.trainingCoachingProposals)
                  ..where((p) => p.deletedAt.isNull())
                  ..orderBy([(p) => OrderingTerm.desc(p.createdAt)]))
                .get();
        return rows
            .where(
              (r) =>
                  ['proposed', 'trial', 'review'].contains(r.status) &&
                  (r.snoozedUntil == null ||
                      !r.snoozedUntil!.isAfter(clock.now())) &&
                  (sessionId == null || r.sourceSessionId == sessionId),
            )
            .toList();
      });

  Future<void> refresh() {
    _refreshRequested = true;
    return _refreshing ??= _refreshLoop().whenComplete(
      () => _refreshing = null,
    );
  }

  Future<void> _refreshLoop() async {
    do {
      _refreshRequested = false;
      await _refresh();
    } while (_refreshRequested);
  }

  Future<void> _refresh() async {
    final since = clock.now().subtract(TrainingCoachingEngine.lookback);
    final localPlans =
        await (db.select(db.workoutReportPlans).join([
              innerJoin(
                db.workoutSessions,
                db.workoutSessions.id.equalsExp(
                  db.workoutReportPlans.sessionId,
                ),
              ),
            ])..where(
              db.workoutSessions.endedAt.isNotNull() &
                  db.workoutSessions.deletedAt.isNull() &
                  db.workoutSessions.startedAt.isBiggerOrEqualValue(since),
            ))
            .get();
    for (final row in localPlans) {
      final session = row.readTable(db.workoutSessions);
      final report = await (db.select(
        db.workoutReports,
      )..where((r) => r.sessionId.equals(session.id))).getSingleOrNull();
      final input = hash([
        session.endedAt?.toIso8601String(),
        row.readTable(db.workoutReportPlans).planJson,
        report?.fingerprint,
      ]);
      if (_capturedInputs[session.id] != input) {
        await behavior.capture(session.id);
        _capturedInputs[session.id] = input;
      }
    }
    final snapshots =
        await (db.select(db.workoutBehaviorSnapshots)..where(
              (s) =>
                  s.deletedAt.isNull() &
                  s.capturedAt.isBiggerOrEqualValue(since),
            ))
            .get();
    final activeSessions = await (db.select(
      db.workoutSessions,
    )..where((s) => s.deletedAt.isNull() & s.endedAt.isNotNull())).get();
    final sessionsByRef = {for (final s in activeSessions) s.syncUuid: s};
    final observations = <CoachingObservation>[];
    for (final s in snapshots) {
      try {
        final o = CoachingObservation.decode(s.snapshotJson);
        if (sessionsByRef.containsKey(o.session)) observations.add(o);
      } on FormatException {
        /* Unknown/corrupt imported evidence is not usable. */
      }
    }
    final profile =
        await (db.select(db.physiqueProgrammingProfiles)
              ..where((p) => p.active.equals(true) & p.deletedAt.isNull())
              ..orderBy([(p) => OrderingTerm.desc(p.confirmedAt)])
              ..limit(1))
            .getSingleOrNull();
    final priorities = <String>{};
    if (profile != null) {
      final json = jsonDecode(profile.prioritiesJson) as Map;
      for (final p in (json['musclePriorities'] as List? ?? []).cast<Map>()) {
        if (['high', 'prioritize', 'focus'].contains(p['priority'])) {
          final raw = '${p['muscleId']}'.toLowerCase().replaceAll(
            RegExp('[^a-z]'),
            '',
          );
          for (final muscle in MuscleRecoveryV3.groups) {
            if (muscle.toLowerCase().replaceAll(' ', '') == raw)
              priorities.add(muscle);
          }
        }
      }
    }
    final signals = TrainingCoachingEngine.detect(
      observations: observations,
      now: clock.now(),
      priorityMuscles: priorities,
    );
    final activeKeys = <String>{};
    for (final signal in signals) {
      final key = hash(signal.key);
      activeKeys.add(key);
      final previous = await (db.select(
        db.trainingCoachingProposals,
      )..where((p) => p.proposalKey.equals(key))).getSingleOrNull();
      if (previous != null &&
          [
            'trial',
            'review',
            'kept',
            'declined',
            'cancelled',
          ].contains(previous.status))
        continue;
      final source = sessionsByRef[signal.source.session];
      if (source == null) continue;
      final program = signal.source.program == null
          ? null
          : await (db.select(db.programs)..where(
                  (p) =>
                      p.syncUuid.equals(signal.source.program!) &
                      p.deletedAt.isNull(),
                ))
                .getSingleOrNull();
      final payload = jsonEncode({'signal': signal.toJson()});
      if (previous == null) {
        await db
            .into(db.trainingCoachingProposals)
            .insert(
              TrainingCoachingProposalsCompanion.insert(
                programId: Value(program?.id),
                sourceSessionId: Value(source.id),
                kind: signal.kind.name,
                proposalKey: key,
                payloadJson: payload,
                createdAt: clock.now(),
                syncUuid: Value(
                  const Uuid().v5(
                    Namespace.url.value,
                    'herculex:coaching:$key',
                  ),
                ),
              ),
            );
      } else if (previous.payloadJson != payload ||
          previous.status == 'expired') {
        await (db.update(
          db.trainingCoachingProposals,
        )..where((p) => p.id.equals(previous.id))).write(
          TrainingCoachingProposalsCompanion(
            payloadJson: Value(payload),
            status: const Value('proposed'),
          ),
        );
      }
    }
    final rows = await (db.select(
      db.trainingCoachingProposals,
    )..where((p) => p.deletedAt.isNull())).get();
    for (final row in rows) {
      if (row.status == 'proposed' &&
          !activeKeys.contains(row.proposalKey) &&
          (jsonDecode(row.payloadJson) as Map)['manualAdjustment'] != true)
        await _status(row.id, 'expired');
      if (row.status == 'trial') await _evaluate(row);
    }
  }

  CoachingSignal signal(TrainingCoachingProposalData row) =>
      CoachingSignal.fromJson(
        Map<String, dynamic>.from(
          (jsonDecode(row.payloadJson) as Map)['signal'] as Map,
        ),
      );

  Future<void> _requireNoOtherTrial(TrainingCoachingProposalData row) async {
    if (row.programId == null) return;
    final active =
        await (db.select(db.trainingCoachingProposals)..where(
              (p) =>
                  p.programId.equals(row.programId!) &
                  p.status.equals('trial') &
                  p.deletedAt.isNull() &
                  p.id.equals(row.id).not(),
            ))
            .get();
    if (active.any(
      (p) => p.expiresAt == null || p.expiresAt!.isAfter(clock.now()),
    )) {
      throw StateError(
        'Finish or cancel the active trial before trying another change in this program.',
      );
    }
  }

  Future<void> decline(int id) => _status(id, 'declined');
  Future<void> snooze(int id) =>
      (db.update(
        db.trainingCoachingProposals,
      )..where((p) => p.id.equals(id))).write(
        TrainingCoachingProposalsCompanion(
          snoozedUntil: Value(clock.now().add(const Duration(days: 14))),
        ),
      );
  Future<void> _status(int id, String status) =>
      (db.update(
        db.trainingCoachingProposals,
      )..where((p) => p.id.equals(id))).write(
        TrainingCoachingProposalsCompanion(
          status: Value(status),
          decidedAt: Value(clock.now()),
        ),
      );
}
