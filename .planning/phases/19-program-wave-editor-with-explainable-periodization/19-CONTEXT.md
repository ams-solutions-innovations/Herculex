# Phase 19: Program & Wave Editor with Explainable Periodization - Context

**Gathered:** 2026-09-16
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 19 turns the existing after-the-fact block viewer (`block_detail_view.dart`) into a real editor: a single active-week view with a Week dropdown and an Exercise-wave indicator strip (replacing today's scrollable all-weeks card list), plus per-exercise replacement with `thisWave`/`thisAndFutureWaves`/`entireBlock` scope — reusing the `ExerciseReplacementSheet` + `replaceProgramExerciseSlot` machinery that Phase 17/18 already built for the pre-commit review screen, but was never wired into the post-commit editor. It also expands the periodization guide (`program_method_guide_view.dart`, already built with card selection, Recommended pill, and `?` navigation from `block_builder_view.dart`) to show a literal 8-week example per model instead of today's 4-milestone abbreviation. It does not touch program generation logic (Phase 17, shipped), prescription/time-budget logic (Phase 18, shipped), or the active workout/calendar execution flow (Phase 20).

</domain>

<decisions>
## Implementation Decisions

### Editor Reuse vs Rebuild (EDIT-01, EDIT-02)
- **D-01:** `block_detail_view.dart` (currently 710 lines, already over CLAUDE.md's 600-line hand-written-file limit) is retrofitted into the Week/Wave editor rather than building a separate `program_editor_view.dart`. Its `_WeekCard`-per-week scrollable list is replaced with a Week dropdown showing one active week at a time, plus a wave indicator strip. Split the file with `part`/`part of` into a subfolder (per CLAUDE.md) as part of this work, keeping the public import path unchanged.
- **D-02:** The `ExerciseReplacementSheet` and its `_ScopeChoice` widget, currently defined inline in `program_review_view.dart`, are extracted into a shared presentation widget/sheet file. Both `program_review_view.dart` (pre-commit) and the retrofitted `block_detail_view.dart` (post-commit) import the same sheet — no duplicated scope-picker UI.
- **D-03:** The day-level "link a template" swap (the `swap_horiz`/`link` icon in `_DayRow`, which relinks a whole day to a different `WorkoutTemplateData`) stays available on every day regardless of whether it already has exercises — it is a different, coarser operation (replace the whole day's session) than the new per-exercise replacement sheet (replace one exercise within a day), and both coexist. Per-exercise replacement is the new, additional action for editing individual exercises once a day has them; it does not remove or hide the day-level link icon.

### Post-Commit Replacement Safety (EDIT-02, EDIT-03)
- **D-04:** When `replaceProgramExerciseSlot` is invoked from the post-commit editor (not just pre-commit review), the caller follows it with `rematerializeProgram(programId)` — the exact same pattern `block_detail_view.dart`'s existing day-level swap already uses. `replaceProgramExerciseSlot` itself continues to only touch the `ProgramDayExercises` blueprint and `rotationAssignments`; it does not need to change to satisfy EDIT-03. `rematerializeProgram`'s existing "from today forward" boundary is accepted as-is for EDIT-03 — no separate status-based (planned/moved) filtering is added in this phase.

### Week vs Wave Labeling (EDIT-01)
- **D-05:** The single "Exercise wave X of Y · Weeks A–B" label shown alongside "Week N of M" is computed from one anchor slot's `rotationAssignments`, not derived by merging all slots' wave boundaries. The anchor slot is the first `SlotRole.main` slot encountered in the week's own day/slot ordering (deterministic, matches the ordering Phase 17's anchor-lift-guarantee logic already walks). If a block has multiple `SlotRole.main` slots across different days (e.g. a Squat day and a Bench day), only the first one in iteration order drives the displayed wave label — other slots may rotate on different internal cycles without a separate UI indicator in this phase.

### Periodization Guide Depth (EDIT-04)
- **D-06:** `program_method_guide_view.dart`'s "Example block" section is expanded from today's 4 abbreviated milestone `ProgramMethodGuideWeek` entries per model to a literal one-row-per-week rendering for all 8 weeks, for every `PeriodizationModel` (linear, concurrent, block, maxEffort, none). Block periodization's phase transitions (accumulation → transmutation → realization) land on their real week numbers instead of being implied by gaps between milestone weeks 1/3/5/7.

### Claude's Discretion
- Exact Week-dropdown widget choice (`DropdownButton` vs a custom sheet/picker) and where the wave-strip visually sits relative to it — left to planning/UI work as long as EDIT-01's "Week N of M" + "Exercise wave X of Y · Weeks A–B" separation is met.
- Exact file/folder name for the `part`/`part of` split of `block_detail_view.dart` (D-01) and for the extracted shared replacement-sheet file (D-02).
- Whether `PeriodizationModel.none`'s guide (which today only shows 2 "Stable" milestone weeks, not tied to an 8-week block) also expands to 8 rows or keeps its shorter, non-periodized framing — left to planning, since "none" has no periodization phases to map onto week numbers.
- Exact wording/content for weeks that fall between today's existing milestone entries (e.g. Linear's currently-undescribed weeks 5–8, Block's weeks 2/4/6/8) — left to implementation as long as every week 1–8 has a row.


</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Milestone & Blueprint Specs
- `docs/training-programs-physique-gamification-plan-2026-09-10.md` §"Faza 4 — razložljiva periodizacija, rotation waves in program editor" (lines ~343-401) — Architecture blueprint, origin of EDIT-01–04, including the Week dropdown/wave strip/scope UX, `ProgramWeekEditorSnapshot`/`ProgramExerciseReplacementScope` repository contract, and acceptance criteria (`A,A,B,B` → `C,C,B,B` for `thisWave`, → `C,C,C,C` for `entireBlock`).
- `docs/training-programs-physique-gamification-plan-2026-09-10.md` §4.4 (lines ~173-179) — Week/Exercise wave/Occurrence definitions that must stay domain- and visually-separate per D-05.
- `.planning/REQUIREMENTS.md` (EDIT-01–04) — Authoritative requirements for Phase 19.
- `.planning/ROADMAP.md` (Phase 19) — Milestone phase goal and success criteria.

### Prior Phase Context
- `.planning/phases/17-deterministic-program-planner-hard-guardrails/17-CONTEXT.md` D-09–D-12 — Anchor-lift guarantee mechanism (`SlotRole.main`, per-slot not per-day) that D-05 here reuses for wave-label anchoring, and D-11 which already named Phase 19's `thisWave`/`thisAndFutureWaves`/`entireBlock` scopes as the deliberate-override path for anchors.
- `.planning/phases/18-workout-time-budget-warmups-set-method-prescriptions/18-CONTEXT.md` D-03 — Confirms Phase 18 deliberately left `block_builder_view.dart`/editor storage untouched, expecting Phase 19 to wire the real editor UI to the codec.

### Program Editor & Replacement Domain
- `lib/features/programs/data/programs_repository.dart` — `ProgramExerciseReplacementScope` enum (line ~41) and `replaceProgramExerciseSlot` (lines ~883-1040) — the already-built repository contract for EDIT-02, currently only called from `program_review_view.dart`. Also `rematerializeProgram` (used by day-level swap, referenced by D-04) and `setWeekAdjustment`/`addProgramDay`/`deleteProgramDay`/`setProgramDayTemplate` — existing per-week/per-day mutation methods `block_detail_view.dart` already uses.
- `lib/features/programs/presentation/views/program_review_view.dart` (lines ~236-242, ~698-910) — `ExerciseReplacementSheet`, `_ScopeChoice`, and the scope-selection UI/copy ("This wave" recommended, "This and future waves", "Entire block") to extract per D-02.
- `lib/features/programs/presentation/views/block_detail_view.dart` — Current all-weeks card-list view (`_WeekCard`, `_DayRow`) being retrofitted per D-01; already 710 lines (over CLAUDE.md's 600-line limit) before this phase's additions.
- `lib/features/programs/data/database` rotation/assignment tables (`rotationAssignments`, `programExerciseSlots`, `programSlotPoolMembers`) — source of per-slot wave boundaries consumed by D-05's anchor-slot computation.

### Periodization Guide
- `lib/features/programs/presentation/views/program_method_guide_view.dart` — Already-built guide view/`ProgramMethodGuide.forModel` data being expanded per D-06; currently defines `bestFor`/`how`/`rotation`/`weeks` per `PeriodizationModel`.
- `lib/features/programs/presentation/views/block_builder_view.dart` (lines ~940-965, ~2951-3015) — Periodization card selection, `_RecommendedPill`, and existing `?` → `ProgramMethodGuideView.show(context, model)` navigation; no changes expected here beyond whatever the guide's data shape requires.
- `lib/features/programs/domain/periodization.dart` — `PeriodizationModel` enum and `Periodization.isPlannedDeload`, the block-phase/deload logic the expanded 8-week guide content should stay consistent with.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `ExerciseReplacementSheet` + `ProgramExerciseReplacementScope` + `replaceProgramExerciseSlot`: Fully built and working for the pre-commit review flow (`program_review_view.dart`) — this phase's core EDIT-02 work is extraction/reuse, not net-new design.
- `program_method_guide_view.dart`: Fully built guide shell (cards, sections, navigation) — EDIT-04's work is expanding the `weeks` data per model, not building new UI chrome.
- `SlotRole.main` (Phase 17): Already the exact predicate used for anchor-lift protection; D-05 reuses it again for wave-label anchoring rather than inventing a new "primary slot" concept.

### Established Patterns
- `block_detail_view.dart`'s existing day-level mutations (`_link`, `_remove`, `_addDay`) all follow "repository write → `rematerializeProgram(program.id)`" — D-04 extends this exact pattern to post-commit exercise replacement rather than introducing a different propagation mechanism.
- CLAUDE.md's `part`/`part of` split-when-over-600-lines convention, already applied precedent-wise across the codebase (51 files currently over limit) — D-01 follows this rather than a full multi-file rewrite.

### Integration Points
- `block_detail_view.dart`'s `_WeekCard` per-week rendering is the exact insertion point for the Week-dropdown/single-active-week change (D-01) and the wave-strip (D-05).
- `_DayRow`'s exercise-summary list (`programDayExerciseSummariesProvider`) is where the new per-exercise replacement trigger (a tap target or icon per exercise row) gets added, alongside the existing day-level link icon (D-03).

</code_context>

<specifics>
## Specific Ideas

- Blueprint's worked example for scope semantics: rotation pattern `A,A,B,B` across 4 weeks, replacing week 2's exercise with scope `This wave` → `C,C,B,B` (only the contiguous wave containing week 2 changes); scope `Entire block` → `C,C,C,C` (every week changes). This matches `replaceProgramExerciseSlot`'s existing wave-boundary-walk logic (`waveStart`/`waveEnd` contiguous-run detection) already implemented in `programs_repository.dart`.
- UI must separately display "Week 2 of 8" and "Exercise wave 1 of 4 · Weeks 1–2" as two distinct labels, never merged into one.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 19-program-wave-editor-with-explainable-periodization*
*Context gathered: 2026-09-16*
