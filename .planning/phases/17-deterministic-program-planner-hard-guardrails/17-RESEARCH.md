# Phase 17: Deterministic Program Planner & Hard Guardrails - Research

**Researched:** 2026-09-13
**Domain:** Internal Dart/Flutter domain logic (deterministic program generation, no new external packages)
**Confidence:** HIGH (codebase-verified; no external library research required)

## Summary

Phase 17 is a pure refactor/hardening of existing Dart domain code in
`lib/features/programs/`. There is no new package to evaluate — every finding here comes from
reading the actual implementation, not from Context7/WebSearch, so confidence is HIGH throughout
except where explicitly marked `[ASSUMED]`.

The single biggest fact this research surfaces, not visible from the phase description alone: **the
existing planner does not gracefully handle a hard-filter-exhausted slot today — it throws
`StateError` and aborts the entire `populate()` transaction** (`smart_program_planner.dart:465-469`
and `:471-475`). D-01's "leave the slot empty with an explanation" requirement is not an additive
feature next to current behavior; it is a replacement of a crash path with a recoverable one, and
every existing max-effort/pool-size guard that currently throws needs the same treatment or an
explicit decision to keep throwing for non-hard-filter conditions.

The second major fact: **`ExerciseScorer.rank` (a separate, currently-used class,
`lib/features/programs/domain/exercise_scorer.dart`) already has a `Relaxation` ladder that includes
`Relaxation.equipment` (silently drops the equipment hard filter) and a final `Relaxation.anchor`
fallback that returns `pool.first` even if every candidate was rejected for `blacklisted` or
`roleIneligible`.** This is a direct architectural conflict with D-02 ("never relax the 5 named hard
filters"). In the current call path from `smart_program_planner.dart` this is *functionally* inert
for equipment specifically, because equipment is already hard-filtered out of `candidates` before
`ScorerCandidate.equipmentAvailable: true` is hardcoded (line 424) — but the dead code path still
exists in a shared, reusable scorer class and must not be allowed to activate once the new hard
filters (especially injury/pain) start flowing into `ScorerCandidate`. Recommendation: keep
injury/pain and all 5 named hard filters entirely at the *candidate-pool-construction* stage
(`_createStableSlots`), never inside `ExerciseScorer`, so the scorer's `Relaxation` ladder — which
this phase does not own or need to touch — cannot silently undo them.

The third major fact: **injury/pain data (`JointModel.influencingMuscles`) is keyed by Title-Case
muscle names (`'Chest'`, `'Triceps'`, `'Front Delts'`, `'Rear Delts'`, `'Shoulders'`, …) and this
matches `ExerciseCatalog.primaryMuscle`'s stored format exactly** (verified against
`lib/data/local/seed_data.dart`, e.g. `primaryMuscle: 'Chest'`). This is a clean, direct join — no
new normalization/mapping layer is needed, unlike the planner's own `_canonicalMuscleId` which
lowercases/snake_cases for a *different* purpose (weekly set-cap bucketing). Do not reuse
`_canonicalMuscleId` for injury matching — match `exercise.primaryMuscle` directly against
`JointModel.influencingMuscles[joint].keys`.

The fourth major fact: **`ProgramDayExercises.exerciseId` is a non-nullable foreign key
(`onDelete: KeyAction.restrict`)** — a literal null-exercise sentinel row is not possible without a
schema migration to make the column nullable (and adjusting the FK action). This resolves Claude's
Discretion item #2 in favor of *not* writing a `ProgramDayExercises` row for an empty slot, and
instead persisting the explanation on a new table keyed by `(programId, slotKey, weekIndex)` — see
Architecture Patterns below. This *does* trigger CLAUDE.md's 5-chore schema-bump checklist.

**Primary recommendation:** Do the hard-filter/no-relax work entirely inside
`_createStableSlots`'s candidate construction (both the primary filter at lines 309-334 and the
fallback at lines 338-358), extend `ExerciseProgrammingEligibility.allows` with the injury/pain
check rather than adding a parallel gate, replace the `StateError` throws with a per-slot
"no safe candidate" result object, add a new `ProgramSlotExplanations` drift table (schema v42) for
persistence, and converge `SmartProgramConfiguration` and `ProgramGenerationRequest` by adding the
missing fields (`excludedMuscles`/`flaggedJoints`, `lockedAnchors`) to
`SmartProgramConfiguration` rather than migrating the single call site in `block_builder_view.dart`
to the unused class (see Architectural Responsibility Map and Don't Hand-Roll below for the
reasoning).

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**No-Safe-Candidate Behavior**
- D-01: When a slot's hard filters (injury/pain, equipment, style, experience, prerequisites) leave
  zero candidates, the slot is left empty (no `ProgramDayExercises` row, or a placeholder marker)
  rather than filled via any relaxation of those filters. A `SelectionExplanation` records why
  nothing qualified.
- D-02: The "never relax" guarantee applies strictly to the 5 named hard filters.
  Pattern/muscle targeting (`need.pattern`, `need.muscle`) is a soft placement preference and may
  still relax to fill a slot, exactly as `smart_program_planner.dart:335-358` does today — that
  fallback logic stays, scoped so it never crosses into equipment/injury/style/experience/
  prerequisite territory.
- D-03: Before declaring a slot truly empty, the planner consults Phase 16's
  `ExerciseScalingResolver` for a safer/easier regression on the same movement pattern. Only if the
  scaling resolver also returns null does the slot count as "no safe candidate."
- D-04: Empty slots are surfaced visibly in the program view with a short explanation (e.g. "No safe
  [pattern] movement available for your equipment/injuries") rather than being an invisible gap —
  this requires new UI in the program day view, in scope for Phase 17's user-facing surface even
  though the full editor lands in Phase 19.

**Injury/Pain as a Hard Filter**
- D-05: Injury/pain filtering reuses Recovery's existing `JointModel.influencingMuscles` (joint →
  weighted muscle map) rather than inventing a new movement-pattern-based mapping. This is the same
  mechanism that already drives muscle exclusions in `TrainingSuggestion`
  (`lib/features/recovery/domain/training_suggestion.dart`) — one source of truth shared between
  Recovery and program generation.
- D-06: Any flagged joint-pain severity (severity >= 1, per `JointPainStatus.isFlagged`) triggers a
  hard exclusion of exercises whose `primaryMuscle` is in that joint's influencing-muscle set (same
  `>= 0.5` weight threshold `TrainingSuggestion` already uses). This is not a soft scoring penalty —
  it's a full candidate-pool exclusion, matching the "no silently relaxed filters" principle.
- D-07: Injury/pain data flows into generation as an explicit field on `ProgramGenerationRequest`
  (e.g. `excludedMuscles` or `flaggedJoints`), computed once by the caller from
  `JointPainRepository.watchCurrentStatuses()` before generation starts. The planner itself does not
  query `JointPainRepository` live — this keeps `SmartProgramPlanner`/the deterministic scorer pure,
  deterministic, and unit-testable with fixed inputs.
- D-08: If joint-pain exclusion empties a slot, it gets the exact same visible-gap-with-explanation
  treatment as any other hard-filter exhaustion (D-01/D-04) — no special-cased fallback to an unsafe
  or off-pattern movement.

**Anchor Lift Guarantee Mechanism**
- D-09: An "anchor" is a specific exercise, not a movement pattern. Once week 1 selects an exercise
  (e.g. Back Squat) for a `SlotRole.main` slot, every subsequent week in the block reuses that same
  exercise — preserving load/1RM progression continuity — rather than allowing rotation to swap it
  for pattern variety.
- D-10: Anchor-lift protection applies to every slot with `SlotRole.main`, not just a single "primary
  lift of the day." This matches how `RotationPolicy` already special-cases `main`-role scoring today
  (`smart_program_planner.dart:392-400`).
- D-11: Anchors remain manually overridable at any point mid-block via the exercise replacement flow
  (Phase 19's `thisWave`/`thisAndFutureWaves`/`entireBlock` scopes, per EDIT-02). The Phase 17
  guarantee is only a defense against *automatic* rotation logic silently swapping the anchor — it
  must not fight deliberate user-driven replacement, even though the replacement UI itself ships in
  Phase 19.
- D-12: If a locked anchor exercise becomes injury-excluded mid-block (e.g. a new joint-pain flag
  appears after week 1), the safety hard filter wins and breaks the anchor lock — the slot
  re-resolves under the normal candidate/scaling-ladder/no-safe-candidate flow (D-01–D-03), it does
  not silently keep prescribing a now-unsafe anchor with just a warning.

### Claude's Discretion
- Exact `ProgramGenerationRequest` field names/shapes for `excludedMuscles`/`flaggedJoints` and the
  anchor-lock bookkeeping (e.g. a `lockedAnchors: Map<slotKey, exerciseId>` carried between week
  iterations in `populate()`). **Resolved below** — see Architecture Patterns.
- Whether the empty-slot placeholder is a null-exercise `ProgramDayExercises` row with a sentinel, or
  the day list simply renders fewer items keyed off `SelectionExplanation` records — left to
  planning/implementation, as long as D-04's visible-gap-with-explanation UX outcome is met.
  **Resolved below**: schema makes the sentinel-row option unavailable without a migration; a new
  `ProgramSlotExplanations` table plus "day list renders fewer items" is the concrete recommendation.
- Migration path for the existing unused `ProgramGenerationRequest` class in
  `programming_models.dart` vs. the currently-used `SmartProgramConfiguration` — planner/researcher
  to determine whether this phase fully replaces `SmartProgramConfiguration` call sites or adapts
  one into the other. **Resolved below** — see Architectural Responsibility Map.
- Exact `SelectionExplanation` schema/persistence (PLAN-04) — not deep-dived in this discussion;
  format and depth (chosen-only vs. chosen+excluded rationale) are left to planning, informed by
  D-01's requirement that at minimum the "why" for a no-safe-candidate slot must be captured.
  **Resolved below** — see Architecture Patterns.

### Deferred Ideas (OUT OF SCOPE)
- Selection rationale depth (whether to persist "why" for runner-up/excluded candidates, not just the
  chosen one, and whether this needs any Phase 17 UI vs. staying backend-only for Phase 19's editor to
  surface) — planner should default to capturing at minimum the no-safe-candidate rationale (D-01)
  and can treat richer per-candidate rationale persistence as a stretch goal within PLAN-04's scope,
  not a separate phase.
- Full migration of `SmartProgramConfiguration` call sites to `ProgramGenerationRequest` across the
  UI layer (block builder view, etc.) is noted as a research question, not decided here.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| PLAN-01 | Unified `ProgramGenerationRequest` acts as single authoritative entry point for all generation parameters. | Architectural Responsibility Map resolves the `SmartProgramConfiguration` vs. `ProgramGenerationRequest` question with a concrete convergence path (extend `SmartProgramConfiguration`, do not migrate the sole call site to the unused class — see rationale below). |
| PLAN-02 | Hard filters (injury/pain, equipment, style, experience, prerequisites) execute before scoring and are never relaxed to fill a slot. | Code Examples + Common Pitfalls document exactly where today's 2 candidate-filter passes and the `ExerciseScorer.Relaxation` ladder live, and which one the new injury/pain filter must extend. |
| PLAN-03 | Core anchor movements remain guaranteed across block weeks rather than rotating out on affinity scoring. | Architecture Patterns documents the `lockedAnchors` bookkeeping shape and its interaction with `RotationPolicy.epochFor` / `pool[epoch % pool.length]`. |
| PLAN-04 | Planner returns human-readable selection rationales (`SelectionExplanation`) for every chosen and excluded movement. | Architecture Patterns proposes the `ProgramSlotExplanations` table schema and notes the existing `prescriptionWhy` free-text precedent plus `ExerciseScorer.ScorerResult.excluded` as a reusable shape for the "excluded" half. |
</phase_requirements>

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Hard-filter candidate exclusion (injury/equipment/style/experience/prerequisites) | Domain (`exercise_programming_eligibility.dart`) | Data (`smart_program_planner.dart` calls it) | Single gate, already established by Phase 16; injury/pain extends it rather than adding a parallel path (avoids two sources of truth). |
| Injury/pain status computation from raw logs | Data/Domain (`JointPainRepository` + `JointModel`) | Application (caller of `populate()`) | `JointPainRepository.watchCurrentStatuses()` is a `Stream`; per D-07 it must be resolved to a plain `Map`/`Set` snapshot by the *caller* before generation, keeping the planner pure and synchronous-testable. |
| Anchor-lock bookkeeping across weeks | Data (`smart_program_planner.dart::populate`/`_createStableSlots`) | — | Anchors are chosen per-slot inside `_createStableSlots`, which already loops `weeks` to build `RotationAssignments`; the lock must live in that same loop, not be bolted on afterward. |
| No-safe-candidate detection + scaling-ladder consultation | Domain (`exercise_scaling_resolver.dart`, already exists) + Data (planner calls it) | — | `ExerciseScalingResolver.regress` is already a pure, DB-free domain service (Phase 16); the planner is the correct caller, one level up from where candidates are built. |
| `SelectionExplanation` persistence | Data (new drift table) | — | No existing table can hold a per-week, per-slot, exercise-may-be-null rationale row without a non-nullable-FK violation (see Common Pitfalls). |
| Empty-slot visible surface (D-04) | Presentation (program day view widget) | — | Small, additive UI change reading the new explanation rows; does not touch the Phase 19 full editor. |
| `ProgramGenerationRequest` vs `SmartProgramConfiguration` convergence | Domain (`programming_models.dart`) | Data (`smart_program_planner.dart`) | See rationale below — recommend extending `SmartProgramConfiguration`, not migrating the call site. |

**Convergence rationale (PLAN-01):** `ProgramGenerationRequest` is confirmed unused anywhere
outside `programming_models.dart` (`grep` found zero other references). `SmartProgramConfiguration`
has exactly **one** production call site
(`lib/features/programs/presentation/views/block_builder_view.dart:3268-3293`) plus test call sites
in `test/smart_program_planner_test.dart`. Given PLAN-01 requires "a single authoritative entry
point," and `SmartProgramConfiguration` is already that in practice (it is what `populate()`
actually consumes), the lowest-risk path that still satisfies PLAN-01 is:

1. Add the two missing fields to `SmartProgramConfiguration` (`excludedMuscles`/`flaggedJoints` per
   D-07, and nothing else — anchors are internal bookkeeping, not caller input).
2. Delete the unused `ProgramGenerationRequest` class from `programming_models.dart` (dead code that
   would otherwise silently diverge further from what's actually authoritative), *or* rename
   `SmartProgramConfiguration` to `ProgramGenerationRequest` in place if the planner wants the
   requirement's literal class name satisfied — a pure rename is a `git mv`-equivalent, mechanical,
   low-risk change touching exactly 3 files (`smart_program_planner.dart`, `block_builder_view.dart`,
   `smart_program_planner_test.dart`).
3. Do **not** attempt to make `ProgramGenerationRequest`'s existing shape (which has
   `split`/`daysPerWeek`/`scheduleMode`/`slotMethods`/`exercisePreferences` fields that
   `SmartProgramConfiguration` does not have and does not need, since those concerns are handled
   elsewhere by `ProgramsRepository.createProgramFromSplit`) the surviving class — it would require
   rewiring `populate()`'s entire signature and the split/day/week creation path that today is a
   separate, already-working concern (`createProgramFromSplit` builds the `programs`/`programWeeks`/
   `programDays` rows *before* `populate()` runs). That rewiring is out of Phase 17's stated boundary
   ("does not touch prescription/time-budget concerns... beyond leaving clean data").

This is the single largest scope decision in the phase; flag it explicitly for user/plan-check
confirmation even though it is presented here as a recommendation, since CONTEXT.md left it fully to
discretion.

## Standard Stack

Not applicable — Phase 17 introduces no new external package. All work is in existing
`package:herculex` Dart source and one new/extended drift table.

## Package Legitimacy Audit

Not applicable — no packages are installed or upgraded by this phase.

## Architecture Patterns

### System Architecture Diagram

```
JointPainRepository.watchCurrentStatuses()  (Stream<Map<String,JointPainStatus>>)
        │  (caller resolves current snapshot BEFORE generation — D-07)
        ▼
block_builder_view.dart
        │  builds SmartProgramConfiguration{ ..., excludedMuscles: {...} }
        ▼
SmartProgramPlanner.populate(programId, configuration)
        │
        ├─► for each week → for each day → _createStableSlots(...)
        │        │
        │        ├─► candidates = catalog.where(hard filters)      [PLAN-02, extends today's filter]
        │        │        equipment.allows()
        │        │        ExerciseProgrammingEligibility.allows()  ← + injury/pain check (D-05/D-06)
        │        │        ExerciseProgrammingEligibility.verifyPrerequisites()
        │        │        SlotRoleEligibility.allows()
        │        │
        │        ├─► if candidates.isEmpty:
        │        │        relax pattern/muscle ONLY (existing fallback, unchanged scope)  [D-02]
        │        │
        │        ├─► if STILL empty:
        │        │        ExerciseScalingResolver.regress(target, ...)                     [D-03]
        │        │            │
        │        │            ├─ success → candidate becomes the pool
        │        │            └─ noSafeCandidate → record SelectionExplanation, SKIP slot   [D-01/D-08]
        │        │                                  (no ProgramDayExercises row written)
        │        │
        │        ├─► if slot.role == SlotRole.main AND lockedAnchors[slotKey] exists:
        │        │        reuse locked exercise UNLESS it just failed the hard-filter gate above
        │        │        (D-12: safety wins, lock breaks, falls through to normal flow)   [D-09/D-10]
        │        │
        │        ├─► else (week 1 / first resolution): ExerciseScorer.rank(...) picks anchor
        │        │        lockedAnchors[slotKey] = anchor.exerciseId                        [D-09]
        │        │
        │        └─► write ProgramSlotExplanations row (chosen or empty)                    [PLAN-04]
        │
        ▼
ProgramDayExercises rows (only for filled slots) + ProgramSlotExplanations rows (every slot, every week)
        │
        ▼
Program day view (presentation) reads ProgramSlotExplanations for slots with no matching
ProgramDayExercises row and renders the "No safe [pattern] movement available..." message  [D-04]
```

### Recommended Project Structure

`smart_program_planner.dart` is already 1352 lines (over the 600-line hand-written-file limit per
CLAUDE.md) *before* this phase adds injury filtering, anchor-lock bookkeeping, and explanation
persistence. New logic should not be appended to the existing file. Split via `part`/`part of` into a
subfolder that keeps the public import path unchanged:

```
lib/features/programs/data/
├── smart_program_planner.dart          # part of; keeps public class, imports, populate() shell
└── smart_program_planner/
    ├── slot_candidate_resolution.part.dart   # part 'smart_program_planner.dart';
    │                                          #   candidate filtering + injury/pain + scaling-ladder
    │                                          #   consultation (replaces _createStableSlots body)
    ├── anchor_lock.part.dart                 # lockedAnchors bookkeeping, D-09–D-12 logic
    └── selection_explanation.part.dart       # builds + persists ProgramSlotExplanations rows
```

Reminder: **parts cannot have their own imports** — all imports stay in `smart_program_planner.dart`
itself, which is already the case for the file's current single-file form.

`lib/features/programs/domain/programming_models.dart` (350 lines) has headroom and does not need
splitting yet even after adding `excludedMuscles`/`flaggedJoints` fields and (if the rename path is
chosen) folding `ProgramGenerationRequest`'s surviving fields into `SmartProgramConfiguration`.

A new `lib/features/programs/domain/selection_explanation.dart` (pure Dart model, no Flutter import)
is recommended for the `SelectionExplanation` class itself, mirroring how `program_guardrails.dart`
and `exercise_scaling_resolver.dart` are each single-purpose domain files under 200 lines.

### Pattern 1: Extending the existing hard-filter gate (PLAN-02, D-05/D-06)

`ExerciseProgrammingEligibility.allows` is already the single, deliberately-fallback-free hard gate
(its own doc comment: *"It deliberately has no scoring or fallback behavior"*). Add the injury/pain
check as a new required parameter here, not as a separate call site, so there is exactly one place a
future maintainer looks for "why was this exercise excluded from auto-programming":

```dart
// Source: lib/features/programs/domain/exercise_programming_eligibility.dart (existing file, extend)
static bool allows({
  required ExperienceLevel experience,
  required TrainingStyle style,
  required String? difficulty,
  required String? commonness,
  required String? allowedTrainingStylesJson,
  required String? technicalEligibility,
  String? modality,
  String? requiredEquipmentKeysJson,
  // NEW (D-05/D-06/D-07):
  String? primaryMuscle,
  Set<String> excludedMuscles = const {},
}) {
  // ...existing checks unchanged...

  // Injury/pain hard exclusion (D-06): matches TrainingSuggestion's own
  // >= 0.5 influencing-muscle weight threshold, computed by the CALLER
  // (SmartProgramConfiguration.excludedMuscles) — this function stays pure
  // and takes the already-resolved exclusion set, mirroring how every other
  // parameter here is pre-resolved rather than queried live.
  if (primaryMuscle != null && excludedMuscles.contains(primaryMuscle)) {
    return false;
  }

  // ...rest unchanged...
}
```

The caller (`smart_program_planner.dart`) computes `excludedMuscles` **once per `populate()` call**
(not per-slot), exactly the way `_affinities`/`_equipment`/`_physiquePriorities` are already resolved
once at the top of `populate()`:

```dart
// Source: derived from JointModel.influencingMuscles (lib/features/recovery/domain/joint_model.dart)
// and TrainingSuggestionEngine's own _jointExclusionWeight = 0.5 precedent
// (lib/features/recovery/domain/training_suggestion.dart:76)
static const _jointExclusionWeight = 0.5;

Set<String> _excludedMusclesFrom(Map<String, JointPainStatus> statuses) => {
  for (final status in statuses.values)
    if (status.isFlagged)  // severity >= 1, per D-06
      for (final entry in (JointModel.influencingMuscles[status.joint] ?? const {}).entries)
        if (entry.value >= _jointExclusionWeight) entry.key,
};
```

Note this duplicates `TrainingSuggestionEngine`'s inline set-builder almost verbatim (lines 86-92 of
`training_suggestion.dart`). Consider extracting a shared
`JointModel.excludedMusclesFor(Map<String, JointPainStatus>, {double weightThreshold = 0.5})` helper
on `JointModel` itself so both call sites share one implementation — this satisfies D-05's "one
source of truth" spirit more literally than two independent copies of the same set-comprehension.

### Pattern 2: Anchor-lock bookkeeping (PLAN-03, D-09–D-12)

`_createStableSlots` already loops `weeks` once per slot to build `RotationAssignments`
(`smart_program_planner.dart:520-538`) using `pool[epoch % pool.length]`. Today this always applies
rotation math even to `SlotRole.main`, relying only on `RotationPolicy.everyWeeks == 0` (linear
model) to *happen* to keep the same exercise — Concurrent/Block/MaxEffort main slots can and do
rotate under today's code. The anchor lock must intercept this loop for `SlotRole.main`:

```dart
// Inside the `for (final week in weeks)` loop that builds RotationAssignments,
// AFTER computing `selected` via the existing epoch/pool logic:
if (need.role == SlotRole.main) {
  final locked = lockedAnchors[slotKey];
  if (locked == null) {
    // First week this slot is resolved this generation run — lock it.
    lockedAnchors[slotKey] = selected.candidate.exerciseId;
  } else if (candidatesStillAllow(locked)) {
    // D-12: only reuse the lock if it still survives THIS week's hard-filter
    // pass (injury exclusion may have newly removed it mid-block).
    selected = poolEntryFor(locked) ?? selected; // fall through to normal pick if lock now unsafe
  } else {
    // Lock broken by newly-flagged injury — do not re-lock to the old
    // exercise; whatever the normal flow picks this week becomes the new
    // lock for subsequent weeks (D-12).
    lockedAnchors[slotKey] = selected.candidate.exerciseId;
  }
}
```

`lockedAnchors: Map<String, int>` (slotKey → exerciseId) should be a **local variable inside
`_createStableSlots`**, not a field on `SmartProgramConfiguration` — it is generation-run-scoped
bookkeeping, not caller input, and CONTEXT.md's own phrasing ("carried between week iterations in
`populate()`") confirms this. It does not need to persist beyond one `populate()` call: on a
re-generation, `ProgramExerciseSlots`/`RotationAssignments` are deleted and rebuilt from scratch
(`_db.delete(_db.programDayExercises)` at line 179-181 confirms materialization is always a full
rebuild per day, not an incremental patch), so there is no cross-run state to persist for the lock
itself — only the *explanation* needs a table (see Pattern 3).

**Important:** `candidatesStillAllow(locked)` must re-run the *same* hard-filter predicate used to
build `candidates` for that week (equipment/style/experience/prerequisites/injury), not just injury
— an anchor could in principle also become equipment-invalid if this phase's `SmartProgramConfiguration`
is later reused for gym-switching mid-block (not in this phase's scope, but the check should be
written generically against "is this exerciseId still in this week's raw candidate pool" rather than
hardcoded to injury only, so it doesn't need revisiting later).

### Pattern 3: `ProgramSlotExplanations` table (PLAN-04)

No existing table can hold a nullable-exercise, per-week rationale row:
- `ProgramDayExercises.exerciseId` is `integer().references(ExerciseCatalog, #id, onDelete: KeyAction.restrict)()` — **not nullable**.
- `RotationAssignments.exerciseId` — same, not nullable, and its `{slotId, weekIndex}` unique key
  would collide with "no assignment this week" semantics.
- `ProgramExerciseSlots` is per-slot, not per-week — cannot represent "empty in week 3, filled in
  week 1" (relevant for D-12's mid-block breakage).

Add a new table (schema v42):

```dart
// New in lib/data/local/tables.dart
@DataClassName('ProgramSlotExplanationData')
class ProgramSlotExplanations extends Table with SyncColumns, SyncTombstone {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get slotId => integer().references(
    ProgramExerciseSlots,
    #id,
    onDelete: KeyAction.cascade,
  )();
  IntColumn get weekIndex => integer()();
  // Null when D-01's no-safe-candidate case fires this week.
  IntColumn get chosenExerciseId => integer().nullable().references(
    ExerciseCatalog,
    #id,
    onDelete: KeyAction.setNull,
  )();
  TextColumn get status => text()(); // 'filled' | 'empty'
  TextColumn get rationale => text()(); // human-readable "why", D-04's message text
  // Optional stretch (deferred per CONTEXT.md's Deferred Ideas): JSON list of
  // {exerciseId, reason} for excluded candidates, mirroring
  // ExerciseScorer.ScorerResult.excluded's Map<int, FilterReason> shape.
  TextColumn get excludedJson => text().nullable()();

  @override
  List<Set<Column>> get uniqueKeys => [
    {slotId, weekIndex},
  ];
}
```

This is a **new table**, so it triggers CLAUDE.md's 5-chore schema-bump checklist in full:
1. `schemaVersion` 41 → 42 in `lib/data/local/database.dart`, `onUpgrade` `if (from < 42)` branch
   creating the table (no `addColumn` guard needed — it's a whole new table, not a column add).
2. `dart run drift_dev schema dump lib/data/local/database.dart drift_schemas/`
3. `dart run drift_dev schema generate drift_schemas/ test/generated_migrations/`
4. Retarget `test/migration_test.dart` and any `test/schema_v41*.dart`-equivalent fixture.
5. **Supabase migration** — only required if this table needs to sync. Given it is fully derivable
   from re-running the planner (deterministic given the same inputs — a core theme of this whole
   phase), it is reasonable to scope it **local-only** (no `supabase/migrations/NNNN_*.sql`, no
   `SyncColumns`/outbox row) and skip chore 5 entirely. Flag this as a decision for the plan/
   plan-check step: local-only avoids sync-quarantine risk entirely (per CLAUDE.md's PGRST204
   warning) at the cost of explanations not surviving a fresh install until the program is
   regenerated. **Recommended:** local-only; the phase's own success criterion is "transparent
   selection explanations," not "explanations survive a reinstall," and Phase 25 (Cloud Sync
   Hardening) is the correct place to decide what of v2.0's new tables need sync at all.

Note also: migrations `0015` and `0016` are already written but **not applied** per CLAUDE.md's
"Gotchas" section — confirm with the user/STATE.md whether Phase 17's v42 migration should apply
after those two, and that local v37 mentioned there has since moved to v41 (current
`schemaVersion`), so that gotcha note is stale and should be treated as informational only, not as
a live blocker.

### Anti-Patterns to Avoid

- **Adding injury/pain filtering as a second, parallel gate function** instead of extending
  `ExerciseProgrammingEligibility.allows` — creates two places to keep in sync and violates D-05's
  "one source of truth" principle at the code level, not just the data level.
- **Letting `ExerciseScorer`'s `Relaxation.equipment`/`Relaxation.anchor` see excluded-by-injury
  candidates at all.** The scorer's `ScorerCandidate` list must only ever contain candidates that
  already passed all 5 hard filters — never pass a rejected-by-hard-filter candidate into
  `ExerciseScorer.rank` hoping its `blacklisted`/`equipmentMissing` rejection reasons will exclude it
  again; that path's `Relaxation.anchor` fallback can still return a rejected candidate as `pool.first`
  if literally nothing survives every relaxation tier.
- **Reusing `_canonicalMuscleId`'s lowercase/snake_case output to match against
  `JointModel.influencingMuscles` keys.** That function's job is weekly-set-cap bucketing
  (`'front_delts'`, `'side_delts'`) and does not round-trip cleanly back to
  `JointModel`'s Title-Case, space-separated keys (`'Front Delts'`). Match
  `exercise.primaryMuscle` directly, unmodified.
- **Throwing `StateError` for the D-01 no-safe-candidate case.** The existing `StateError` throws at
  lines 465-469 and 471-475 are for *different* invariant violations (empty pool after relaxation —
  today considered a bug/misconfiguration, and insufficient Max Effort pool variety) and should stay
  as throws. D-01's case is a *normal, expected* outcome (a gym legitimately has no safe movement for
  a slot) and must not throw — it must produce a `SelectionExplanation` and continue generating the
  rest of the program.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Joint → muscle exclusion mapping | A new movement-pattern-based injury taxonomy | `JointModel.influencingMuscles` (already exists, already validated by `TrainingSuggestion`) | D-05 explicitly locks this; a second mapping would drift from Recovery's over time. |
| Progressive regression / "try an easier variant first" | A new scaling/ladder traversal inside the planner | `ExerciseScalingResolver.regress` (Phase 16, already exists, already pure/testable) | It already implements exactly D-03's ordering (difficulty → technical eligibility → style/commonness/equipment → prerequisites) with an explainable rationale string. |
| "Why was this excluded" bookkeeping | A bespoke exclusion-reason enum for the planner | `FilterReason` from `exercise_scorer.dart` for the scored-candidate half; a new minimal `status`/`rationale` pair for the pre-scoring hard-filter half | Reinventing a second reason taxonomy for the same conceptual thing (why didn't X get picked) fragments PLAN-04's rationale story across two incompatible shapes. |
| Prerequisite/experience/style/commonness hard gating | New if-chains in the planner | `ExerciseProgrammingEligibility.allows` / `.verifyPrerequisites` (Phase 16) | Already the established, tested hard-gate entry point; extend, don't duplicate. |

**Key insight:** Phase 16 already built almost every domain primitive Phase 17 needs
(`ExerciseProgrammingEligibility`, `ExerciseScalingResolver`). The actual Phase 17 work is mostly
*wiring these into the planner's control flow correctly* and *not throwing on the way there* —
not inventing new domain logic.

## Common Pitfalls

### Pitfall 1: The current code path throws, it does not gracefully empty
**What goes wrong:** A developer adds the injury/pain filter to `_isEligibleForAutomaticProgramming`
(or the eligibility gate), tests it, and it works — until a real gym/injury combination empties a
slot's candidate pool entirely, at which point `ranked.isEmpty` at line 465 throws `StateError` and
the **entire program generation transaction fails**, not just that one slot. Because `populate()`
wraps everything in `_db.transaction(...)`, this can silently roll back a program the user was
otherwise happy with, with no indication of *which* slot caused it beyond the exception message.
**Why it happens:** the current `StateError` was written under the old assumption "never leave a
slot empty" (see the comment at line 336: *"Never leave a Smart slot empty"*) — a design goal Phase
17 explicitly reverses for the 5 hard filters.
**How to avoid:** the candidate-construction + scaling-resolver-consultation + explanation-recording
flow must return a per-slot result type (e.g. a sealed `_SlotResolution` with `.filled(...)` /
`.empty(...)` variants) *before* reaching `ExerciseScorer.rank`/the `ranked.isEmpty` throw, so the
throw is only ever reached for genuinely different failure modes (empty catalog entirely, pool below
Max Effort's minimum-3 requirement) that remain legitimate hard failures, not "user has a flagged
elbow and a basic-equipment gym."
**Warning signs:** any new test that expects `populate()` to complete successfully with one slot
missing from a day's `ProgramDayExercises` rows will fail loudly (transaction rollback / exception)
until this control-flow change is made.

### Pitfall 2: `used` (already-picked-exercise) set interacts with anchor locking
**What goes wrong:** `_createStableSlots` tracks a `used = <int>{}` set so the same exercise is not
picked twice across different slots *within one day* (line 277, 310, 339, 477). This set is rebuilt
fresh per day inside `_createStableSlots`, which is itself cached per `(dayLabel, stressRole)` key
(`slotCache`, line 160) and reused across all weeks that share that cache key. If anchor-locking
logic is added naively at the week-loop level (Pattern 2), it must not re-trigger `used`-set
collision logic per week — `used` is a same-day, cross-slot dedup concern, orthogonal to
per-week rotation, and should not be touched by the anchor-lock change at all. Keep the lock
strictly inside the week-indexed `RotationAssignments`-building loop (lines 520-538), not inside the
per-slot candidate/`used` loop (lines 279-477).
**Why it happens:** both concerns live in the same 250-line method, easy to conflate.
**How to avoid:** when splitting into `part` files (see Project Structure), keep the `used`-set
candidate resolution and the week-loop anchor-lock resolution in physically separate functions with
distinct signatures, so it's structurally hard to reach into the wrong one's state.

### Pitfall 3: `equipmentAvailable: true` is hardcoded when building `ScorerCandidate`
**What goes wrong:** Line 424 of `smart_program_planner.dart` always sets
`equipmentAvailable: true` on every `ScorerCandidate` passed to `ExerciseScorer.rank`, *because*
equipment was already hard-filtered out of `candidates` upstream. If a future maintainer adds
injury/pain as a `ScorerCandidate` field (mirroring how `equipmentAvailable` looks tempting to copy)
instead of filtering it out of `candidates` upstream (Pattern 1's recommended approach), they will
accidentally route injury/pain through `ExerciseScorer`'s `Relaxation` ladder, which — unlike the
upstream candidate filter — genuinely can relax past it (`Relaxation.equipment`/`Relaxation.anchor`
tiers, or worse, a *new* `Relaxation.injury` tier someone adds by analogy). This would violate
D-02/D-06 the moment the scorer's fallback ladder is exercised.
**Why it happens:** `ExerciseScorer` already has the exact shape (`bool equipmentAvailable`) that
looks like the natural place to add `bool injurySafe`. It is not, for hard filters.
**How to avoid:** injury/pain (like equipment, style, experience, prerequisites) must never reach
`ScorerCandidate` construction for a rejected exercise at all — it should already be absent from
`candidates` by the time the `scorerPool` list comprehension runs (line 401-426).

### Pitfall 4: `test/smart_program_planner_test.dart` loads the real exercise catalog from assets
**What goes wrong:** the existing test suite's `setUp` calls `ExerciseImporter.runFromJson` against
`assets/data/exercises.json` + `assets/data/exercise_programming_metadata.json` — real curated data,
not synthetic fixtures. New hard-filter tests for injury/pain need synthetic `JointPainStatus` /
`excludedMuscles` inputs layered on top of this real catalog, which means test assertions about
"slot X should be empty" need to pick a joint/muscle combination that is guaranteed to exhaust a
*specific* slot's candidates in the real curated catalog — fragile if the catalog changes. Prefer the
`exercise_scaling_resolver_test.dart` style (hand-built `ExerciseCatalogData` fixtures via a local
`_makeExercise` helper, no asset loading) for the new eligibility/hard-filter unit tests, and reserve
the real-catalog `smart_program_planner_test.dart` style only for the top-level "full program
generation still works end-to-end" integration tests.
**Warning signs:** a new test asserting on a specific empty slot that passes today but silently stops
testing anything meaningful after an unrelated catalog data update.

## Code Examples

### Existing hard-filter gate (extend this, don't duplicate)
```dart
// Source: lib/features/programs/domain/exercise_programming_eligibility.dart:16-84 (current)
static bool allows({
  required ExperienceLevel experience,
  required TrainingStyle style,
  required String? difficulty,
  required String? commonness,
  required String? allowedTrainingStylesJson,
  required String? technicalEligibility,
  String? modality,
  String? requiredEquipmentKeysJson,
}) {
  final resolvedDifficulty = _difficulty(difficulty);
  if (_difficultyRank(resolvedDifficulty) > _experienceRank(experience)) return false;
  // ... commonness / style / equipment-key checks ...
  final styles = _styles(allowedTrainingStylesJson);
  return styles.any(style.allowedCatalogStyles.contains);
}
```

### Existing "why" persistence precedent (chosen-only, already shipping)
```dart
// Source: lib/features/programs/data/smart_program_planner.dart:238-241 (current)
prescriptionWhy: Value(
  '${slot.why}${focusNote.message}${timePlan.why}',
),
```
This is free-text, chosen-only, and lives on `ProgramDayExercises` (which cannot represent "empty").
PLAN-04's `SelectionExplanation` supersedes this for the *slot-level* "why", but `prescriptionWhy`
itself is unrelated to slot selection (it's about method/target-adjustment reasoning) and should stay
as-is — do not conflate the two.

### Existing excluded-candidate shape to reuse for PLAN-04's stretch goal
```dart
// Source: lib/features/programs/domain/exercise_scorer.dart:194-213 (current)
class ScorerResult {
  final List<ScoredExercise> ranked;
  final Relaxation relaxation;
  final Map<int, FilterReason> excluded; // exerciseId -> why it never got scored
}
```

## State of the Art

Not applicable in the external-library sense — this is entirely internal code evolution. The
relevant "old approach → new approach" shift is internal to this codebase:

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|---------------|--------|
| "Never leave a slot empty" (comment at `smart_program_planner.dart:336`) — relax pattern/muscle *and implicitly accept whatever equipment/eligibility allows* | Hard filters (5 named) are absolute; only pattern/muscle relax; empty-with-explanation is a valid, expected outcome | Phase 17 (this phase) | Reverses a design assumption baked into the planner since its creation — every place that assumed "there's always an exercise" needs re-auditing (see Pitfall 1). |
| `StateError` on empty candidate pool | Per-slot `SelectionExplanation`, generation continues | Phase 17 | Changes `populate()`'s failure semantics from all-or-nothing to partial-success-with-visible-gaps. |

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `ProgramSlotExplanations` should be local-only (no Supabase sync) since it's fully re-derivable by regenerating the program. | Architecture Patterns, Pattern 3 | If wrong, explanations silently vanish after a fresh install/re-login until the program is next regenerated — low severity (cosmetic/explainability only, not data-loss), but should be confirmed with the user/plan-check rather than assumed silently. |
| A2 | The `git mv`-equivalent rename of `SmartProgramConfiguration` → keep-as-is vs. rename-to-`ProgramGenerationRequest` is a pure naming/discretion choice with no behavioral difference — recommend NOT renaming (keep `SmartProgramConfiguration`, delete the unused class) to minimize diff size, but either satisfies PLAN-01's literal requirement text depending on interpretation. | Architectural Responsibility Map | If the user/plan-check intends `ProgramGenerationRequest` to literally exist as the entry-point class name (e.g. for future Phase 19 editor code to reference), the rename path should be chosen instead — low risk either way, purely a naming decision, flagged here so planning makes it explicitly rather than by accident. |
| A3 | `JointModel.influencingMuscles`'s `'Shoulders'`-vs-`'Front/Side/Rear Delts'` key mismatch (the joint map only has `'Front Delts'`/`'Side Delts'`/`'Rear Delts'`, never bare `'Shoulders'`, while some catalog `primaryMuscle` values are `'Shoulders'`) means a small number of shoulder exercises will never match any joint exclusion even when the Shoulder joint is flagged. | Summary, Pattern 1 | If this is a real gap (not just a seed-data artifact), some shoulder-loading exercises could slip through a flagged-shoulder exclusion. Worth a quick catalog `primaryMuscle` value audit (`grep -o "primaryMuscle: '[^']*'" assets/data/exercises.json \| sort -u`) during planning/implementation to confirm the full set of distinct values used, not just the seed_data.dart sample checked here. |

**If this table is empty:** N/A — see rows above.

## Open Questions

1. **Should `ProgramSlotExplanations` sync to Supabase?**
   - What we know: no existing table shape fits; a new table is required regardless of sync scope.
   - What's unclear: whether Phase 25 (Cloud Sync Hardening) expects every v2.0 table to already have
     sync wired up, or whether staged/local-only-then-synced-later is acceptable.
   - Recommendation: default to local-only (see A1); explicitly re-visit in Phase 25 rather than
     guessing now.

2. **Does `_createStableSlots`'s per-day `slotCache` (keyed by `dayLabel|stressRole.id`, reused
   across all weeks) interact safely with anchor-locking?**
   - What we know: `slotCache` only affects *slot definition* reuse (same day label appearing twice
     in a split), not the per-week rotation-assignment loop where the anchor lock lives.
   - What's unclear: whether any split template repeats a `(dayLabel, stressRole)` pair such that two
     physically different days would incorrectly share one `lockedAnchors` entry through the cache.
   - Recommendation: during planning, trace one `SplitTemplates.generate` output for a repeating
     split (e.g. PPL with 6 days/week, `daysPerWeek >= 6` per `_stressRole`) to confirm `dayLabel`
     values are unique per physical day, not per label-type, before finalizing the `lockedAnchors`
     keying scheme (`slotKey` already includes `dayLabel`, which should already disambiguate this,
     but worth a concrete trace since the cache is the one part of the existing method the anchor
     lock must NOT disturb per Pitfall 2).

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | `flutter_test` (bundled with Flutter 3.44) |
| Config file | none — standard `flutter test` discovery of `test/**/*_test.dart` |
| Quick run command | `flutter test test/exercise_programming_eligibility_test.dart test/exercise_scaling_resolver_test.dart test/smart_program_planner_test.dart` |
| Full suite command | `flutter test > /tmp/test_output.txt 2>&1` (per CLAUDE.md: redirect, don't pipe to `tail`; use `tr '\r' '\n'` before grepping) |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| PLAN-01 | `SmartProgramConfiguration`/entry-point carries `excludedMuscles` and is consumed end-to-end by `populate()` | integration | `flutter test test/smart_program_planner_test.dart -x` | ✅ (extend existing file) |
| PLAN-02 | Injury/pain, equipment, style, experience, prerequisites never relax; pattern/muscle still relax | unit | `flutter test test/exercise_programming_eligibility_test.dart -x` | ✅ (extend existing file) |
| PLAN-02 | Zero-candidate slot does not throw, produces empty-slot result | integration | `flutter test test/smart_program_planner_test.dart -x` | ✅ (extend existing file, add new `test()` block) |
| PLAN-03 | Anchor exercise identical across all weeks of a block for `SlotRole.main` | integration | `flutter test test/smart_program_planner_test.dart -x` | ✅ (extend existing file) |
| PLAN-03 | Anchor lock breaks when injury-excluded mid-block (D-12) | integration | `flutter test test/smart_program_planner_test.dart -x` | ✅ (extend existing file) |
| PLAN-04 | `SelectionExplanation`/`ProgramSlotExplanations` row exists for every slot, every week, filled or empty | unit + integration | new `test/program_slot_explanations_test.dart` + extend `smart_program_planner_test.dart` | ❌ Wave 0 |
| PLAN-04 | Empty slot surfaces a human-readable message in the program day view | widget | new `test/features/programs/presentation/*_test.dart` | ❌ Wave 0 (only if D-04 UI is a distinct widget/file — depends on plan's task breakdown) |

### Sampling Rate
- **Per task commit:** the 3 targeted `flutter test test/exercise_programming_eligibility_test.dart test/exercise_scaling_resolver_test.dart test/smart_program_planner_test.dart` (fast, seconds)
- **Per wave merge:** `flutter test` full suite (per CLAUDE.md, ~2min, 1308 pass / 4 skipped baseline — expect this count to rise with new tests)
- **Phase gate:** Full suite green + `flutter analyze` 0 errors + `dart run tool/check_structure.dart` clean before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `test/program_slot_explanations_test.dart` — new file, covers PLAN-04's persistence shape
      (`ProgramSlotExplanationData` round-trip, `{slotId, weekIndex}` uniqueness)
- [ ] Migration fixtures for schema v42 (`test/generated_migrations/schema_v42.dart`-equivalent,
      generated via `drift_dev schema generate`, not hand-written) — covers the new table's
      `onUpgrade` path
- [ ] Widget test file for the empty-slot UI message (D-04) — exact path depends on where the
      planner decides to surface it in the program day view; not yet identified because that view
      was not part of this research's required reading list

*(No framework install needed — `flutter_test` and `drift_dev` are already project dependencies.)*

## Environment Availability

Skipped — this phase has no external tool/service dependencies beyond the existing Flutter/Dart/
drift toolchain already required by every other phase in this codebase (verified present via
`CLAUDE.md`'s documented `flutter analyze`/`flutter test`/`tool/codegen.ps1` commands, which the
project already relies on).

## Security Domain

`security_enforcement` is not set in `.planning/config.json`, so treated as enabled per protocol.
This phase is offline-first local domain logic with no new network surface, auth surface, or
user-supplied-string-to-SQL surface (`ProgramSlotExplanations` is populated entirely from
already-validated internal enums/exercise IDs, not raw user input).

| ASVS Category | Applies | Standard Control |
|---------------|---------|-------------------|
| V2 Authentication | No | Phase touches no auth code. |
| V3 Session Management | No | N/A. |
| V4 Access Control | No | Local-only data, no multi-tenant surface introduced. |
| V5 Input Validation | Marginal | `rationale`/explanation text is system-generated (not user input) from a small fixed set of message templates (D-04's example: "No safe [pattern] movement available for your equipment/injuries") — no injection risk, but keep it templated rather than concatenating raw catalog strings without control, consistent with existing `prescriptionWhy` string-interpolation precedent. |
| V6 Cryptography | No | N/A. |

No new STRIDE-relevant threat patterns identified for this stack beyond what already applies to the
existing drift/SQLite local storage (unchanged by this phase).

## Sources

### Primary (HIGH confidence — direct codebase reads, this session)
- `lib/features/programs/data/smart_program_planner.dart` (full file, 1352 lines)
- `lib/features/programs/domain/programming_models.dart` (full file)
- `lib/features/programs/domain/exercise_programming_eligibility.dart` (full file)
- `lib/features/programs/domain/exercise_scaling_resolver.dart` (full file)
- `lib/features/programs/domain/exercise_scorer.dart` (partial, ~330 lines read)
- `lib/features/programs/domain/rotation_policy.dart` (full file)
- `lib/features/programs/domain/slot_role.dart` (full file)
- `lib/features/programs/domain/program_guardrails.dart` (partial)
- `lib/features/recovery/data/joint_pain_repository.dart` (full file)
- `lib/features/recovery/domain/joint_model.dart` (full file)
- `lib/features/recovery/domain/training_suggestion.dart` (full file)
- `lib/data/local/tables.dart` (relevant sections: `ExerciseCatalog`, `ProgramDayExercises`,
  `ProgramExerciseSlots`, `ProgramSlotPoolMembers`, `RotationAssignments`)
- `lib/data/local/seed_data.dart` (`primaryMuscle` value sample, grep-verified)
- `lib/features/programs/presentation/views/block_builder_view.dart` (sole `SmartProgramConfiguration`/
  `.populate()` call site, lines 3230-3300)
- `test/smart_program_planner_test.dart`, `test/exercise_scaling_resolver_test.dart` (existing test
  patterns)
- `test/support/test_database.dart` (in-memory DB helper pattern)
- `.planning/phases/17-deterministic-program-planner-hard-guardrails/17-CONTEXT.md`
- `.planning/REQUIREMENTS.md`
- `.planning/STATE.md`
- `.planning/config.json`
- `CLAUDE.md` (project root)

### Secondary / Tertiary
None — no WebSearch/Context7 lookups were needed; this phase is entirely internal codebase
investigation.

## Metadata

**Confidence breakdown:**
- Standard stack: N/A — no external packages
- Architecture: HIGH — every claim traced to a specific file/line in the actual codebase
- Pitfalls: HIGH — all four pitfalls are existing, currently-reachable code paths, not speculative

**Research date:** 2026-09-13
**Valid until:** Until this phase's plan is written and merged — internal-codebase research has no
external staleness window, but goes stale the moment another phase/branch touches these same files
(check `git log --oneline -- lib/features/programs/ lib/features/recovery/` before planning if this
research is more than a few days old).
