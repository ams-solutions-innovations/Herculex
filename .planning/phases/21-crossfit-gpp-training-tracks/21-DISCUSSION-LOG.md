# Phase 21: CrossFit & GPP Training Tracks - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-09-16
**Phase:** 21-crossfit-gpp-training-tracks
**Areas discussed:** Session blueprint data model, Metcon structure — single move or circuit, GPP day shape in Full Body 2×+GPP, CrossFit level policy scope

---

## Session blueprint data model

| Option | Description | Selected |
|--------|-------------|----------|
| New segment table | Dedicated table ordering segments per day, each owning its own slot(s) | |
| Tag existing rows | Add a 'segment' enum column to existing ProgramDayExercises/slot rows | ✓ |
| You decide | Leave schema shape to research/planning | |

**User's choice:** Tag existing rows.

| Option | Description | Selected |
|--------|-------------|----------|
| Different, new logic | CrossFit warmup is general prep, distinct from WarmupResolver's %1RM ramp | ✓ |
| Reuse where applicable | Run WarmupResolver inside skill segment for loaded lifts, standalone warmup covers general prep on top | |
| You decide | Leave boundary to planning | |

**User's choice:** Different, new logic.

| Option | Description | Selected |
|--------|-------------|----------|
| Lightweight placeholder | Cooldown structurally present, no curated content needed yet | ✓ |
| Real prescribed content | Cooldown needs actual exercise/stretch selection logic now | |
| You decide | Leave depth to planning | |

**User's choice:** Lightweight placeholder.

| Option | Description | Selected |
|--------|-------------|----------|
| One segment, two flavors | Skill or strength is one segment, chosen by day/level | |
| Both segments possible | A day can carry both a skill segment and a separate strength segment | ✓ |
| You decide | Leave to research | |

**User's choice:** Both segments possible.

---

## Metcon structure — single move or circuit

| Option | Description | Selected |
|--------|-------------|----------|
| Multi-movement circuits | Real CrossFit metcons, likely extends WorkoutCircuitData/CircuitsRepository | ✓ |
| Single-exercise for now | Keeps current SetType.amrap/emom/forTime architecture, simpler | |
| You decide | Leave to research | |

**User's choice:** Multi-movement circuits.

| Option | Description | Selected |
|--------|-------------|----------|
| One cap on the circuit | Circuit as a whole carries format + time cap | |
| Per-movement set type | Each movement keeps its own SetType | |
| You decide | Leave exact schema split to planning | ✓ |

**User's choice:** You decide.

| Option | Description | Selected |
|--------|-------------|----------|
| Time cap = fixed duration | Estimator treats time cap as a hard fixed block | |
| Estimate below the cap | Estimate realistic completion time for For Time, fall back to cap | |
| You decide | Leave to planning/research | ✓ |

**User's choice:** You decide.

| Option | Description | Selected |
|--------|-------------|----------|
| Same mechanism as CrossFit metcons | GPP reuses circuit/time-cap structure | |
| Simpler, separate | GPP conditioning stays free-form, lighter-weight | |
| You decide | Leave to planning once metcon mechanism is designed | ✓ |

**User's choice:** You decide.

---

## GPP day shape in Full Body 2×+GPP

| Option | Description | Selected |
|--------|-------------|----------|
| Standalone 3rd day | Matches SplitType.fullBodyAbGpp's existing 3-slot definition | |
| Appended block | Shorter GPP addendum tacked onto Full Body A/B | |
| You decide | Blueprint itself leaves this open, "by agreement" | ✓ |

**User's choice:** You decide.
**Notes:** The blueprint text explicitly leaves this choice open ("GPP/conditioning day OR shorter GPP addition, by agreement") — user confirmed this stays open for planning rather than being pre-decided.

| Option | Description | Selected |
|--------|-------------|----------|
| Hard exclude DE archetype | GPP slots structurally blocked from Dynamic Effort/max-effort archetype | |
| Discipline-tag filtering only | Rely on 'gpp' tag pool naturally not containing heavy DE work | |
| You decide | Leave enforcement mechanism to planning/research | ✓ |

**User's choice:** You decide.

| Option | Description | Selected |
|--------|-------------|----------|
| Expand the gpp tag pool | Curate more 'gpp'-tagged exercises as content work this phase | |
| Draw from gpp + crossfit tags | Keep 4 curated + widen pool to include 'crossfit'-tagged conditioning moves | |
| You decide | Leave pool sizing/curation scope to research | ✓ |

**User's choice:** You decide.

---

## CrossFit level policy scope

| Option | Description | Selected |
|--------|-------------|----------|
| Already sufficient | Phase 16's prerequisite gating + scaling ladders already cover skill gating | |
| Needs CrossFit-specific extension | CrossFit combos need additional level-aware logic beyond single-movement prerequisites | |
| You decide | Leave gap assessment to research | ✓ |

**User's choice:** You decide.

**Which level-policy axes need an explicit decision now vs. left to research/planning?** (multi-select)
- Time caps per level — selected
- Combo/complexity limits — selected
- Recovery reserve — selected

**User's choice:** All three axes selected as needing an explicit decision (not "left to research/planning" as a free pass) — the follow-up questions below drilled into shape, and the user answered "you decide" on the specific mechanism for each while insisting all three must be addressed.

| Option | Description | Selected |
|--------|-------------|----------|
| Reuse Phase 16 scaling | Existing scaling groups already cover level-appropriate Olympic lift selection | |
| New complexity ladder needed | Chained Olympic complexes are a different axis than single-movement scaling | |
| You decide | Leave to research | ✓ |

**User's choice:** You decide.

**Follow-up: Time caps per level — what shape?**
| Option | Description | Selected |
|--------|-------------|----------|
| Level→multiplier on format | Multiplier applied to base cap per format | |
| Fixed per-level cap table | Explicit fixed cap value per level+format combination | |
| You decide | Leave mechanism to planning | ✓ |

**User's choice:** You decide.

**Follow-up: Combo/complexity limits — what should cap chaining?**
| Option | Description | Selected |
|--------|-------------|----------|
| Movement-count ceiling per level | Simple count-based ceiling | |
| Movement-count + no fatigued-skill stacking | Count ceiling plus rule blocking barely-unlocked skill stacking | |
| You decide | Leave exact rule to planning/research | ✓ |

**User's choice:** You decide.

**Follow-up: Recovery reserve — new or tied into existing system?**
| Option | Description | Selected |
|--------|-------------|----------|
| New for Phase 21 — session spacing rule | Simple level-based minimum rest-day rule | |
| Tie into Hercul coaching engine | Reuse/extend Phase 13's recovery guidance | |
| You decide | Leave to research | ✓ |

**User's choice:** You decide.

---

## Claude's Discretion

- Naming for the new session-segment concept (must avoid colliding with the existing `WorkSegment` class name).
- Whether metcon time cap/format lives on the circuit as a whole or per movement.
- How a metcon's time cap flows into the Phase 18 time-budget estimator.
- Whether GPP conditioning reuses the metcon/circuit mechanism or stays simpler/separate.
- GPP day shape: standalone 3rd day vs. appended block (blueprint leaves this explicitly open).
- Enforcement mechanism preventing GPP from becoming a 3rd Dynamic Effort day.
- Whether to expand the `gpp` exercise tag pool or widen eligibility to `crossfit`-tagged exercises.
- Whether skill-movement gating needs CrossFit-specific extension beyond Phase 16's existing gate.
- Exact shape of time caps per level, combo/complexity limits, and recovery reserve (all three must be explicitly decided — not skipped).
- Whether Olympic lift complexes need a new complexity ladder beyond Phase 16's scaling groups.

## Deferred Ideas

None — discussion stayed within phase scope.
