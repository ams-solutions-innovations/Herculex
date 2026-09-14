import 'package:herculex/features/programs/domain/programming_models.dart';
import 'package:herculex/features/programs/domain/slot_role.dart';

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
}
