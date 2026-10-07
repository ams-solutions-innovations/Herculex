import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/data/local/database.dart';
import 'package:herculex/features/nutrition/domain/diet_phase.dart';
import 'package:herculex/features/nutrition/domain/phase_eligibility.dart';
import 'package:herculex/features/nutrition/domain/tdee_trend.dart';
import 'package:herculex/features/physique/data/ml_kit_face_detector.dart';
import 'package:herculex/features/physique/data/physique_assessment_repository.dart';
import 'package:herculex/features/physique/data/physique_checkin_service.dart';
import 'package:herculex/features/physique/data/physique_date_keys.dart';
import 'package:herculex/features/physique/data/physique_dream_photo_repository.dart';
import 'package:herculex/features/physique/data/physique_goal_repository.dart';
import 'package:herculex/features/physique/data/physique_legacy_migrator.dart';
import 'package:herculex/features/physique/data/physique_photo_sanitizer.dart';
import 'package:herculex/features/physique/data/physique_photo_store.dart';
import 'package:herculex/features/physique/data/physique_privacy_preferences.dart';
import 'package:herculex/features/physique/data/physique_roadmap_repository.dart';
import 'package:herculex/features/physique/data/physique_series_repository.dart';
import 'package:herculex/features/physique/domain/check_in_policy.dart';
import 'package:herculex/features/physique/domain/physique_guardrails.dart';
import 'package:herculex/features/physique/domain/roadmap_exit_criteria.dart';
import 'package:herculex/services/ai/gemini_backend_service.dart';
import 'package:path_provider/path_provider.dart';

// NOTE: physique_chart_providers.dart imports this file, never the reverse.

// --- repositories and services -------------------------------------------

final physiqueGoalRepositoryProvider = Provider<PhysiqueGoalRepository>((ref) {
  return PhysiqueGoalRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(clockProvider),
  );
});

final physiqueRoadmapRepositoryProvider = Provider<PhysiqueRoadmapRepository>((
  ref,
) {
  return PhysiqueRoadmapRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(clockProvider),
  );
});

final physiqueAssessmentRepositoryProvider =
    Provider<PhysiqueAssessmentRepository>((ref) {
      return PhysiqueAssessmentRepository(
        ref.watch(appDatabaseProvider),
        ref.watch(clockProvider),
      );
    });

final physiqueSeriesRepositoryProvider = Provider<PhysiqueSeriesRepository>((
  ref,
) {
  return PhysiqueSeriesRepository(ref.watch(appDatabaseProvider));
});

final physiquePhotoStoreProvider = Provider<PhysiquePhotoStore>((ref) {
  return PhysiquePhotoStore(
    documentsDirectory: getApplicationDocumentsDirectory,
  );
});

final physiquePhotoSanitizerProvider = Provider<PhysiquePhotoSanitizer>((ref) {
  return PhysiquePhotoSanitizer(faceDetector: MlKitFaceDetector());
});

final physiqueDreamPhotoRepositoryProvider =
    Provider<PhysiqueDreamPhotoRepository>((ref) {
      return PhysiqueDreamPhotoRepository(
        store: ref.watch(physiquePhotoStoreProvider),
        sanitizer: ref.watch(physiquePhotoSanitizerProvider),
      );
    });

/// The saved dream physique photo for the goal with this sync uuid. Invalidate
/// it after saving a new one.
final physiqueDreamPhotoProvider = FutureProvider.family<File?, String>((
  ref,
  goalUuid,
) {
  return ref.watch(physiqueDreamPhotoRepositoryProvider).find(goalUuid);
});

final physiquePrivacyPreferencesProvider = Provider<PhysiquePrivacyPreferences>(
  (ref) => PhysiquePrivacyPreferences(ref.watch(sharedPreferencesProvider)),
);

final physiqueCheckInServiceProvider = Provider<PhysiqueCheckInService>((ref) {
  return PhysiqueCheckInService(ref.watch(physiqueCheckInBackendProvider));
});

// --- streams --------------------------------------------------------------

final activePhysiqueGoalProvider = StreamProvider<PhysiqueGoalData?>((ref) {
  return ref.watch(physiqueGoalRepositoryProvider).watchActiveGoal();
});

final archivedPhysiqueGoalsProvider = StreamProvider<List<PhysiqueGoalData>>((
  ref,
) {
  return ref.watch(physiqueGoalRepositoryProvider).watchArchivedGoals();
});

final physiqueGoalProvider = StreamProvider.family<PhysiqueGoalData?, int>((
  ref,
  id,
) {
  return ref.watch(physiqueGoalRepositoryProvider).watchGoal(id);
});

final physiqueRoadmapPhasesProvider =
    StreamProvider.family<List<PhysiqueRoadmapPhaseData>, int>((ref, goalId) {
      return ref.watch(physiqueRoadmapRepositoryProvider).watchPhases(goalId);
    });

final physiqueCheckInsProvider =
    StreamProvider.family<List<PhysiqueAssessmentData>, int>((ref, goalId) {
      return ref
          .watch(physiqueAssessmentRepositoryProvider)
          .watchCheckIns(goalId);
    });

final physiqueLatestAnalysisProvider =
    StreamProvider.family<PhysiqueAssessmentData?, int>((ref, goalId) {
      return ref
          .watch(physiqueAssessmentRepositoryProvider)
          .watchLatestAnalysis(goalId);
    });

final physiqueLastCheckInAtProvider = StreamProvider.family<DateTime?, int>((
  ref,
  goalId,
) {
  return ref
      .watch(physiqueAssessmentRepositoryProvider)
      .watchLastCheckInAt(goalId);
});

final physiquePhotosProvider =
    StreamProvider.family<List<PhysiquePhotoData>, int>((ref, goalId) {
      return ref
          .watch(physiqueAssessmentRepositoryProvider)
          .watchPhotos(goalId);
    });

final physiqueWeightLogsProvider = StreamProvider<List<WeightLog>>((ref) {
  return ref.watch(physiqueSeriesRepositoryProvider).watchWeightLogs();
});

final physiqueMeasuredBodyFatProvider =
    StreamProvider<List<BodyMeasurementData>>((ref) {
      return ref.watch(measurementsRepositoryProvider).watchMetric('body_fat');
    });

// --- eligibility ----------------------------------------------------------

/// Age used for eligibility. While the profile stream loads, the synchronously
/// stored profile answers, so there is no unrestricted flash (D-05). Error,
/// no profile or no age all yield null, which restricts.
int? _eligibilityAge(Ref ref) {
  final profile = ref.watch(profileProvider);
  return profile.when(
    data: (p) => p?.ageYears,
    loading: () =>
        ref.watch(localProfileRepositoryProvider).currentProfile?.ageYears,
    error: (_, _) => null,
  );
}

/// Manual-editor eligibility: age only.
final physiqueEditorEligibilityProvider = Provider<PhaseEligibility>((ref) {
  return PhysiqueGuardrails.ageEligibility(_eligibilityAge(ref));
});

/// Roadmap and preset eligibility: age and the latest analysis confidence.
final physiqueRoadmapEligibilityProvider =
    Provider.family<PhaseEligibility, int>((ref, goalId) {
      final analysis = ref
          .watch(physiqueLatestAnalysisProvider(goalId))
          .asData
          ?.value;
      return PhysiqueGuardrails.evaluate(
        ageYears: _eligibilityAge(ref),
        confidence: AssessmentConfidence.fromWire(analysis?.confidence),
        bfRangeMin: analysis?.bfRangeMin,
        bfRangeMax: analysis?.bfRangeMax,
      );
    });

/// The date the next check-in unlocks, or null when one is allowed today.
final physiqueNextCheckInProvider = Provider.family<DateTime?, int>((
  ref,
  goalId,
) {
  final last = ref.watch(physiqueLastCheckInAtProvider(goalId)).asData?.value;
  final next = CheckInCapPolicy.nextEligibleDate(last);
  if (next == null) return null;
  final now = ref.watch(clockProvider).now();
  final today = DateTime(now.year, now.month, now.day);
  return next.isAfter(today) ? next : null;
});

// --- body fat reading -----------------------------------------------------

enum PhysiqueBfSource { measured, estimate, none }

class PhysiqueBfReading {
  const PhysiqueBfReading({
    required this.percent,
    required this.source,
    required this.reliable,
  });

  static const none = PhysiqueBfReading(
    percent: null,
    source: PhysiqueBfSource.none,
    reliable: false,
  );

  final double? percent;
  final PhysiqueBfSource source;
  final bool reliable;
}

/// Latest logged body fat since the goal started, else the baseline analysis
/// estimate (reliable only when its confidence is not low).
final physiqueBodyFatReadingProvider = Provider.family<PhysiqueBfReading, int>((
  ref,
  goalId,
) {
  final goal = ref.watch(physiqueGoalProvider(goalId)).asData?.value;
  final measured =
      ref.watch(physiqueMeasuredBodyFatProvider).asData?.value ?? const [];
  if (goal != null) {
    final since = physiqueDayKey(goal.startedAt);
    BodyMeasurementData? latest;
    for (final m in measured) {
      if (m.deletedAt != null || m.dateIso.compareTo(since) < 0) continue;
      if (latest == null || m.dateIso.compareTo(latest.dateIso) >= 0) {
        latest = m;
      }
    }
    if (latest != null) {
      return PhysiqueBfReading(
        percent: latest.value,
        source: PhysiqueBfSource.measured,
        reliable: true,
      );
    }
  }
  final analysis = ref
      .watch(physiqueLatestAnalysisProvider(goalId))
      .asData
      ?.value;
  final estimate = analysis?.currentBfPercent;
  if (analysis != null && estimate != null) {
    final confidence = AssessmentConfidence.fromWire(analysis.confidence);
    return PhysiqueBfReading(
      percent: estimate,
      source: PhysiqueBfSource.estimate,
      reliable: confidence != AssessmentConfidence.low,
    );
  }
  return PhysiqueBfReading.none;
});

// --- phase status ---------------------------------------------------------

class PhysiquePhaseStatus {
  const PhysiquePhaseStatus({
    required this.current,
    required this.next,
    required this.position,
    required this.total,
    required this.evaluation,
    required this.offerAdvance,
    required this.proposalPending,
    required this.bfReading,
    required this.logMeasurementsHint,
  });

  final PhysiqueRoadmapPhaseData? current;
  final PhysiqueRoadmapPhaseData? next;

  /// 1-based position of the current phase; 0 while no phase is current.
  final int position;
  final int total;
  final ExitEvaluation? evaluation;
  final bool offerAdvance;
  final bool proposalPending;
  final PhysiqueBfReading bfReading;
  final bool logMeasurementsHint;
}

DietPhase _dietPhaseOf(String name) {
  for (final p in DietPhase.values) {
    if (p.name == name) return p;
  }
  return DietPhase.maintain;
}

/// Phase position, exit evaluation and advance offer. Derived only; the offer
/// is a value for the UI, never a write (D-02). Null until the goal and its
/// phases have loaded.
final physiquePhaseStatusProvider = Provider.family<PhysiquePhaseStatus?, int>((
  ref,
  goalId,
) {
  final goal = ref.watch(physiqueGoalProvider(goalId)).asData?.value;
  final phases = ref.watch(physiqueRoadmapPhasesProvider(goalId)).asData?.value;
  if (goal == null || phases == null) return null;
  final now = ref.watch(clockProvider).now();
  final weights =
      ref.watch(physiqueWeightLogsProvider).asData?.value ?? const [];
  final bf = ref.watch(physiqueBodyFatReadingProvider(goalId));
  final analysis = ref
      .watch(physiqueLatestAnalysisProvider(goalId))
      .asData
      ?.value;

  final currentIdx = phases.indexWhere((p) => p.status == 'current');
  final current = currentIdx < 0 ? null : phases[currentIdx];
  final next = phases
      .skip(currentIdx < 0 ? 0 : currentIdx + 1)
      .where((p) => p.status == 'upcoming')
      .firstOrNull;
  final proposalPending = goal.roadmapAcceptedAt == null;

  ExitEvaluation? evaluation;
  if (current != null) {
    evaluation = RoadmapExitEvaluator.evaluate(
      phase: PhaseProgress(
        phase: _dietPhaseOf(current.phaseType),
        plannedWeeks: current.plannedWeeks,
        startedAt: current.startedAt ?? goal.startedAt,
        targetWeightKg: current.targetWeightKg,
        targetBfPercent: current.targetBfPercent,
      ),
      now: now,
      latestWeightKg: weights.isEmpty ? null : weights.last.kg,
      latestBfPercent: bf.percent,
      bfEstimateReliable: bf.reliable,
    );
  }
  final offer =
      evaluation != null &&
      !proposalPending &&
      next != null &&
      RoadmapExitEvaluator.shouldOfferAdvance(
        evaluation: evaluation,
        hasNextPhase: true,
        now: now,
        snoozedUntil: goal.advanceSnoozedUntil,
      );

  final confidence = AssessmentConfidence.fromWire(analysis?.confidence);
  final hint =
      bf.source != PhysiqueBfSource.measured &&
      (bf.source == PhysiqueBfSource.none ||
          confidence == AssessmentConfidence.low ||
          confidence == AssessmentConfidence.unknown);

  return PhysiquePhaseStatus(
    current: current,
    next: next,
    position: currentIdx + 1,
    total: phases.length,
    evaluation: evaluation,
    offerAdvance: offer,
    proposalPending: proposalPending,
    bfReading: bf,
    logMeasurementsHint: hint,
  );
});

// --- startup --------------------------------------------------------------

/// Runs the legacy migration once per launch, then always reconciles a second
/// device's duplicate active goal (RESEARCH Pitfall 8). Never throws: a failed
/// migration returns null so the next launch retries.
final physiqueLegacyMigrationProvider = FutureProvider<LegacyMigrationResult?>((
  ref,
) async {
  final goals = ref.read(physiqueGoalRepositoryProvider);
  LegacyMigrationResult? result;
  try {
    final migrator = PhysiqueLegacyMigrator(
      db: ref.read(appDatabaseProvider),
      goals: goals,
      sanitizer: ref.read(physiquePhotoSanitizerProvider),
      store: ref.read(physiquePhotoStoreProvider),
      summaries: ref.read(dreamPhysiqueSummaryRepositoryProvider),
      prefs: ref.read(sharedPreferencesProvider),
      readProfile: () =>
          ref.read(localProfileRepositoryProvider).currentProfile,
      clock: ref.read(clockProvider),
    );
    result = await migrator.run();
  } on Object catch (e) {
    debugPrint('Physique legacy migration failed: $e');
  }
  try {
    await goals.reconcileSingleActive();
  } on Object catch (e) {
    debugPrint('Physique goal reconcile failed: $e');
  }
  return result;
});
