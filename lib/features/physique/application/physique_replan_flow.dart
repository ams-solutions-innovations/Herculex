import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/core/utils/clock.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/nutrition/application/tdee_providers.dart';
import 'package:herculex/features/nutrition/domain/diet_phase.dart';
import 'package:herculex/features/physique/application/physique_providers.dart';
import 'package:herculex/features/physique/data/physique_assessment_repository.dart';
import 'package:herculex/features/physique/data/physique_dream_photo_repository.dart';
import 'package:herculex/features/physique/data/physique_goal_repository.dart';
import 'package:herculex/features/physique/data/physique_photo_sanitizer.dart';
import 'package:herculex/features/physique/data/physique_photo_store.dart';
import 'package:herculex/features/physique/domain/check_in_policy.dart';
import 'package:herculex/features/physique/domain/physique_roadmap.dart';
import 'package:herculex/features/physique/domain/physique_tuning.dart';
import 'package:herculex/features/profile/data/dream_physique_service.dart';
import 'package:herculex/features/profile/data/dream_physique_summary_repository.dart';
import 'package:herculex/features/profile/domain/profile.dart';

/// Why a roadmap update cannot start. Nothing was sent to the AI.
enum ReplanBlock {
  /// The roadmap was never accepted, so there is nothing to update yet.
  notStarted,

  /// No dream physique photo is stored on this device for the goal.
  noDreamPhoto,

  /// No current weight to plan from.
  noWeight,

  /// An analysis was made less than a check-in window ago.
  tooSoon,
}

class ReplanBlockedException implements Exception {
  const ReplanBlockedException(this.block, {this.nextEligibleDate});

  final ReplanBlock block;
  final DateTime? nextEligibleDate;

  @override
  String toString() => 'ReplanBlockedException($block)';
}

/// A fresh analysis and the roadmap built from it. Nothing is stored until the
/// member accepts it with [PhysiqueReplanFlow.apply] (the AI proposes, the
/// member confirms).
class ReplanProposal {
  const ReplanProposal({
    required this.analysis,
    required this.proposal,
    required this.phases,
    required this.weightKg,
    required this.analyzedAt,
  });

  final DreamPhysiqueAnalysisResult analysis;
  final PhysiqueRoadmapProposal proposal;

  /// [proposal]'s phases, with the running phase's elapsed time carried over
  /// when the new roadmap continues it.
  final List<RoadmapPhaseDraft> phases;
  final double weightKg;
  final DateTime analyzedAt;
}

/// "Update roadmap": new photo, new AI analysis against the dream photo, a
/// deterministic roadmap from today's weight, member confirms, one write.
class PhysiqueReplanFlow {
  PhysiqueReplanFlow({
    required DreamPhysiqueService service,
    required PhysiqueDreamPhotoRepository dreamPhotos,
    required PhysiqueAssessmentRepository assessments,
    required PhysiqueGoalRepository goals,
    required PhysiquePhotoStore store,
    required Clock clock,
    required Profile? Function() readProfile,
    required int? Function() readMaintenanceKcal,
  }) : _service = service,
       _dreamPhotos = dreamPhotos,
       _assessments = assessments,
       _goals = goals,
       _store = store,
       _clock = clock,
       _readProfile = readProfile,
       _readMaintenanceKcal = readMaintenanceKcal;

  final DreamPhysiqueService _service;
  final PhysiqueDreamPhotoRepository _dreamPhotos;
  final PhysiqueAssessmentRepository _assessments;
  final PhysiqueGoalRepository _goals;
  final PhysiquePhotoStore _store;
  final Clock _clock;
  final Profile? Function() _readProfile;
  final int? Function() _readMaintenanceKcal;

  /// Checks everything that can be checked without the AI.
  ///
  /// Throws [ReplanBlockedException] when the update cannot run, so the
  /// caller can say why before the member takes a photo.
  Future<void> checkReady(PhysiqueGoalData goal, {double? weightKg}) async {
    if (goal.roadmapAcceptedAt == null) {
      throw const ReplanBlockedException(ReplanBlock.notStarted);
    }
    final uuid = goal.syncUuid;
    if (uuid == null || await _dreamPhotos.find(uuid) == null) {
      throw const ReplanBlockedException(ReplanBlock.noDreamPhoto);
    }
    if (weightKg == null || weightKg <= 0) {
      throw const ReplanBlockedException(ReplanBlock.noWeight);
    }
    final last = await _assessments.latestAnalysisAt(goal.id);
    if (!CheckInCapPolicy.isEligible(now: _clock.now(), lastCheckInAt: last)) {
      throw ReplanBlockedException(
        ReplanBlock.tooSoon,
        nextEligibleDate: CheckInCapPolicy.nextEligibleDate(last),
      );
    }
  }

  /// Sends [staged] and the stored dream photo for analysis and builds the
  /// proposed roadmap from today's [weightKg]. [currentPhase] and
  /// [weeksInPhase] describe the phase running now.
  Future<ReplanProposal> analyse({
    required PhysiqueGoalData goal,
    required StagedPhoto staged,
    required bool consentGranted,
    required double? weightKg,
    required DietPhase currentPhase,
    required int weeksInPhase,
  }) async {
    await checkReady(goal, weightKg: weightKg);
    final weight = weightKg!;
    final dream = (await _dreamPhotos.find(goal.syncUuid!))!;
    final profile = _readProfile();

    final result = await _service.compareAndAnalyzePhysique(
      currentImages: [staged.file],
      targetImages: [dream],
      consentGranted: consentGranted,
      profile: profile?.copyWith(weightKg: weight),
    );

    final proposal = PhysiqueRoadmapGenerator.propose(
      PhysiqueRoadmapInput(
        weightKg: weight,
        currentBfPercent: result.currentEstimatedBf,
        targetBfPercent: result.targetBfPercent,
        plannedWeightChangeKg: result.weightChangeKg,
        estimatedMonths: result.estimatedMonths,
        ageYears: profile?.ageYears,
        confidence: result.assessmentConfidence,
        bfRangeMin: result.currentBfRangeMin,
        bfRangeMax: result.currentBfRangeMax,
        prefersWeightLoss: profile?.goal == FitnessGoal.weightLoss,
        maintenanceKcal:
            _readMaintenanceKcal() ?? PhysiqueTuning.defaultMaintenanceKcal,
        fatLossKg: result.fatLossKg,
        leanGainKg: result.leanMuscleGainKg,
      ),
    );

    // A roadmap that carries on with the running phase keeps its start date,
    // so the weeks already spent in it count toward its length.
    final phases = [...proposal.phases];
    if (phases.first.phase == currentPhase && weeksInPhase > 0) {
      phases[0] = phases.first.copyWith(
        plannedWeeks: math.min(
          PhysiqueTuning.maxPhaseWeeks,
          weeksInPhase + phases.first.plannedWeeks,
        ),
      );
    }
    return ReplanProposal(
      analysis: result,
      proposal: proposal,
      phases: List.unmodifiable(phases),
      weightKg: weight,
      analyzedAt: _clock.now(),
    );
  }

  /// Stores the analysis, its photo and the new roadmap in one transaction.
  /// The photo is moved out of staging, so [staged] is spent afterwards.
  Future<void> apply({
    required PhysiqueGoalData goal,
    required ReplanProposal proposal,
    required StagedPhoto staged,
    required String pose,
  }) async {
    final uuid = goal.syncUuid;
    if (uuid == null) {
      throw StateError('Physique goal ${goal.id} has no sync uuid');
    }
    final result = proposal.analysis;
    final now = _clock.now();
    final summary = DreamPhysiqueAnalysisSummary.fromResult(
      result: result,
      currentPhotoCount: 1,
      targetPhotoCount: 1,
      analyzedAt: proposal.analyzedAt.toUtc(),
    );
    final relative = await _store.adopt(staged.file, goalUuid: uuid);
    try {
      await _goals.applyReanalysis(
        goalId: goal.id,
        analysis: AnalysisInput(
          analyzedAt: proposal.analyzedAt,
          currentBfPercent: result.currentEstimatedBf,
          bfRangeMin: result.currentBfRangeMin,
          bfRangeMax: result.currentBfRangeMax,
          confidence: result.assessmentConfidence,
          weightKg: proposal.weightKg,
          summaryJson: jsonEncode(summary.toJson()),
        ),
        estimatedMonths: result.estimatedMonths,
        targetBfPercent: result.targetBfPercent,
        roadmap: proposal.phases,
        photo: NewPhotoRow(
          pose: pose,
          relativePath: relative,
          takenAt: now,
          blurred: staged.blurApplied,
        ),
      );
    } on Object {
      await _store.delete(relative);
      rethrow;
    }
  }
}

final physiqueReplanFlowProvider = Provider<PhysiqueReplanFlow>((ref) {
  return PhysiqueReplanFlow(
    service: ref.watch(dreamPhysiqueServiceProvider),
    dreamPhotos: ref.watch(physiqueDreamPhotoRepositoryProvider),
    assessments: ref.watch(physiqueAssessmentRepositoryProvider),
    goals: ref.watch(physiqueGoalRepositoryProvider),
    store: ref.watch(physiquePhotoStoreProvider),
    clock: ref.watch(clockProvider),
    readProfile: () => ref.read(localProfileRepositoryProvider).currentProfile,
    readMaintenanceKcal: () => ref.read(maintenanceKcalProvider),
  );
});
