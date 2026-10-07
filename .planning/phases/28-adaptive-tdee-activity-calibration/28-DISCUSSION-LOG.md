# Phase 28: Adaptive TDEE & Activity Calibration - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-09-28
**Phase:** 28-adaptive-tdee-activity-calibration
**Areas discussed:** Adherence threshold, Estimate visibility, Material-shift handling, Onboarding activity picker

---

## Adherence threshold

| Option | Description | Selected |
|--------|-------------|----------|
| Food diary only | A day counts if food was logged; weight trend computed separately from whatever weight logs exist. | |
| Food diary AND bodyweight same day | Stricter same-day requirement for both. | |
| Food diary + any bodyweight logs in window | Two separate gates: enough food-logged days, enough weight logs somewhere in the window. | ✓ |

**User's choice:** Food diary + any bodyweight logs in window
**Notes:** —

| Option | Description | Selected |
|--------|-------------|----------|
| ~70% of window days | e.g. 10 of last 14 days. | ✓ |
| ~50% of window days | e.g. 7 of last 14 days, more permissive. | |
| You decide | Claude picks during planning/research, informed by comparable apps. | |

**User's choice:** ~70% of window days

| Option | Description | Selected |
|--------|-------------|----------|
| Sustained crossing required | Adherence must stay above/below the bar for several consecutive days before the method switches. | ✓ |
| Immediate switch on threshold cross | No dwell time. | |
| You decide | Claude picks the exact mechanism during planning. | |

**User's choice:** Sustained crossing required

| Option | Description | Selected |
|--------|-------------|----------|
| Grace period, then fallback | Hold last observed estimate (labelled stale) for a grace window before falling back to classifier. | ✓ |
| Fall back immediately | Next recalibration after adherence drops uses the classifier right away. | |

**User's choice:** Grace period, then fallback

---

## Estimate visibility

| Option | Description | Selected |
|--------|-------------|----------|
| Inline badge + tap-through detail | Small label next to "Maintenance calories" expanding into a detail sheet. | ✓ |
| Always-expanded detail card | Full breakdown always visible inline. | |
| Separate dedicated screen | New screen off the main nutrition flow. | |

**User's choice:** Inline badge + tap-through detail

| Option | Description | Selected |
|--------|-------------|----------|
| Individually visible | Show actual HealthSamples inputs (steps, workouts, etc.). | ✓ |
| Confidence label only | Just show a confidence label, no breakdown. | |

**User's choice:** Individually visible

| Option | Description | Selected |
|--------|-------------|----------|
| Show both, side by side | Saved manual target and live estimate shown together. | ✓ |
| Estimate only | Detail sheet shows only the live estimate. | |

**User's choice:** Show both, side by side

| Option | Description | Selected |
|--------|-------------|----------|
| "Calibrating" state | Badge shows a calibrating label; Mifflin-St Jeor + onboarding activity level used as seed. | ✓ |
| Hidden until first estimate lands | No badge at all until real data exists. | |

**User's choice:** "Calibrating" state

---

## Material-shift handling

| Option | Description | Selected |
|--------|-------------|----------|
| Whichever is bigger: ±100 kcal or ±5% | Floor-plus-percentage rule. | ✓ |
| Flat ±100 kcal | Simple absolute threshold. | |
| Flat ±5% of current baseline | Simple relative threshold. | |

**User's choice:** Whichever is bigger: ±100 kcal or ±5%

| Option | Description | Selected |
|--------|-------------|----------|
| Explicit accept/dismiss prompt | "Update my target to X" / "Keep current target." | ✓ |
| Pure information, no action | States the drift happened, no in-report action. | |

**User's choice:** Explicit accept/dismiss prompt

| Option | Description | Selected |
|--------|-------------|----------|
| Phase 28 persists estimate history only | Phase 29 diffs the history itself to find material shifts. | ✓ |
| Phase 28 also emits explicit shift events | A distinct "shift detected" record written by Phase 28. | |

**User's choice:** Phase 28 persists estimate history only
**Notes:** Raised because Phase 29 (Weekly Report) doesn't exist yet — this fixes the Phase 28/29 scope boundary so Phase 28 doesn't design a queue/event shape for a screen that isn't built.

---

## Onboarding activity picker

| Option | Description | Selected |
|--------|-------------|----------|
| Reframe it as a starting estimate | Update onboarding copy to set expectations it will be refined automatically. | ✓ |
| Leave the onboarding question unchanged | Keep existing wording as-is. | |

**User's choice:** Reframe it as a starting estimate

| Option | Description | Selected |
|--------|-------------|----------|
| Keep it, relabeled as a manual reset | Picker stays in Profile; changing it re-seeds the estimate. | ✓ |
| Remove it from Profile once calibrated | Picker disappears once real data exists. | |

**User's choice:** Keep it, relabeled as a manual reset

| Option | Description | Selected |
|--------|-------------|----------|
| Reseed only, keep history | New pick becomes the classifier seed; past estimate history untouched. | ✓ |
| Full reset — discard estimate history | Wipes prior estimates, starts over. | |

**User's choice:** Reseed only, keep history

| Option | Description | Selected |
|--------|-------------|----------|
| No — observed-expenditure stays active if adherence still qualifies | Reset only affects the classifier seed; doesn't force method change. | ✓ |
| Yes — reset always drops back to Calibrating | Any manual change forces full re-seed regardless of current method. | |

**User's choice:** No — observed-expenditure stays active if adherence still qualifies

---

## Claude's Discretion

- Exact calibration window length and re-calibration cadence mechanics (TDEE-03).
- Exact bodyweight-log count required within the window for the weight-adherence gate.
- Exact hysteresis/dwell mechanism for method switching.
- Exact grace-period length before falling back from observed to classified.
- Weight-trend smoothing method (EWMA vs. moving average vs. other).
- Exact activity-classifier output shape (existing 4-tier `ActivityLevel` enum vs. continuous
  multiplier).
- Exact TDEE-estimate-history table schema (columns, indexing) beyond method/confidence/
  window/kcal/timestamp.

## Deferred Ideas

- The weekly-report UI/screen rendering the material-shift accept/dismiss prompt — entirely
  Phase 29's job; Phase 28 only persists the estimate history Phase 29 will diff.
- PHYS-04 (underage/low-confidence deficit and surplus guardrails) applying to adaptive TDEE —
  noted as a cross-phase constraint from Phase 23 (not yet built); Phase 28 must not create a
  bypass around it, but implementing the gate itself is out of this phase's scope.
