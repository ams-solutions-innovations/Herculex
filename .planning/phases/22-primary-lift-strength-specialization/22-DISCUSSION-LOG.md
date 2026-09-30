# Phase 22: Primary Lift Strength Specialization - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-09-30
**Phase:** 22-primary-lift-strength-specialization
**Areas discussed:** Split flexibility, Maintenance volume floor, Timeline realism warning, Sticking-point exercises

---

## Split flexibility

| Question | Options | Selected |
|---|---|---|
| Should specialization support splits beyond Full Body? | Full-body only (current) / **Also Upper/Lower + PPL** / You decide | ✓ Also Upper/Lower + PPL |
| Should the anchor lift get a "top-up" appearance on non-matching days? | **No — only on matching days** / Yes — guarantee a minimum touch / Not applicable | ✓ No — only on matching days |
| Should enabling specialization always force a specific split, or respect the user's existing choice? | Keep forcing (current) / Respect user's existing split / **You decide** | ✓ You decide |
| Which lifts feel wrong under full-body-only? | None / Pull-up specialization / Upper-body lifts generally | No preference given |

**User's choice:** Support Full Body + Upper/Lower + PPL; no top-up; no per-lift exception.
**Notes:** The "You decide" on force-vs-respect-split was resolved by Claude and confirmed in a follow-up: keep the user's existing split/days if it's already one of the 3 supported types (Full Body, Upper/Lower, PPL), otherwise reset to the current Full Body/3-day/Linear default. The user did not object when this resolution was presented back to them at the end of the area (moved straight to "Next area").

---

## Maintenance volume floor

| Question | Options | Selected |
|---|---|---|
| Wire in the existing VolumeBands system? | Yes — wire VolumeBands in / Yes, simpler threshold / **You decide** | ✓ You decide |
| What happens if a muscle group falls below the floor? | Warning only / Blocking like Max Effort guardrails / **You decide** | ✓ You decide |
| Where should the check run? | At Create time only / Live preview / **Both** | ✓ Both |
| Which muscle groups need floor protection? | All 19 groups / Only realistically-affected / **You decide** | ✓ You decide |

**User's choice:** Both timing points confirmed directly. The three "You decide" items were resolved by Claude in a single follow-up question (wire real VolumeBands via `ProgramVolumeCalculator`; warning-only everywhere; scope = whatever muscles appear in the plan) and the user explicitly confirmed with "That's right, lock it in" rather than picking the alternative offered ("Make it blocking at Create time").
**Notes:** None further.

---

## Timeline realism warning

| Question | Options | Selected |
|---|---|---|
| Add a dedicated target-timeline field to the modal? | Yes — add a field / **No — keep auto-applying recommendedWeeks()** | ✓ No |
| What happens when the chosen timeline is shorter than recommended? | **Inline warning + auto-adjust** / Inline warning, keep user's number / Blocking | ✓ Inline warning + auto-adjust |
| Warning threshold? | Any shortfall / A meaningful margin (25%+) / **You decide** | ✓ You decide |
| Also flag an unrealistic kg increase independent of timeline? | Timeline only / **Also flag an unrealistic increase outright** | ✓ Also flag |

**User's choice (raw):** As given above, "No new field" + "warn on shorter timeline" initially read as contradictory — there's no timeline for the user to shorten if no field exists to enter one.
**Reconciliation:** Claude proposed the resolution that the warning reuses the *existing* Weeks picker (`dialogs.part.dart:_showLengthPicker`, values `[4,6,8,12,16,24]`) rather than a new field — the specialization modal still auto-sets `_weeks = recommendedWeeks()`, but if the user later reopens the general Weeks picker and picks something shorter, that triggers the warning. Presented back to the user as an explicit reconciliation question; confirmed "Yes, exactly that."
**Follow-up resolutions:** Threshold confirmed as "any shortfall" (justified by the picker's own coarse 2–8 week gaps between options — no trivial-difference case exists to nag over). Increase-realism check confirmed as needing its own experience-aware ceiling, not a reuse of `recommendedWeeks()`'s existing >15kg/>30kg tiering.

---

## Sticking-point exercises

| Question | Options | Selected |
|---|---|---|
| Bench press sticking-point → assistance mapping? | Chest→pause/chest, Lockout→triceps / **You decide** | ✓ You decide |
| Overhead press sticking-point → assistance mapping? | Bottom→strict press, Lockout→triceps / **You decide** | ✓ You decide |
| Pull-up dead-hang → assistance mapping? | Scapular control + grip/lat / **You decide** | ✓ You decide |
| Lock exact exercises now, or leave to planning? | **Principle is enough — planning fills in specifics** / I want to specify exact exercises now | ✓ Principle is enough |

**User's choice:** Delegated all exact exercise/pattern mappings to research/planning. Locked only the structural requirement: every lift must branch assistance by sticking point (matching squat/deadlift's existing shape) — no lift may keep one generic slot regardless of sticking point.
**Notes:** The final "detail level" question made the delegation explicit and intentional rather than assumed from three consecutive "You decide" answers alone.

---

## Claude's Discretion

- Split force-vs-respect resolution (Split flexibility) — resolved and confirmed.
- Volume-floor wiring approach, enforcement severity, and muscle-group scope (Maintenance volume floor) — resolved and confirmed as a batch.
- Timeline warning threshold exact value ("any shortfall") — resolved and confirmed.
- Unrealistic-increase ceiling's exact numeric threshold — left fully open for research/planning (not resolved in this discussion, only the "yes, build this check" decision was locked).
- Exact assistance-exercise mapping per lift × sticking-point combination (Sticking-point exercises) — explicitly and fully delegated to research/planning.
- Whether to auto-fill "current load" in the specialization modal from the app's existing estimated-1RM analytics (`one_rep_max.dart`, `analytics_repository.dart`) — surfaced by Claude during codebase scouting, never raised as a discussion question, not decided either way. Flagged in CONTEXT.md's canonical_refs for research/planning to assess.
- Dead code cleanup (`SquatSpecialization`/`SquatStickingPoint`) — announced in the phase intro as something Claude would fold in; no objection raised, treated as confirmed by silence plus general "no preference" tenor of the split-flexibility area.

## Deferred Ideas

None — discussion stayed within phase scope for all four areas.
