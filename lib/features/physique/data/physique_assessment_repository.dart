import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:herculex/core/utils/clock.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/physique/data/physique_date_keys.dart';
import 'package:herculex/features/physique/data/physique_goal_repository.dart';
import 'package:herculex/features/physique/domain/check_in_policy.dart';
import 'package:herculex/features/physique/domain/check_in_verdict.dart';
import 'package:herculex/features/physique/domain/physique_guardrails.dart';
import 'package:herculex/features/physique/domain/physique_tuning.dart';

/// One check-in to persist: the photo metadata plus the verdict evidence.
class CheckInRecord {
  const CheckInRecord({
    required this.goalId,
    required this.pose,
    required this.relativePath,
    this.blurred = false,
    this.weightKg,
    this.verdict = CheckInVerdict.inconclusive,
    this.band,
    this.confidence = AssessmentConfidence.unknown,
    this.reason = '',
    this.limitations = const [],
    this.source = 'no_analysis',
    this.modelVersion,
    this.knowledgeVersion,
  });

  final int goalId;
  final String pose;
  final String relativePath;
  final bool blurred;
  final double? weightKg;
  final CheckInVerdict verdict;
  final CheckInBand? band;
  final AssessmentConfidence confidence;
  final String reason;
  final List<String> limitations;

  /// `ai` or `no_analysis`.
  final String source;
  final String? modelVersion;
  final String? knowledgeVersion;
}

/// Thrown when a check-in is submitted inside the 7-day window (D-13).
class CheckInTooSoonException implements Exception {
  const CheckInTooSoonException({required this.nextEligibleDate});

  final DateTime nextEligibleDate;

  @override
  String toString() => 'CheckInTooSoonException(next: $nextEligibleDate)';
}

class GoalNotActiveException implements Exception {
  const GoalNotActiveException();

  @override
  String toString() => 'GoalNotActiveException';
}

class BaselineLimitException implements Exception {
  const BaselineLimitException();

  @override
  String toString() => 'BaselineLimitException';
}

/// Check-ins, baseline photos and their reads. [recordCheckIn] is the only
/// code path that creates a photo with role `checkin`, and it enforces the
/// 7-day cap inside a transaction (PHYS-06).
class PhysiqueAssessmentRepository {
  PhysiqueAssessmentRepository(this._db, this._clock);

  final AppDatabase _db;
  final Clock _clock;

  /// Newest check-in time for [goalId], soft-deleted rows included so that
  /// deleting a check-in cannot reopen the window.
  Future<DateTime?> _lastCheckInIncludingDeleted(int goalId) async {
    final row =
        await (_db.select(_db.physiqueAssessments)
              ..where((a) => a.goalId.equals(goalId) & a.kind.equals('checkin'))
              ..orderBy([(a) => OrderingTerm.desc(a.assessedAt)])
              ..limit(1))
            .getSingleOrNull();
    return row?.assessedAt;
  }

  Future<int> recordCheckIn(CheckInRecord record) => _db.transaction(() async {
    final goal =
        await (_db.select(_db.physiqueGoals)
              ..where((g) => g.id.equals(record.goalId) & g.deletedAt.isNull()))
            .getSingleOrNull();
    if (goal == null || goal.status != 'active') {
      throw const GoalNotActiveException();
    }

    final now = _clock.now();
    final last = await _lastCheckInIncludingDeleted(record.goalId);
    if (!CheckInCapPolicy.isEligible(now: now, lastCheckInAt: last)) {
      throw CheckInTooSoonException(
        nextEligibleDate: CheckInCapPolicy.nextEligibleDate(last)!,
      );
    }

    final dateIso = physiqueDayKey(now);
    final assessmentId = await _db
        .into(_db.physiqueAssessments)
        .insert(
          PhysiqueAssessmentsCompanion.insert(
            goalId: record.goalId,
            kind: 'checkin',
            dateIso: dateIso,
            assessedAt: Value(now),
            weightKg: Value(record.weightKg),
            confidence: Value(record.confidence.wireValue),
            verdict: Value(record.verdict.wireValue),
            directionBandLow: Value(record.band?.low),
            directionBandHigh: Value(record.band?.high),
            reason: Value(record.reason),
            limitationsJson: Value(jsonEncode(record.limitations)),
            source: Value(record.source),
            modelVersion: Value(record.modelVersion),
            knowledgeVersion: Value(record.knowledgeVersion),
          ),
        );
    await _db
        .into(_db.physiquePhotos)
        .insert(
          PhysiquePhotosCompanion.insert(
            goalId: record.goalId,
            assessmentId: Value(assessmentId),
            role: 'checkin',
            pose: record.pose,
            dateIso: dateIso,
            takenAt: Value(now),
            relativePath: record.relativePath,
            blurred: Value(record.blurred),
          ),
        );
    return assessmentId;
  });

  /// Baseline photo: no cap, no AI call, at most
  /// [PhysiqueTuning.maxCheckInBaselinePhotos] per goal.
  Future<int> addBaselinePhoto({
    required int goalId,
    required NewPhotoRow photo,
  }) => _db.transaction(() async {
    final existing =
        await (_db.select(_db.physiquePhotos)..where(
              (p) =>
                  p.goalId.equals(goalId) &
                  p.role.equals('baseline') &
                  p.deletedAt.isNull(),
            ))
            .get();
    if (existing.length >= PhysiqueTuning.maxCheckInBaselinePhotos) {
      throw const BaselineLimitException();
    }
    return _db
        .into(_db.physiquePhotos)
        .insert(
          PhysiquePhotosCompanion.insert(
            goalId: goalId,
            role: 'baseline',
            pose: photo.pose,
            dateIso: physiqueDayKey(photo.takenAt),
            takenAt: Value(photo.takenAt),
            relativePath: photo.relativePath,
            blurred: Value(photo.blurred),
            source: Value(photo.source),
            legacyRef: Value(photo.legacyRef),
          ),
        );
  });

  /// Soft-deletes a check-in and its photo rows; returns the relative paths so
  /// the caller can remove the files. The row keeps counting toward the cap.
  Future<List<String>> deleteCheckIn(
    int assessmentId,
  ) => _db.transaction(() async {
    final row =
        await (_db.select(_db.physiqueAssessments)
              ..where((a) => a.id.equals(assessmentId) & a.deletedAt.isNull()))
            .getSingleOrNull();
    if (row == null || row.kind != 'checkin') {
      throw ArgumentError.value(assessmentId, 'assessmentId', 'not a check-in');
    }
    final now = _clock.now();
    final photos =
        await (_db.select(_db.physiquePhotos)..where(
              (p) => p.assessmentId.equals(assessmentId) & p.deletedAt.isNull(),
            ))
            .get();
    await (_db.update(
      _db.physiqueAssessments,
    )..where((a) => a.id.equals(assessmentId))).write(
      PhysiqueAssessmentsCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
      ),
    );
    await (_db.update(
      _db.physiquePhotos,
    )..where((p) => p.assessmentId.equals(assessmentId))).write(
      PhysiquePhotosCompanion(deletedAt: Value(now), updatedAt: Value(now)),
    );
    return [for (final p in photos) p.relativePath];
  });

  Stream<List<PhysiqueAssessmentData>> watchCheckIns(int goalId) =>
      (_db.select(_db.physiqueAssessments)
            ..where(
              (a) =>
                  a.goalId.equals(goalId) &
                  a.kind.equals('checkin') &
                  a.deletedAt.isNull(),
            )
            ..orderBy([
              (a) => OrderingTerm.desc(a.assessedAt),
              (a) => OrderingTerm.desc(a.id),
            ]))
          .watch();

  Stream<PhysiqueAssessmentData?> watchLatestAnalysis(int goalId) =>
      (_db.select(_db.physiqueAssessments)
            ..where(
              (a) =>
                  a.goalId.equals(goalId) &
                  a.kind.equals('analysis') &
                  a.deletedAt.isNull(),
            )
            ..orderBy([
              (a) => OrderingTerm.desc(a.assessedAt),
              (a) => OrderingTerm.desc(a.id),
            ])
            ..limit(1))
          .watchSingleOrNull();

  Stream<DateTime?> watchLastCheckInAt(int goalId) =>
      (_db.select(_db.physiqueAssessments)
            ..where((a) => a.goalId.equals(goalId) & a.kind.equals('checkin'))
            ..orderBy([(a) => OrderingTerm.desc(a.assessedAt)])
            ..limit(1))
          .watchSingleOrNull()
          .map((r) => r?.assessedAt);

  Future<DateTime?> lastCheckInAt(int goalId) =>
      _lastCheckInIncludingDeleted(goalId);

  /// When the newest analysis of [goalId] was made, the one at the start of
  /// the goal included. A new analysis (roadmap update) waits one check-in
  /// window after it.
  Future<DateTime?> latestAnalysisAt(int goalId) async {
    final row =
        await (_db.select(_db.physiqueAssessments)
              ..where(
                (a) =>
                    a.goalId.equals(goalId) &
                    a.kind.equals('analysis') &
                    a.deletedAt.isNull(),
              )
              ..orderBy([(a) => OrderingTerm.desc(a.assessedAt)])
              ..limit(1))
            .getSingleOrNull();
    return row?.assessedAt;
  }

  Stream<List<PhysiquePhotoData>> watchPhotos(int goalId) =>
      (_db.select(_db.physiquePhotos)
            ..where((p) => p.goalId.equals(goalId) & p.deletedAt.isNull())
            ..orderBy([
              (p) => OrderingTerm.desc(p.takenAt),
              (p) => OrderingTerm.desc(p.id),
            ]))
          .watch();

  static int _poseRank(String pose) => switch (pose) {
    'front' => 0,
    'side' => 1,
    _ => 2,
  };

  Future<List<PhysiquePhotoData>> baselinePhotos(int goalId) async {
    final rows =
        await (_db.select(_db.physiquePhotos)..where(
              (p) =>
                  p.goalId.equals(goalId) &
                  p.role.equals('baseline') &
                  p.deletedAt.isNull(),
            ))
            .get();
    rows.sort((a, b) {
      final c = a.takenAt.compareTo(b.takenAt);
      if (c != 0) return c;
      final r = _poseRank(a.pose).compareTo(_poseRank(b.pose));
      return r != 0 ? r : a.id.compareTo(b.id);
    });
    return rows;
  }
}
