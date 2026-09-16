# Phase 19: Program & Wave Editor with Explainable Periodization - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-09-16
**Phase:** 19-program-wave-editor-with-explainable-periodization
**Areas discussed:** Editor reuse vs rebuild, Post-commit replacement safety, Week vs Wave labeling, Periodization guide depth

---

## Editor reuse vs rebuild

| Option | Description | Selected |
|--------|-------------|----------|
| Retrofit block_detail_view.dart | Replace its week-card-list body with the Week dropdown + Wave strip, wire the existing ExerciseReplacementSheet into it | ✓ |
| New program_editor_view.dart | Build a dedicated editor route; demote/fold block_detail_view.dart | |

**User's choice:** Retrofit `block_detail_view.dart`.
**Notes:** File is already 710 lines (over CLAUDE.md's 600-line limit) — split via `part`/`part of` as part of the work.

| Option | Description | Selected |
|--------|-------------|----------|
| Extract shared widget; keep both swap actions | Move ExerciseReplacementSheet out to a shared file; day-level template swap and per-exercise replacement both stay, as different operations | |
| Extract shared widget; per-exercise replacement supersedes day swap | Same extraction, but remove/hide day-level swap icon once per-exercise replacement exists | ✓ (initial) |

**User's choice:** Initially "per-exercise replacement supersedes," refined below.
**Notes:** Followed up with an empty-day edge case.

| Option | Description | Selected |
|--------|-------------|----------|
| Keep 'link a template' for empty days only | Day-level link icon shows only when day has no template/exercises yet | |
| Keep 'link a template' always available | Day-level relink stays available even on populated days, in addition to per-exercise replacement | ✓ |

**User's choice:** Keep 'link a template' always available — both operations coexist regardless of day state (net decision recorded as D-03 in CONTEXT.md).

---

## Post-commit replacement safety

| Option | Description | Selected |
|--------|-------------|----------|
| Call rematerializeProgram after replacement | Reuse the exact pattern the day-level swap already uses | ✓ |
| Key rematerialization off session status, not date | Explicit status-based filtering instead of the existing date-based "today forward" cutoff | |

**User's choice:** Call `rematerializeProgram` after replacement, reusing the existing pattern as-is.
**Notes:** No separate status-based filtering added in this phase — existing "today forward" boundary accepted.

---

## Week vs Wave labeling

| Option | Description | Selected |
|--------|-------------|----------|
| Anchor it to the main lift's slot | Compute wave label from the SlotRole.main slot's rotationAssignments | ✓ |
| Show the most common wave boundary across all slots | Take whichever boundary set the plurality of slots share | |

**User's choice:** Anchor to the main lift's slot.

| Option | Description | Selected |
|--------|-------------|----------|
| First main slot encountered in week order | Deterministic pick when multiple SlotRole.main slots exist across different days | ✓ |
| Show one wave label per distinct main slot | Multiple wave chips instead of collapsing to one number | |

**User's choice:** First main slot encountered in week order.

---

## Periodization guide depth

| Option | Description | Selected |
|--------|-------------|----------|
| Expand to all 8 weeks, one row per week | Render one ListTile per week 1-8 for every model | ✓ |
| Keep abbreviated milestones, relabel as illustrative | Keep the existing 4-milestone cards, just clarify copy | |

**User's choice:** Expand to all 8 weeks, one row per week.

---

## Claude's Discretion

- Week-dropdown widget choice and wave-strip placement relative to it.
- File/folder naming for the `part`/`part of` split of `block_detail_view.dart` and the extracted shared replacement-sheet file.
- Whether `PeriodizationModel.none`'s guide (non-periodized, currently 2 milestone weeks) also expands to 8 rows or keeps its shorter framing.
- Exact wording/content for guide weeks that fall between today's existing milestone entries.

## Deferred Ideas

None — discussion stayed within phase scope.
