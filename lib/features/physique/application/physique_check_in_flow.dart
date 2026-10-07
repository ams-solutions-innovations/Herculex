import 'dart:io';
import 'dart:typed_data';

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
    if (blurFaces) onProgress?.call(CheckInProgressStep.checkingFaces);
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

  /// Baseline photos need no cap and no AI call.
  Future<CheckInOutcome> saveBaseline({
    required PhysiqueGoalData goal,
    required StagedPhoto staged,
    required String pose,
  }) async {
    final relative = await _store.adopt(staged.file, goalUuid: _goalUuid(goal));
    try {
      final id = await _assessments.addBaselinePhoto(
        goalId: goal.id,
        photo: NewPhotoRow(
          pose: pose,
          relativePath: relative,
          takenAt: _clock.now(),
          blurred: staged.blurApplied,
        ),
      );
      return BaselineSaved(id);
    } on Object {
      await _store.delete(relative);
      rethrow;
    }
  }

  Future<CheckInOutcome> completeCheckIn({
    required PhysiqueGoalData goal,
    required StagedPhoto staged,
    required String pose,
    required DietPhase phase,
    required int weeksInPhase,
    required bool analyze,
    required bool consentGranted,
    double? weightKg,
    double? weeklyTrendKg,
    void Function(CheckInProgressStep step)? onProgress,
  }) async {
    final goalUuid = _goalUuid(goal);

    // Pre-check only; recordCheckIn re-checks inside its transaction.
    final last = await _assessments.lastCheckInAt(goal.id);
    final now = _clock.now();
    if (!CheckInCapPolicy.isEligible(now: now, lastCheckInAt: last)) {
      throw CheckInTooSoonException(
        nextEligibleDate: CheckInCapPolicy.nextEligibleDate(last)!,
      );
    }

    if (!analyze) {
      return _persist(
        goal: goal,
        goalUuid: goalUuid,
        staged: staged,
        pose: pose,
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
      final current = await _sanitizer.analysisBytes(staged.file);
      analysis = await _service.analyze(
        baselineJpegs: baselines,
        currentJpeg: current,
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
        'This photo could not be read. Try taking it again.',
      );
    }

    final verdict = CheckInVerdictClassifier.classify(
      evidence: analysis.evidence,
      phase: phase,
      measuredWeeklyTrendKg: weeklyTrendKg,
    );
    return _persist(
      goal: goal,
      goalUuid: goalUuid,
      staged: staged,
      pose: pose,
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

  Future<CheckInOutcome> _persist({
    required PhysiqueGoalData goal,
    required String goalUuid,
    required StagedPhoto staged,
    required String pose,
    required CheckInVerdict verdict,
    required CheckInEvidence? evidence,
    required String reason,
    required String source,
    required void Function(CheckInProgressStep step)? onProgress,
    double? weightKg,
    String? modelVersion,
    String? knowledgeVersion,
  }) async {
    final relative = await _store.adopt(staged.file, goalUuid: goalUuid);
    onProgress?.call(CheckInProgressStep.saving);
    try {
      final id = await _assessments.recordCheckIn(
        CheckInRecord(
          goalId: goal.id,
          pose: pose,
          relativePath: relative,
          blurred: staged.blurApplied,
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
      return CheckInRecorded(
        assessmentId: id,
        verdict: verdict,
        evidence: evidence,
        analyzed: source == 'ai',
      );
    } on Object {
      await _store.delete(relative);
      rethrow;
    }
  }

  /// Up to three baseline images, front pose first. Missing or unreadable
  /// files are skipped.
  Future<List<Uint8List>> _loadBaselines(int goalId) async {
    final rows = await _assessments.baselinePhotos(goalId);
    final ordered = [
      ...rows.where((r) => r.pose == 'front'),
      ...rows.where((r) => r.pose != 'front'),
    ];
    final out = <Uint8List>[];
    for (final row in ordered) {
      if (out.length >= PhysiqueTuning.maxCheckInBaselinePhotos) break;
      try {
        final file = await _store.resolve(row.relativePath);
        if (!await file.exists()) continue;
        out.add(await _sanitizer.analysisBytes(file));
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
