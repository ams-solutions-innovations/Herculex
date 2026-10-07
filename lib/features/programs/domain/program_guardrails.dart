import 'package:herculex/features/programs/domain/periodization.dart';
import 'package:herculex/features/programs/domain/primary_lift_specialization.dart';
import 'package:herculex/features/programs/domain/programming_models.dart';
import 'package:herculex/features/programs/domain/slot_role.dart';
import 'package:herculex/features/programs/domain/split_template.dart';
import 'package:herculex/features/programs/domain/volume_bands.dart';

enum GuardrailSeverity { warning, blocking }

class ProgramGuardrailIssue {
  const ProgramGuardrailIssue({
    required this.code,
    required this.message,
    required this.severity,
  });

  final String code;
  final String message;
  final GuardrailSeverity severity;

  bool get isBlocking => severity == GuardrailSeverity.blocking;
}

/// Minimal slot information needed to validate a materialized week.
class GuardedProgramSlot {
  const GuardedProgramSlot({
    required this.slotKey,
    required this.sessionKey,
    required this.startsAt,
    required this.role,
    required this.method,
    required this.movementPattern,
    this.poolSize = 0,
    this.rotates = false,
    this.fixedWeeks = 1,
  });

  final String slotKey;
  final String sessionKey;
  final DateTime startsAt;
  final SlotRole role;
  final SlotTrainingMethod method;
  final String movementPattern;
  final int poolSize;
  final bool rotates;
  final int fixedWeeks;

  bool get isMaxEffort => method == SlotTrainingMethod.maxEffort;
}

/// Safety rules that must pass before a Smart preview can be activated.
abstract final class ProgramGuardrails {
  static const maxEffortMinimumGap = Duration(hours: 72);
  static const maxSmartMaxEffortSlotsPerWeek = 2;

  /// Per-experience ceiling (kg) above which a specialization's requested
  /// current→target increase is flagged as unrealistic (D-11).
  ///
  /// These are RESEARCH.md's WebSearch-grounded proposal (Assumptions Log A2,
  /// LOW-MEDIUM confidence, not a locked CONTEXT.md decision) — tunable, not
  /// settled fact.
  static const kgIncreaseCeilings = <ExperienceLevel, double>{
    ExperienceLevel.novice: 50,
    ExperienceLevel.intermediate: 30,
    ExperienceLevel.advanced: 15,
  };

  static List<ProgramGuardrailIssue> validateMaxEffortWeek(
    Iterable<GuardedProgramSlot> slots, {
    bool smartMode = true,
  }) {
    final issues = <ProgramGuardrailIssue>[];
    final maxSlots = slots.where((s) => s.isMaxEffort).toList()
      ..sort((a, b) => a.startsAt.compareTo(b.startsAt));

    final bySession = <String, int>{};
    for (final slot in maxSlots) {
      bySession.update(
        slot.sessionKey,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
      if (!slot.role.isHeavy) {
        issues.add(
          ProgramGuardrailIssue(
            code: 'max_effort_role',
            message:
                'Max Effort is only available for a main or supplemental slot.',
            severity: GuardrailSeverity.blocking,
          ),
        );
      }
      if (slot.rotates && slot.poolSize < 3) {
        issues.add(
          ProgramGuardrailIssue(
            code: 'max_effort_pool',
            message:
                'Add at least three suitable variations before enabling Smart Max Effort rotation.',
            severity: GuardrailSeverity.blocking,
          ),
        );
      }
      if (!slot.rotates && slot.fixedWeeks > 3) {
        issues.add(
          ProgramGuardrailIssue(
            code: 'fixed_max_effort_too_long',
            message:
                'A fixed Max Effort lift is limited to three weeks; use a rotation or Top Set + Back-Off.',
            severity: GuardrailSeverity.blocking,
          ),
        );
      }
    }

    for (final count in bySession.values) {
      if (count > 1) {
        issues.add(
          const ProgramGuardrailIssue(
            code: 'max_effort_per_session',
            message: 'Only one Max Effort lift is allowed in a workout.',
            severity: GuardrailSeverity.blocking,
          ),
        );
      }
    }
    if (smartMode && maxSlots.length > maxSmartMaxEffortSlotsPerWeek) {
      issues.add(
        const ProgramGuardrailIssue(
          code: 'max_effort_per_week',
          message:
              'A Smart program can schedule at most two Max Effort slots per week.',
          severity: GuardrailSeverity.blocking,
        ),
      );
    }

    for (var i = 0; i < maxSlots.length; i++) {
      for (var j = i + 1; j < maxSlots.length; j++) {
        final a = maxSlots[i];
        final b = maxSlots[j];
        if (a.movementPattern != b.movementPattern) continue;
        if (b.startsAt.difference(a.startsAt) < maxEffortMinimumGap) {
          issues.add(
            ProgramGuardrailIssue(
              code: 'max_effort_gap',
              message:
                  '${a.movementPattern} Max Effort sessions need at least 72 hours between them.',
              severity: GuardrailSeverity.blocking,
            ),
          );
        }
      }
    }
    return issues;
  }

  /// A Max Effort top set consumes the largest single chunk of the day. This
  /// keeps the remaining compound work below the original CNS/axial budget.
  static int remainingFatigueBudget({
    required int originalBudget,
    required SlotTrainingMethod method,
  }) {
    if (method != SlotTrainingMethod.maxEffort) return originalBudget;
    return (originalBudget - 4).clamp(0, originalBudget);
  }

  /// Validates a proposed build configuration before any slot is
  /// materialized: the chosen split, periodization model and per-day method
  /// selections. Mirrors [validateMaxEffortWeek]'s shape (a pure function
  /// returning issues rather than throwing) so both `_create()` (all build
  /// modes) and the Herculex AI brief validator can share one guardrail home
  /// and choose their own UX for a blocking issue.
  static List<ProgramGuardrailIssue> validateConfiguration({
    required ProgramBuildMode buildMode,
    required PeriodizationModel model,
    required SplitType split,
    required Map<String, SlotTrainingMethod> mainMethodByDayLabel,
  }) {
    final issues = <ProgramGuardrailIssue>[];
    final explicitMaxEffort = mainMethodByDayLabel.values
        .where((m) => m == SlotTrainingMethod.maxEffort)
        .length;
    if (buildMode != ProgramBuildMode.manual && explicitMaxEffort > 2) {
      issues.add(
        const ProgramGuardrailIssue(
          code: 'config_max_effort_per_week',
          message:
              'A Smart program can use at most two Max Effort patterns per week.',
          severity: GuardrailSeverity.blocking,
        ),
      );
    }
    if (buildMode != ProgramBuildMode.manual &&
        model == PeriodizationModel.maxEffort &&
        split == SplitType.ppl) {
      issues.add(
        const ProgramGuardrailIssue(
          code: 'config_six_day_ppl_max_effort',
          message:
              'A six-day PPL would create three Max Effort days. Use per-slot Max Effort or choose a Conjugate 3–4 day structure.',
          severity: GuardrailSeverity.blocking,
        ),
      );
    }
    return issues;
  }

  static bool smartMaxEffortEligible({
    required ExperienceLevel level,
    required TrainingGoal goal,
    required MaxEffortEligibility eligibility,
  }) {
    final levelOkay = level != ExperienceLevel.novice;
    final goalOkay =
        goal == TrainingGoal.strength || goal == TrainingGoal.powerbuilding;
    return levelOkay &&
        goalOkay &&
        eligibility == MaxEffortEligibility.eligible;
  }

  /// Flags a primary-lift specialization's requested current→target increase
  /// as unrealistic for the user's experience tier (D-11). Warning-severity
  /// only — never blocks block creation.
  static List<ProgramGuardrailIssue> validateKgIncrease({
    required PrimaryLiftSpecialization specialization,
    required ExperienceLevel experience,
  }) {
    final increase = (specialization.targetKg - specialization.currentKg).clamp(
      0,
      double.infinity,
    );
    final ceiling =
        kgIncreaseCeilings[experience] ??
        kgIncreaseCeilings[ExperienceLevel.intermediate]!;
    if (increase <= ceiling) return const [];
    return [
      ProgramGuardrailIssue(
        code: 'specialization_kg_increase',
        message:
            'Adding ${increase.round()} kg to your ${specialization.lift.label} '
            'is outside typical progress for ${experience.label.toLowerCase()} '
            'lifters, even over ${specialization.weeks} weeks. Consider a '
            'smaller target or a longer block.',
        severity: GuardrailSeverity.warning,
      ),
    ];
  }

  /// Flags any muscle group whose planned weekly sets fall below its
  /// maintenance-volume minimum (D-04–D-07). Warning-severity only — never
  /// blocks block creation.
  ///
  /// Known coverage gap (RESEARCH.md Pitfall 1): `ProgramVolumeCalculator`'s
  /// 14-group muscle vocabulary does not fully align with `VolumeBands
  /// .priors`'s 19 groups — e.g. "Shoulders" gets the generic fallback band
  /// `(6, 14, 20)` instead of a delt-specific one. This is a known coarser
  /// approximation, not a bug.
  static List<ProgramGuardrailIssue> validateVolumeFloor(
    Map<String, num> weeklySetsByGroup,
  ) {
    final issues = <ProgramGuardrailIssue>[];
    for (final entry in weeklySetsByGroup.entries) {
      final band = VolumeBands.forGroup(entry.key);
      if (band.verdict(entry.value) != VolumeVerdict.low) continue;
      issues.add(
        ProgramGuardrailIssue(
          code: 'specialization_volume_floor',
          message:
              '${entry.key} would get ${_formatSets(entry.value)} sets/week '
              'with this specialization, below the ${band.minimum}-set '
              'minimum for maintenance. You can still create this block.',
          severity: GuardrailSeverity.warning,
        ),
      );
    }
    return issues;
  }

  /// Mirrors `MuscleVolumeEntry.formattedSets`'s whole-vs-one-decimal rule.
  static String _formatSets(num sets) {
    final asDouble = sets.toDouble();
    if (asDouble == asDouble.roundToDouble()) {
      return asDouble.toInt().toString();
    }
    return asDouble.toStringAsFixed(1);
  }
}
