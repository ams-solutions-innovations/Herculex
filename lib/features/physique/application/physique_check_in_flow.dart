import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/core/utils/clock.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/nutrition/domain/diet_phase.dart';
import 'package:herculex/features/physique/application/physique_providers.dart';
import 'package:herculex/features/physique/data/physique_assessment_repository.dart';
import 'package:herculex/features/physique/data/physique_checkin_service.dart';
import 'package:herculex/features/physique/data/physique_goal_repository.dart';
import 'package:herculex/features/physique/data/physique_photo_sanitizer.dart';
import 'package:herculex/features/physique/data/physique_photo_store.dart';
import 'package:herculex/features/physique/domain/check_in_policy.dart';
import 'package:herculex/features/physique/domain/check_in_verdict.dart';
import 'package:herculex/features/physique/domain/physique_guardrails.dart';
import 'package:herculex/features/physique/domain/physique_tuning.dart';

/// Steps the check-in sheet shows while the flow runs.
enum CheckInProgressStep { removingLocation, checkingFaces, comparing, saving }

sealed class CheckInOutcome {
  const CheckInOutcome();
}

class CheckInRecorded extends CheckInOutcome {
  const CheckInRecorded({
    required this.assessmentId,
    required this.verdict,
    required this.evidence,
    required this.analyzed,
  });

  final int assessmentId;
  final CheckInVerdict verdict;

  /// Null when saved without analysis.
  final CheckInEvidence? evidence;
  final bool analyzed;
}

/// Nothing was persisted and the staged photo is still in place, so the caller
/// can retry or finish with `analyze: false`.
class CheckInAiUnavailable extends CheckInOutcome {
  const CheckInAiUnavailable(this.failure, this.message);

  final PhysiqueCheckInFailure failure;
  final String message;
}

class BaselineSaved extends CheckInOutcome {
  const BaselineSaved(this.photoId);

  final int photoId;
}

const _noBaselineMessage =
    'Add a baseline photo so Herculex AI has something to compare with.';
const _noAnalysisReason =
    "Herculex AI couldn't review this photo, so this check-in is inconclusive.";

/// Stage, cap pre-check, analyse, classify in Dart, persist. The AI returns
/// evidence only; this class performs the one write after the classifier.
class PhysiqueCheckInFlow {
  PhysiqueCheckInFlow({
    required PhysiquePhotoSanitizer sanitizer,
    required PhysiquePhotoStore store,
    required PhysiqueAssessmentRepository assessments,
    required PhysiqueCheckInService service,
    required Clock clock,
  }) : _sanitizer = sanitizer,
       _store = store,
       _assessments = assessments,
       _service = service,
       _clock = clock;

  final PhysiquePhotoSanitizer _sanitizer;
  final PhysiquePhotoStore _store;
  final PhysiqueAssessmentRepository _assessments;
  final PhysiqueCheckInService _service;
  final Clock _clock;

  /// Sanitises [source] into a temp file; [source] is never modified.
  Future<StagedPhoto> stage(
    File source, {
    required bool blurFaces,
    void Function(CheckInProgressStep step)? onProgress,
  }) {
    onProgress?.call(CheckInProgressStep.removingLocation);
    if (blurFaces) {
      onProgress?.call(CheckInProgressStep.checkingFaces);
    }
    return _sanitizer.stage(source, blurFaces: blurFaces);
  }

  Future<void> discardStaged(StagedPhoto staged) => _sanitizer.discard(staged);

  String _goalUuid(PhysiqueGoalData goal) {
    final uuid = goal.syncUuid;
    if (uuid == null) {
      throw StateError('Physique goal ${goal.id} has no sync uuid');
    }
    return uuid;
  }

  /// Copies first, then commits metadata atomically. Staging survives a failure.
  Future<List<NewPhotoRow>> _copyPhotos(
    PhysiqueGoalData goal,
    List<StagedPosePhoto> photos,
  ) async {
    final rows = <NewPhotoRow>[];
    try {
      for (final p in photos) {
        final relative = await _store.copyIntoGoal(
          p.photo.file,
          goalUuid: _goalUuid(goal),
        );
        rows.add(
          NewPhotoRow(
            pose: p.pose,
            relativePath: relative,
            takenAt: _clock.now(),
            blurred: p.photo.blurApplied,
          ),
        );
      }
      return rows;
    } on Object {
      for (final row in rows) {
        await _store.delete(row.relativePath);
      }
      rethrow;
    }
  }

  Future<CheckInOutcome> saveBaseline({
    required PhysiqueGoalData goal,
    StagedPhoto? staged,
    String pose = 'front',
    List<StagedPosePhoto> photos = const [],
  }) async {
    final batch = StagedPosePhoto.checked(
      photos: photos,
      staged: staged,
      pose: pose,
    );
    final rows = await _copyPhotos(goal, batch);
    late final List<int> ids;
    try {
      ids = await _assessments.addBaselinePhotos(goalId: goal.id, photos: rows);
    } on Object {
      for (final row in rows) {
        await _store.delete(row.relativePath);
      }
      rethrow;
    }
    await _discardCommitted(batch);
    return BaselineSaved(ids.first);
  }

  Future<CheckInOutcome> completeCheckIn({
    required PhysiqueGoalData goal,
    StagedPhoto? staged,
    String pose = 'front',
    List<StagedPosePhoto> photos = const [],
    required DietPhase phase,
    required int weeksInPhase,
    required bool analyze,
    required bool consentGranted,
    double? weightKg,
    double? weeklyTrendKg,
    void Function(CheckInProgressStep step)? onProgress,
  }) async {
    final batch = StagedPosePhoto.checked(
      photos: photos,
      staged: staged,
      pose: pose,
    );
    final last = await _assessments.lastCheckInAt(goal.id);
    if (!CheckInCapPolicy.isEligible(now: _clock.now(), lastCheckInAt: last)) {
      throw CheckInTooSoonException(
        nextEligibleDate: CheckInCapPolicy.nextEligibleDate(last)!,
      );
    }
    if (!analyze) {
      return _persist(
        goal: goal,
        photos: batch,
        weightKg: weightKg,
        verdict: CheckInVerdict.inconclusive,
        evidence: null,
        reason: _noAnalysisReason,
        source: 'no_analysis',
        onProgress: onProgress,
      );
    }
    if (!consentGranted) {
      throw const PhysiqueCheckInException(
        PhysiqueCheckInFailure.consentRequired,
        'Confirm the photo privacy notice before starting the analysis.',
      );
    }
    final baselines = await _loadBaselines(goal.id);
    if (baselines.isEmpty) {
      return const CheckInAiUnavailable(
        PhysiqueCheckInFailure.invalidInput,
        _noBaselineMessage,
      );
    }
    onProgress?.call(CheckInProgressStep.comparing);
    final PhysiqueCheckInAnalysis analysis;
    try {
      final current = <PhysiqueCheckInImage>[];
      for (final p in batch) {
        current.add(
          PhysiqueCheckInImage(
            pose: p.pose,
            jpeg: await _sanitizer.analysisBytes(p.photo.file),
          ),
        );
      }
      analysis = await _service.analyze(
        baselineImages: baselines,
        currentImages: current,
        context: PhysiqueCheckInContext(
          phase: phase,
          weeksInPhase: weeksInPhase,
          weightTrendKgPerWeek: weeklyTrendKg,
        ),
        consentGranted: consentGranted,
      );
    } on PhysiqueCheckInException catch (e) {
      return CheckInAiUnavailable(e.kind, e.message);
    } on PhotoSanitizeException {
      return const CheckInAiUnavailable(
        PhysiqueCheckInFailure.invalidInput,
        'These photos could not be read. Try taking them again.',
      );
    }
    final verdict = CheckInVerdictClassifier.classify(
      evidence: analysis.evidence,
      phase: phase,
      measuredWeeklyTrendKg: weeklyTrendKg,
    );
    return _persist(
      goal: goal,
      photos: batch,
      weightKg: weightKg,
      verdict: verdict,
      evidence: analysis.evidence,
      reason: analysis.evidence.reason,
      source: 'ai',
      modelVersion: analysis.modelVersion,
      knowledgeVersion: analysis.knowledgeVersion,
      onProgress: onProgress,
    );
  }

  /// Retries AI on the photos from an existing `no_analysis` check-in.
  /// This only updates its evidence; its original date and weekly slot stay
  /// unchanged. A failed request leaves the saved check-in untouched.
  Future<void> retrySavedCheckInAnalysis({
    required PhysiqueGoalData goal,
    required int assessmentId,
    required DietPhase phase,
    required int weeksInPhase,
    required bool consentGranted,
    double? weeklyTrendKg,
  }) async {
    if (!consentGranted) {
      throw const PhysiqueCheckInException(
        PhysiqueCheckInFailure.consentRequired,
        'Confirm the photo privacy notice before starting the analysis.',
      );
    }
    if (goal.status != 'active') {
      throw const GoalNotActiveException();
    }
    final assessment = await _assessments.checkInForAnalysisRetry(
      goalId: goal.id,
      assessmentId: assessmentId,
    );
    if (assessment == null ||
        assessment.source != 'no_analysis' ||
        CheckInVerdict.fromWire(assessment.verdict) !=
            CheckInVerdict.inconclusive) {
      throw StateError('This check-in is no longer available for retry.');
    }

    final baselines = await _loadBaselines(goal.id);
    if (baselines.isEmpty) {
      throw const PhysiqueCheckInException(
        PhysiqueCheckInFailure.invalidInput,
        _noBaselineMessage,
      );
    }
    final rows = await _assessments.checkInPhotosForAnalysisRetry(
      goalId: goal.id,
      assessmentId: assessmentId,
    );
    if (rows.isEmpty ||
        rows.length > 3 ||
        rows.map((p) => p.pose).toSet().length != rows.length) {
      throw const PhysiqueCheckInException(
        PhysiqueCheckInFailure.invalidInput,
        'The saved check-in photos could not be loaded. The check-in is still saved.',
      );
    }

    final current = <PhysiqueCheckInImage>[];
    for (final row in rows) {
      try {
        final file = await _store.resolve(row.relativePath);
        if (!await file.exists()) {
          throw const PhysiqueCheckInException(
            PhysiqueCheckInFailure.invalidInput,
            'A saved check-in photo is missing. The check-in is still saved.',
          );
        }
        current.add(
          PhysiqueCheckInImage(
            pose: row.pose,
            jpeg: await _sanitizer.analysisBytes(file),
          ),
        );
      } on PhysiqueCheckInException {
        rethrow;
      } on Object {
        throw const PhysiqueCheckInException(
          PhysiqueCheckInFailure.invalidInput,
          'A saved check-in photo could not be read. The check-in is still saved.',
        );
      }
    }

    final analysis = await _service.analyze(
      baselineImages: baselines,
      currentImages: current,
      context: PhysiqueCheckInContext(
        phase: phase,
        weeksInPhase: weeksInPhase,
        weightTrendKgPerWeek: weeklyTrendKg,
      ),
      consentGranted: consentGranted,
    );
    final verdict = CheckInVerdictClassifier.classify(
      evidence: analysis.evidence,
      phase: phase,
      measuredWeeklyTrendKg: weeklyTrendKg,
    );
    await _assessments.updateCheckInAnalysis(
      assessmentId: assessmentId,
      verdict: verdict,
      band: analysis.evidence.band,
      confidence: analysis.evidence.confidence,
      reason: analysis.evidence.reason,
      limitations: analysis.evidence.limitations,
      modelVersion: analysis.modelVersion,
      knowledgeVersion: analysis.knowledgeVersion,
    );
  }

  Future<CheckInOutcome> _persist({
    required PhysiqueGoalData goal,
    required List<StagedPosePhoto> photos,
    required CheckInVerdict verdict,
    required CheckInEvidence? evidence,
    required String reason,
    required String source,
    required void Function(CheckInProgressStep step)? onProgress,
    double? weightKg,
    String? modelVersion,
    String? knowledgeVersion,
  }) async {
    final rows = await _copyPhotos(goal, photos);
    onProgress?.call(CheckInProgressStep.saving);
    late final int id;
    try {
      id = await _assessments.recordCheckIn(
        CheckInRecord(
          goalId: goal.id,
          photos: rows,
          weightKg: weightKg,
          verdict: verdict,
          band: evidence?.band,
          confidence: evidence?.confidence ?? AssessmentConfidence.unknown,
          reason: reason,
          limitations: evidence?.limitations ?? const [],
          source: source,
          modelVersion: modelVersion,
          knowledgeVersion: knowledgeVersion,
        ),
      );
    } on Object {
      for (final row in rows) {
        await _store.delete(row.relativePath);
      }
      rethrow;
    }
    await _discardCommitted(photos);
    return CheckInRecorded(
      assessmentId: id,
      verdict: verdict,
      evidence: evidence,
      analyzed: source == 'ai',
    );
  }

  Future<void> _discardCommitted(List<StagedPosePhoto> photos) async {
    for (final p in photos) {
      try {
        await discardStaged(p.photo);
      } on FileSystemException {
        // The committed copy is durable; stale staging is cleaned next launch.
      }
    }
  }

  Future<List<PhysiqueCheckInImage>> _loadBaselines(int goalId) async {
    final rows = await _assessments.baselinePhotos(goalId);
    final ordered = [
      ...rows.where((r) => r.pose == 'front'),
      ...rows.where((r) => r.pose != 'front'),
    ];
    final out = <PhysiqueCheckInImage>[];
    for (final row in ordered) {
      if (out.length >= PhysiqueTuning.maxCheckInBaselinePhotos) {
        break;
      }
      try {
        final file = await _store.resolve(row.relativePath);
        if (!await file.exists()) {
          continue;
        }
        out.add(
          PhysiqueCheckInImage(
            pose: row.pose,
            jpeg: await _sanitizer.analysisBytes(file),
          ),
        );
      } on Object {
        continue;
      }
    }
    return out;
  }
}

final physiqueCheckInFlowProvider = Provider<PhysiqueCheckInFlow>((ref) {
  return PhysiqueCheckInFlow(
    sanitizer: ref.watch(physiquePhotoSanitizerProvider),
    store: ref.watch(physiquePhotoStoreProvider),
    assessments: ref.watch(physiqueAssessmentRepositoryProvider),
    service: ref.watch(physiqueCheckInServiceProvider),
    clock: ref.watch(clockProvider),
  );
});
