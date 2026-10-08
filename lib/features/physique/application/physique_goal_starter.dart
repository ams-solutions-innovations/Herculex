import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/core/utils/clock.dart';
import 'package:herculex/features/nutrition/application/tdee_providers.dart';
import 'package:herculex/features/nutrition/domain/diet_phase.dart';
import 'package:herculex/features/physique/application/physique_providers.dart';
import 'package:herculex/features/physique/data/physique_dream_photo_repository.dart';
import 'package:herculex/features/physique/data/physique_goal_repository.dart';
import 'package:herculex/features/physique/data/physique_photo_sanitizer.dart';
import 'package:herculex/features/physique/data/physique_photo_store.dart';
import 'package:herculex/features/physique/data/physique_privacy_preferences.dart';
import 'package:herculex/features/physique/domain/physique_roadmap.dart';
import 'package:herculex/features/physique/domain/physique_tuning.dart';
import 'package:herculex/features/profile/data/dream_physique_service.dart';
import 'package:herculex/features/profile/data/dream_physique_summary_repository.dart';
import 'package:herculex/features/profile/domain/profile.dart';
import 'package:uuid/uuid.dart';

/// Turns a Dream Physique analysis into a persisted goal (D-01, D-03, D-07).
///
/// Staging and persisting are separate steps: the caller stages the photos,
/// shows the "No face found" dialog if needed, then persists. The starter
/// shows no UI and never deletes the original picker files.
class PhysiqueGoalStarter {
  PhysiqueGoalStarter({
    required PhysiqueGoalRepository goals,
    required PhysiquePhotoSanitizer sanitizer,
    required PhysiquePhotoStore store,
    required PhysiqueDreamPhotoRepository dreamPhotos,
    required PhysiquePrivacyPreferences privacy,
    required Clock clock,
    required Profile? Function() readProfile,
    required int? Function() readMaintenanceKcal,
  }) : _goals = goals,
       _sanitizer = sanitizer,
       _store = store,
       _dreamPhotos = dreamPhotos,
       _privacy = privacy,
       _clock = clock,
       _readProfile = readProfile,
       _readMaintenanceKcal = readMaintenanceKcal;

  final PhysiqueGoalRepository _goals;
  final PhysiquePhotoSanitizer _sanitizer;
  final PhysiquePhotoStore _store;
  final PhysiqueDreamPhotoRepository _dreamPhotos;
  final PhysiquePrivacyPreferences _privacy;
  final Clock _clock;
  final Profile? Function() _readProfile;
  final int? Function() _readMaintenanceKcal;

  /// Remembers the blur choice and sanitises up to three photos into temp
  /// files. A photo that cannot be processed is skipped.
  Future<List<StagedPhoto>> stagePhotos({
    required List<File> files,
    required bool blurFaces,
  }) async {
    await _privacy.setBlurFaces(blurFaces);
    final staged = <StagedPhoto>[];
    for (final file in files.take(PhysiqueTuning.maxCheckInBaselinePhotos)) {
      try {
        staged.add(await _sanitizer.stage(file, blurFaces: blurFaces));
      } on PhotoSanitizeException {
        continue;
      }
    }
    return staged;
  }

  Future<void> discardStaged(List<StagedPhoto> staged) async {
    for (final s in staged) {
      await _sanitizer.discard(s);
    }
  }

  /// Persists the goal, its proposed roadmap and the baseline photos, and
  /// archives the previous goal. Returns the new goal id.
  Future<int> startFromAnalysis({
    required DreamPhysiqueAnalysisResult result,
    required List<StagedPhoto> staged,
    required int targetPhotoCount,
    File? targetPhoto,
  }) async {
    final goalUuid = const Uuid().v4();
    try {
      final now = _clock.now();
      final profile = _readProfile();
      final roadmap = _proposeRoadmap(result, profile);

      final photos = <NewPhotoRow>[];
      for (final s in staged) {
        final relative = await _store.adopt(s.file, goalUuid: goalUuid);
        photos.add(
          NewPhotoRow(
            pose: 'front',
            relativePath: relative,
            takenAt: now,
            blurred: s.blurApplied,
          ),
        );
      }

      final summary = DreamPhysiqueAnalysisSummary.fromResult(
        result: result,
        currentPhotoCount: staged.length,
        targetPhotoCount: targetPhotoCount,
        analyzedAt: now.toUtc(),
      );

      final goalId = await _goals.startGoal(
        StartGoalInput(
          goalSyncUuid: goalUuid,
          source: 'ai_analysis',
          targetAestheticStyle: result.targetAestheticStyle,
          timeframeRange: result.timeframeRange,
          estimatedMonths: result.estimatedMonths,
          targetBfPercent: result.targetBfPercent,
          startWeightKg: profile?.weightKg,
          startBfPercent: result.currentEstimatedBf,
          analyses: [
            AnalysisInput(
              analyzedAt: now,
              currentBfPercent: result.currentEstimatedBf,
              bfRangeMin: result.currentBfRangeMin,
              bfRangeMax: result.currentBfRangeMax,
              confidence: result.assessmentConfidence,
              weightKg: profile?.weightKg,
              summaryJson: jsonEncode(summary.toJson()),
            ),
          ],
          roadmap: roadmap,
          baselinePhotos: photos,
          archiveExisting: true,
        ),
      );
      // Best effort: a reference photo that cannot be stored must not undo a
      // goal that was already persisted.
      if (targetPhoto != null) {
        await _dreamPhotos.save(targetPhoto, goalUuid: goalUuid);
      }
      return goalId;
    } on Object {
      await _store.deleteGoalFolder(goalUuid);
      await discardStaged(staged);
      rethrow;
    }
  }

  List<RoadmapPhaseDraft> _proposeRoadmap(
    DreamPhysiqueAnalysisResult result,
    Profile? profile,
  ) {
    final weight = profile?.weightKg;
    if (profile == null || weight == null) {
      return const [
        RoadmapPhaseDraft(
          phase: DietPhase.maintain,
          plannedWeeks: 4,
          weeklyRateKg: 0,
        ),
      ];
    }
    return PhysiqueRoadmapGenerator.propose(
      PhysiqueRoadmapInput(
        weightKg: weight,
        currentBfPercent: result.currentEstimatedBf,
        targetBfPercent: result.targetBfPercent,
        plannedWeightChangeKg: result.weightChangeKg,
        estimatedMonths: result.estimatedMonths,
        ageYears: profile.ageYears,
        confidence: result.assessmentConfidence,
        bfRangeMin: result.currentBfRangeMin,
        bfRangeMax: result.currentBfRangeMax,
        prefersWeightLoss: profile.goal == FitnessGoal.weightLoss,
        maintenanceKcal:
            _readMaintenanceKcal() ?? PhysiqueTuning.defaultMaintenanceKcal,
        fatLossKg: result.fatLossKg,
        leanGainKg: result.leanMuscleGainKg,
      ),
    ).phases;
  }
}

final physiqueGoalStarterProvider = Provider<PhysiqueGoalStarter>((ref) {
  return PhysiqueGoalStarter(
    goals: ref.watch(physiqueGoalRepositoryProvider),
    sanitizer: ref.watch(physiquePhotoSanitizerProvider),
    store: ref.watch(physiquePhotoStoreProvider),
    dreamPhotos: ref.watch(physiqueDreamPhotoRepositoryProvider),
    privacy: ref.watch(physiquePrivacyPreferencesProvider),
    clock: ref.watch(clockProvider),
    readProfile: () => ref.read(localProfileRepositoryProvider).currentProfile,
    readMaintenanceKcal: () => ref.read(maintenanceKcalProvider),
  );
});
