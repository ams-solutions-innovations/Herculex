# Phase 18: Workout Time Budget, Warmups & Set Method Prescriptions - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-09-15
**Phase:** 18-workout-time-budget-warmups-set-method-prescriptions
**Areas discussed:** Codec migration scope, Duration estimator behavior, Warmup scaling formula, Intensity technique gating

---

## Codec Migration Scope

| Option | Description | Selected |
|--------|-------------|----------|
| Show full detail | Preview renders set-by-set prescription via the new codec | ✓ |
| Keep summary only | Preview stays name/time only, detail deferred to Phase 19 | |

**User's choice:** Show full detail (Recommended)

| Option | Description | Selected |
|--------|-------------|----------|
| Leave editor untouched | block_builder_view.dart keeps generating via SmartProgramPlanner as today | ✓ |
| Migrate editor storage now | Convert editor's ad-hoc prescriptionJson writes to the new codec now | |

**User's choice:** Leave editor untouched (Recommended)

| Option | Description | Selected |
|--------|-------------|----------|
| New DB column, source of truth | Codec defines canonical stored encoding | ✓ |
| In-memory layer only | DB columns unchanged, codec only at read boundary | |

**User's choice:** New DB column, source of truth (Recommended)

| Option | Description | Selected |
|--------|-------------|----------|
| No live data to migrate | Pre-ship milestone, safe to change stored shape outright | ✓ |
| Codec reads legacy shape, writes new shape | Dual-read backward compatibility | |

**User's choice:** No live data to migrate

**Notes:** Preview/editor currently don't consume `SlotPrescription` at all — only the workout session does. This phase introduces the shared model rather than fixing drift between three existing consumers.

---

## Duration Estimator Behavior

| Option | Description | Selected |
|--------|-------------|----------|
| Feeds back into generation | Estimator actively trims/pads volume to fit workoutDurationMinutes | ✓ |
| Read-only estimate | Estimator only reports; generation unchanged | |

**User's choice:** Feeds back into generation (Recommended)

| Option | Description | Selected |
|--------|-------------|----------|
| All of it | Warmups, unilateral 2x, transitions, rest-pause/myo mini-sets all itemized | ✓ |
| Core work sets only | Flat overhead buffer for everything else | |

**User's choice:** All of it (Recommended)

| Option | Description | Selected |
|--------|-------------|----------|
| Accessories/isolation first | Protect main/supplemental anchor lifts from trimming | ✓ |
| Proportional trim | Reduce set counts proportionally across all slots | |

**User's choice:** Accessories/isolation first (Recommended)

---

## Warmup Scaling Formula

| Option | Description | Selected |
|--------|-------------|----------|
| More steps as intensity rises | Denser ramp progression for higher %1RM targets | ✓ |
| Fixed step count, scaled percentages | Always 3 steps, values scaled relative to target | |

**User's choice:** More steps as intensity rises (Recommended)

| Option | Description | Selected |
|--------|-------------|----------|
| Later exercises get reduced warmup | Movement order reduces ramp for later main/supplemental lifts | ✓ |
| Every exercise warms up independently | Order doesn't affect warmup scaling | |

**User's choice:** Later exercises get reduced warmup (Recommended)

| Option | Description | Selected |
|--------|-------------|----------|
| Replace entirely | WarmupResolver becomes the single source of warmup logic | ✓ |
| Parameterize existing tables | Keep fixed-table structure, make values configurable | |

**User's choice:** Replace entirely (Recommended)

---

## Intensity Technique Gating

| Option | Description | Selected |
|--------|-------------|----------|
| Global program-level toggle | Extend existing allowTimeSavingSetTechniques switch | ✓ |
| Per-set toggle | Keep free choice per set with one-time confirmation | |

**User's choice:** Global program-level toggle (Recommended)

| Option | Description | Selected |
|--------|-------------|----------|
| SlotRole.main only | Bar covers only the primary lift slot | ✓ |
| SlotRole.isHeavy (main + supplemental) | Broader bar covering both roles | |

**User's choice:** SlotRole.main only (Recommended)

| Option | Description | Selected |
|--------|-------------|----------|
| Hide the options entirely | No advanced technique options shown for barred lifts | ✓ |
| Show but block with explanation | Options visible but disabled with inline message | |

**User's choice:** Hide the options entirely (Recommended)

---

## Claude's Discretion

- Exact `SlotPrescriptionCodec` JSON schema/version field naming and field mapping from `SlotPrescription`/`WorkSegment`.
- Exact ramp-step-count-by-intensity thresholds and "abbreviated ramp" definition for later exercises.
- Exact trim algorithm/ordering within accessory/isolation slots when multiple exist.
- Migration path detail for the new DB column (column name, `SlotPrescription` restructuring, `PrescriptionResolver` changes).

## Deferred Ideas

None — discussion stayed within phase scope.
