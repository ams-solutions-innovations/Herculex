# Phase 17: Deterministic Program Planner & Hard Guardrails - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-09-13
**Phase:** 17-deterministic-program-planner-hard-guardrails
**Areas discussed:** No-safe-candidate behavior, Injury/pain as a hard filter, Anchor lift guarantee mechanism

---

## No-Safe-Candidate Behavior

| Option | Description | Selected |
|--------|-------------|----------|
| Leave slot empty + flag it | No exercise assigned; SelectionExplanation records why | ✓ |
| Fill with nearest safe scaling-ladder regression | Consult ExerciseScalingResolver before giving up | |
| Keep current relax-then-fill fallback | Pattern/muscle relax, hard gates stay hard | |

**User's choice:** Leave slot empty + flag it

| Option | Description | Selected |
|--------|-------------|----------|
| Only the 5 named filters | Pattern/muscle is a soft preference, may relax | ✓ |
| Pattern/muscle counts as hard too | Swapping pattern/muscle is itself a silent relaxation | |

**User's choice:** Only the 5 named filters (injury, equipment, style, experience, prerequisites)

| Option | Description | Selected |
|--------|-------------|----------|
| Visible gap with explanation | Day shows fewer exercises + a note; needs new UI | ✓ |
| Backend-only for now | SelectionExplanation stored but no UI change in Phase 17 | |

**User's choice:** Visible gap with explanation

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, scaling ladder first | Only declare empty after scaling resolver also returns null | ✓ |
| No, scaling is separate | Scaling resolver only for explicit replacement requests | |

**User's choice:** Yes, scaling ladder first

**Notes:** This directly targets the existing "never leave a Smart slot empty" fallback at `smart_program_planner.dart:335-358`, which today relaxes pattern/muscle only — confirmed that behavior is fine to keep, but the fallback must never be extended to relax equipment/injury/style/experience/prerequisite gates.

---

## Injury/Pain as a Hard Filter

| Option | Description | Selected |
|--------|-------------|----------|
| Reuse JointModel.influencingMuscles | Same mapping/threshold already used by Recovery's TrainingSuggestion | ✓ |
| New movement-pattern-based mapping | More precise but duplicates existing Recovery logic | |

**User's choice:** Reuse JointModel.influencingMuscles

| Option | Description | Selected |
|--------|-------------|----------|
| Any flagged severity (>=1) excludes hard | Matches "no silently relaxed filters" principle | ✓ |
| Only moderate/severe (>=2) excludes hard | Mild soreness only lowers scoring | |

**User's choice:** Any flagged severity (>=1) excludes hard

| Option | Description | Selected |
|--------|-------------|----------|
| Explicit field on the request | Computed once by caller; keeps planner pure/testable | ✓ |
| Planner queries repository directly | Simpler wiring but couples planner to live DB | |

**User's choice:** Explicit field on the request

| Option | Description | Selected |
|--------|-------------|----------|
| Same visible-gap behavior | Injury exclusion is just one of the 5 hard filters | ✓ |
| Fall back to any non-excluded movement | Give any safe exercise rather than an empty slot | |

**User's choice:** Same visible-gap behavior

**Notes:** Discovered during codebase scouting that `lib/features/recovery/domain/training_suggestion.dart` already implements joint→muscle exclusion with a `0.5` weight threshold — reusing this avoids inventing a parallel injury model.

---

## Anchor Lift Guarantee Mechanism

| Option | Description | Selected |
|--------|-------------|----------|
| Specific exercise per main slot | Same exercise every week for load-continuity tracking | ✓ |
| Movement pattern per main slot | Rotation still allowed within the pattern | |

**User's choice:** Specific exercise per main slot

| Option | Description | Selected |
|--------|-------------|----------|
| Every main-role slot | Any SlotRole.main slot locks to its week-1 exercise | ✓ |
| Only one anchor per day | Only the single primary compound per day locks | |

**User's choice:** Every main-role slot

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, always overridable | Guarantee is against automatic rotation, not user intent | ✓ |
| No, anchors locked for the whole block | Cannot change even manually until block ends | |

**User's choice:** Yes, always overridable

| Option | Description | Selected |
|--------|-------------|----------|
| Safety breaks the lock | Injury hard filter always wins over the anchor guarantee | ✓ |
| Anchor lock wins, warn instead | Keep exercise, just show a warning | |

**User's choice:** Safety breaks the lock

**Notes:** Ties the three discussed areas together — the anchor mechanism is explicitly subordinate to the injury/pain hard filter and the no-safe-candidate flow, not a competing guarantee.

---

## Claude's Discretion

- Exact `ProgramGenerationRequest` field shapes for injury exclusion and anchor-lock bookkeeping.
- Empty-slot data representation (sentinel row vs. list omission keyed off `SelectionExplanation`).
- Migration path for the existing unused `ProgramGenerationRequest` vs. `SmartProgramConfiguration`.
- `SelectionExplanation` schema/persistence depth.

## Deferred Ideas

- Selection rationale depth (persisting "why" for excluded/runner-up candidates, not just the chosen one) — user chose not to discuss this area in this session; left as planner discretion within PLAN-04's scope.
- Full migration of `SmartProgramConfiguration` call sites to `ProgramGenerationRequest` across the UI layer — noted as a research question for `/gsd:plan-phase 17`.
