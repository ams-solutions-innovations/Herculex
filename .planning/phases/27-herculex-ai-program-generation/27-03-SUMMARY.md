---
phase: 27-herculex-ai-program-generation
plan: 03
subsystem: programs
tags: [dart, domain-model, json-parsing, validation, ai, program-brief]

# Dependency graph
requires:
  - phase: 26-herculex-ai-knowledge-base-brand-unification
    provides: knowledge_base.ts corpus injection contract (programBriefPrompt in a later plan grounds against this)
provides:
  - "ProgramBrief/DayRoleBrief pure-Dart domain model with strict fromJson/toJson"
  - "The authoritative client-side gate that rejects any AI brief containing an exercise-shaped field or an unknown enum value"
affects: [27-06 (Edge Function normalizeProgramBriefResult mirrors this parser's strictness), 27-09 (HerculexAiBriefService persists ProgramBrief.toJson() verbatim), 27-04 (HerculexAiProgramBriefs table stores this exact JSON shape)]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Strict Set-membership enum lookup (_strictSplitType/_strictPeriodizationModel/_strictDayStressRole) that throws FormatException on miss, as the AI-input counterpart to the codebase's existing lenient fromId(..., orElse: default) helpers which are reserved for user input"
    - "Recursive disallow-list scan over a raw decoded JSON map, run before any field-by-field parsing, to enforce a negative schema (no exercise-shaped keys at any depth)"

key-files:
  created:
    - lib/features/programs/domain/program_brief.dart
    - test/program_brief_test.dart
  modified: []

key-decisions:
  - "musclePriorities is List<ProgrammingMusclePriority>, importing dream_physique_service.dart's existing type verbatim rather than re-declaring a parallel shape (D-01) — zero new apply logic needed in _applyDreamPhysiqueTuning()"
  - "Enum validation never calls the existing SplitType.fromId/PeriodizationModel.fromId/DayStressRole.fromId statics — those use orElse: () => default, which is exactly the silent-failure D-02 forbids for AI output. New private strict lookups check Set membership first and throw."
  - "The exercise-shaped-field scan runs first, over the whole raw JSON map, before any field is parsed — a single clear rejection reason (first prohibited key found), never a collected list, per D-02/D-05's single-outcome intent"

patterns-established:
  - "Strict-reject-unknown-enum: any future AI-sourced Dart parser in this codebase should follow _strictSplitType's shape (Set.contains-or-throw) rather than an existing lenient fromId"

requirements-completed: [AIP-02, AIP-03]

# Metrics
duration: 25min
completed: 2026-09-30
---

# Phase 27 Plan 03: ProgramBrief Domain Model Summary

**Pure-Dart ProgramBrief/DayRoleBrief parser that strictly validates Herculex AI's program design brief — rejecting any exercise-shaped field or unknown enum value as a whole-brief FormatException — and reuses Dream Physique's ProgrammingMusclePriority shape verbatim for musclePriorities.**

## Performance

- **Duration:** ~25 min
- **Tasks:** 1 completed (TDD: RED then GREEN)
- **Files modified:** 2 (1 new domain file, 1 new test file)

## Accomplishments
- `ProgramBrief.fromJson`/`toJson` and `DayRoleBrief.fromJson`/`toJson` implemented as plain Dart (no Flutter/Riverpod imports), per the `domain/` layout rule.
- Strict enum validation for `splitType`, `periodizationModel`, and `dayRoles[].role` via new private `_strict*` lookups that throw `FormatException` on any unknown id, never the existing lenient `fromId(..., orElse: ...)` statics.
- `musclePriorities` reuses `ProgrammingMusclePriority`/`canonicalProgrammingMuscleIds`/`ProgrammingPriorityLevel` from `dream_physique_service.dart` verbatim (D-01) — confirmed by a test that feeds an unknown `muscleId` ("forearm", singular) and gets the exact same rejection Dream Physique already has.
- A recursive disallow-list scan (`_rejectProhibitedExerciseFields`) runs first, at any nesting depth, rejecting `exerciseId`/`sets`/`reps`/`load`/`rpe`/`tempo`/`timeCap` wherever they appear — top level, inside a `dayRoles` entry, or inside a `musclePriorities` entry (AIP-02, threat T-27-04).
- `toJson()` round-trips losslessly through `fromJson()` — verified field-by-field (no `==`/`hashCode` implemented; the round-trip test compares every field explicitly, matching this codebase's existing `DreamPhysiqueProgrammingProfile` convention of not implementing equality).

## Task Commits

TDD RED/GREEN cycle for the single task:

1. **RED:** `3441324` (test) — `test/program_brief_test.dart` added; fails to compile since `program_brief.dart` doesn't exist yet.
2. **GREEN:** `cadf5da` (feat) — `lib/features/programs/domain/program_brief.dart` implemented; test file's missing `dream_physique_service.dart` import (needed for `ProgrammingPriorityLevel` in an assertion) fixed in the same commit once the compile error surfaced. 39/39 tests passing.

No REFACTOR commit was needed — the implementation matched the plan's prescribed shape cleanly on first pass.

**Plan metadata:** this commit (docs: complete plan).

## Files Created/Modified
- `lib/features/programs/domain/program_brief.dart` - `ProgramBrief`, `DayRoleBrief`, strict enum lookups, exercise-field disallow-list scan, `toJson`/`fromJson`
- `test/program_brief_test.dart` - 39 unit tests covering valid parse, strict enum rejection (4 fields), exercise-field prohibition (7 keys × 3 nesting positions = 21 cases), missing-required-field cases, `DayRoleBrief` field validation, and the round-trip guarantee

## Decisions Made
See `key-decisions` in frontmatter. No decisions required deviating from the plan's `<interfaces>`/`<action>` guidance — the plan's prescribed shape (private `_strict*` lookups, reused `ProgrammingMusclePriority`, recursive scan before parsing) was implemented as specified.

## Deviations from Plan

None — plan executed exactly as written. One incidental fix during the TDD GREEN step: the test file (written during RED) referenced `ProgrammingPriorityLevel` in an assertion without importing `dream_physique_service.dart`; this only surfaced as a compile error once `program_brief.dart` itself compiled (RED's failure was solely "undefined name ProgramBrief/DayRoleBrief", which masked the second missing import). Added the import in the same GREEN commit — this is normal TDD iteration, not a Rule 1-4 deviation from the plan's design.

## Verification

- `flutter test test/program_brief_test.dart` — 39/39 passing.
- `flutter analyze lib/features/programs/domain/program_brief.dart test/program_brief_test.dart` — 0 issues.
- `dart run tool/check_structure.dart` — no new violations (both files well under the 600-line cap: 236 and 283 lines respectively).
- Confirmed `program_brief.dart` has zero Flutter/Riverpod imports (only imports `dream_physique_service.dart`, `periodization.dart`, `programming_models.dart`, `split_template.dart`).

Per this plan's note, the full `flutter test` suite was not run standalone in this session (targeted-file validation only, per the plan's explicit allowance for a wave-level full-suite check by the orchestrator) — this plan's files are new and self-contained (no shared files with 27-01/27-02), so no regression risk to the existing suite is expected.

## Known Stubs

None. This plan is a self-contained domain model with no UI/consumer wiring yet (that's plans 27-06 through 27-09) — no stub data paths were introduced.

## Threat Flags

None beyond what the plan's own `<threat_model>` already covers (T-27-03, T-27-04) — no new trust boundary or surface was introduced beyond the ProgramBrief parser itself.

## Self-Check: PASSED

- FOUND: lib/features/programs/domain/program_brief.dart
- FOUND: test/program_brief_test.dart
- FOUND: 3441324 (RED commit)
- FOUND: cadf5da (GREEN commit)
