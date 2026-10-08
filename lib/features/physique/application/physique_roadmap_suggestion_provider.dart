import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/features/nutrition/application/tdee_providers.dart';
import 'package:herculex/features/physique/application/physique_providers.dart';
import 'package:herculex/features/physique/domain/physique_guardrails.dart';
import 'package:herculex/features/physique/domain/physique_roadmap.dart';
import 'package:herculex/features/physique/domain/physique_tuning.dart';
import 'package:herculex/features/profile/data/dream_physique_summary_repository.dart';

DreamPhysiqueAnalysisSummary? _summaryOf(String? summaryJson) {
  if (summaryJson == null) return null;
  try {
    final decoded = jsonDecode(summaryJson);
    if (decoded is! Map<String, dynamic>) return null;
    return DreamPhysiqueAnalysisSummary.fromJson(decoded);
  } on Object {
    return null;
  }
}

/// The deterministic roadmap the generator would propose for [goalId] today,
/// used by "Reset to suggestion". Null when it cannot be built: no usable
/// profile weight, no analysis, or a photos-only legacy goal with no target
/// or timeframe (D-08).
final physiqueRoadmapSuggestionProvider =
    Provider.family<PhysiqueRoadmapProposal?, int>((ref, goalId) {
      final goal = ref.watch(physiqueGoalProvider(goalId)).asData?.value;
      final analysis = ref
          .watch(physiqueLatestAnalysisProvider(goalId))
          .asData
          ?.value;
      final profile = ref.watch(profileProvider).asData?.value;
      if (goal == null || analysis == null) return null;
      final targetBf = goal.targetBfPercent;
      final months = goal.estimatedMonths;
      final currentBf = analysis.currentBfPercent;
      final weight = profile?.weightKg;
      if (targetBf == null ||
          months == null ||
          currentBf == null ||
          weight == null ||
          weight <= 0) {
        return null;
      }
      final summary = _summaryOf(analysis.summaryJson);
      return PhysiqueRoadmapGenerator.propose(
        PhysiqueRoadmapInput(
          weightKg: weight,
          currentBfPercent: currentBf,
          targetBfPercent: targetBf,
          plannedWeightChangeKg: summary?.weightChangeKg ?? 0,
          fatLossKg: summary?.fatLossKg,
          leanGainKg: summary?.leanGainKg,
          estimatedMonths: months,
          ageYears: profile?.ageYears,
          confidence: AssessmentConfidence.fromWire(analysis.confidence),
          bfRangeMin: analysis.bfRangeMin,
          bfRangeMax: analysis.bfRangeMax,
          maintenanceKcal:
              ref.watch(maintenanceKcalProvider) ??
              PhysiqueTuning.defaultMaintenanceKcal,
        ),
      );
    });
