part of '../smart_program_planner.dart';

/// Runs only when both of `_createStableSlots`'s candidate-filter blocks
/// (hard-filter-complete per Tasks 1-2) produced an empty candidate list.
///
/// Consults the movement pattern's scaling ladder (D-03) for a safer
/// regression before accepting that the slot is genuinely, safely empty
/// (D-01) — a legitimate gym/injury combination that exhausts a slot's
/// candidates must never abort the whole `populate()` transaction.
SelectionExplanation _resolveEmptyCandidatePool({
  required String? needPattern,
  required List<ExerciseCatalogData> catalog,
  required _EquipmentProfile equipment,
  required SmartProgramConfiguration configuration,
  required Set<String> completedExerciseSlugs,
  required Set<String> completedMovementSlugs,
  required Map<String, ExerciseCatalogData> catalogBySlug,
}) {
  final ladderMembers =
      (needPattern == null
              ? catalog
              : catalog.where((e) => e.movementPattern == needPattern))
          .where((e) => e.scalingGroup != null && e.scalingOrder != null)
          .toList(growable: false);

  if (ladderMembers.isEmpty) {
    return SelectionExplanation.empty(
      rationale:
          'No safe ${needPattern ?? 'matching'} movement available for '
          'your equipment/injuries.',
    );
  }

  // Ties are broken by catalog iteration order, mirroring List.reduce.
  final target = ladderMembers.reduce(
    (a, b) => b.scalingOrder! > a.scalingOrder! ? b : a,
  );

  final groupCandidates = catalog
      .where((e) => e.scalingGroup == target.scalingGroup)
      .toList(growable: false);

  final availableEquipmentKeys = equipment.allEquipment
      ? {
          for (final candidate in groupCandidates)
            ...(candidate.requiredEquipmentKeys == null
                ? [candidate.modality]
                : (jsonDecode(candidate.requiredEquipmentKeys!) as List)
                      .cast<String>()),
        }
      : equipment.keys;

  final result = const ExerciseScalingResolver().regress(
    target: target,
    groupCandidates: groupCandidates,
    experience: configuration.experience,
    style: configuration.trainingStyle,
    availableEquipmentKeys: availableEquipmentKeys,
    completedExerciseSlugs: completedExerciseSlugs,
    completedMovementSlugs: completedMovementSlugs,
    catalogBySlug: catalogBySlug,
  );

  if (result.isSuccess) {
    return SelectionExplanation.filled(
      exerciseId: result.candidate!.id,
      rationale: result.rationale,
    );
  }
  return SelectionExplanation.empty(rationale: result.rationale);
}
