---
phase: 18-workout-time-budget-warmups-set-method-prescriptions
verified: 2026-09-15T00:00:00Z
status: passed
score: 4/4 must-haves verified
overrides_applied: 0
---

# Phase 18: Workout Time Budget, Warmups & Set Method Prescriptions Verification Report

**Phase Goal:** Introduce `SlotPrescriptionCodec` as the single shared prescription
model so preview and live session resolve byte-identically (PRES-01); make program
generation honor the user's time budget by trimming accessory/isolation work only
(PRES-02); replace fixed warmup tables with an intensity/order-scaled resolver
(PRES-03); hard-hide advanced intensity techniques from `SlotRole.main` unless
opted in (PRES-04).

**Verified:** 2026-09-15
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | PRES-01: Preview and live session resolve prescriptions/warmups through the identical call path (byte parity) | VERIFIED | `lib/features/workouts/data/scheduled_workout_service.dart:132-141` (`previewScheduledWorkout`) and `:154-186` (`startScheduledWorkoutById`) both instantiate `PlannedSessionResolver(_db)` and call `.resolveProgramDay(programDay.id, templateOverride: ...)` with identical arguments — no separate preview-only code path exists. `resolveProgramDay` itself (`planned_session_resolver.dart`) decodes `prescriptionCodecJson` via `SlotPrescriptionCodec.decode` and computes warmups via `WarmupResolver.resolve`, confirmed by reading the file directly (18-04). The calendar preview sheet (`day_detail_sheet.dart:629`) renders `formatPlannedExerciseSets(plannedExercise)` against the `PlannedExerciseSnapshot` returned by this same resolver — old `_setSummary` compact-count code deleted, confirmed via grep (only one definition/one call site remain). |
| 2 | PRES-02: Generation trims accessory/isolation only, protecting main/supplemental, when itemized duration exceeds `workoutDurationMinutes*1.10` | VERIFIED | `lib/features/programs/data/smart_program_planner.dart:285-325`: `budget = workoutDurationMinutes * 1.10`; `isTrimmableRole` returns true only for `SlotRole.isolation`/`SlotRole.accessory`; the `while` loop shrinks set counts (floor 1) then drops slots, isolation prioritized over accessory, and `main`/`supplemental` are structurally excluded from both the `shrinkable`/`trimmable` filters — read directly, not inferred from SUMMARY. `_estimateDayDuration` (line ~1409) delegates to `WorkoutDurationEstimator.estimateSession`, a real itemized estimate (not a flat buffer), confirmed in `lib/features/workouts/domain/workout_duration_estimator.dart`. |
| 3 | PRES-03: Warmup ramps scale in density with target %1RM and abbreviate for later heavy lifts in the same session, fully replacing the old fixed tables | VERIFIED | `lib/features/workouts/domain/warmup_resolver.dart`: four density tiers keyed on `%1RM` thresholds (0.90+ → 5-step dense ramp, 0.80+ → 4-step, 0.70+ → 3-step, else → 2-step light ramp), and `isFirstHeavyLiftInSession=false` truncates to the top half of steps (D-09). `planned_session_resolver.dart`'s old `_automaticWarmups`/`_maxEffortSets` tables are gone (confirmed absent via SUMMARY-reported deletion and no matches found in current file); `resolveProgramDay` tracks `sawHeavyLiftInSession` across ordered exercises to feed `isFirstHeavyLiftInSession`. |
| 4 | PRES-04: Advanced techniques (drop/rest-pause/myo-reps/AMRAP) are hard-hidden from the set-type menu for `SlotRole.main`, and for other roles unless `allowTimeSavingSetTechniques` opt-in is set | VERIFIED | `lib/features/workouts/presentation/widgets/set_type_menu.dart:15-16`: `isAdvancedTechniqueAllowed(role, programAllows) => role != SlotRole.main && programAllows`. `_hypertrophyItems`/`_timedItems` (lines 476-487) are instance getters that filter `SetTypeInfo.all` at list-construction time using `allowAdvancedTechniques` — items are never added to the list (hard-hide, not disabled state), confirmed by reading the widget's `build()` which iterates only over the filtered getters. `active_exercise_card.dart` call site derives `allowed` from `workoutExercise.plannedSlotRole`/`plannedAllowsAdvancedTechniques` (schema v43 columns, confirmed present in `database.dart` schemaVersion 43 and `supabase/migrations/20260915000000_slot_prescription_codec_v43.sql`). |

**Score:** 4/4 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `lib/features/programs/domain/slot_prescription_codec.dart` | Versioned JSON codec, pure Dart | VERIFIED | Exists, plain-Dart only imports (`dart:convert`, `slot_prescription.dart`, `set_type.dart`), encode/decode implemented, no legacy-shape fallback per D-04. |
| `lib/features/workouts/domain/warmup_resolver.dart` | Pure-Dart density/order-based warmup resolver | VERIFIED | Domain-pure (only imports `slot_role.dart`), implements D-08/D-09 exactly as designed. |
| `lib/features/workouts/domain/workout_duration_estimator.dart` | Pure-Dart itemized duration estimator | VERIFIED | Domain-pure (imports only `set_type.dart`, `warmup_resolver.dart`); itemizes working sets, warmups, unilateral doubling, mini-set bursts per D-06. |
| `lib/features/workouts/data/planned_session_resolver.dart` | Single resolver read path for preview+session | VERIFIED | `resolveProgramDay` reads codec + WarmupResolver; confirmed as the shared call site for both `previewScheduledWorkout` and `startScheduledWorkoutById`. |
| `lib/features/programs/data/smart_program_planner.dart` | Two-pass generation with time-budget trim loop | VERIFIED | Trim loop present and correctly scoped to isolation/accessory only (lines 285-325). |
| `lib/features/workouts/presentation/widgets/set_type_menu.dart` | Hard-hide gating by role/opt-in | VERIFIED | `isAdvancedTechniqueAllowed` + filtered instance getters confirmed. |
| `lib/features/programs/presentation/sheets/day_detail_sheet.dart` | Calendar preview renders set-by-set detail | VERIFIED | `formatPlannedExerciseSets` implemented and wired at the one render call site; old summary function fully removed. |
| Schema v43 (drift + supabase) | 3 new columns, 5-chore bump complete | VERIFIED | `schemaVersion => 43` in `database.dart`; `onUpgrade` branch `if (from < 43 && to >= 43)` present; `drift_schemas/drift_schema_v43.json` dumped; matching `supabase/migrations/20260915000000_slot_prescription_codec_v43.sql` adds `prescription_codec_json`, `allow_time_saving_set_techniques`, `planned_allows_advanced_techniques` — column names/tables match the Dart-side additions. |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|----|--------|---------|
| `scheduled_workout_service.previewScheduledWorkout` | `PlannedSessionResolver.resolveProgramDay` | direct call | WIRED | Identical call signature to `startScheduledWorkoutById`'s call, same resolver instance construction pattern. |
| `scheduled_workout_service.startScheduledWorkoutById` | `PlannedSessionResolver.resolveProgramDay` | direct call | WIRED | Same as above; both feed into `resolver.materialize(plan, ...)` downstream for session start only (preview does not materialize — correct per read-only preview contract). |
| `smart_program_planner.populate()` trim loop | `WorkoutDurationEstimator.estimateSession` | `_estimateDayDuration` | WIRED | Real per-slot `WarmupResolver.resolve(...)` inputs and real unilateral flag from `ExerciseCatalog.movementPatternRaw`, not static/hardcoded values. |
| `active_exercise_card.dart` | `SetTypeMenu.show(allowAdvancedTechniques:)` | direct call | WIRED | Derives `allowed` from `isAdvancedTechniqueAllowed(role, workoutExercise.plannedAllowsAdvancedTechniques)`. |
| `day_detail_sheet.dart` `_WorkoutPlanPreviewSheet` | `formatPlannedExerciseSets` | direct call | WIRED | Single call site at line 629; old `_setSummary` deleted (no remaining references). |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `lib/features/programs/presentation/sheets/day_detail_sheet.dart` | n/a (whole file) | 827 lines, over CLAUDE.md's 600-line hand-written-file limit | WARNING (pre-existing, not new) | File was already 783 lines before 18-06's commit (`git show a0fda03~1` = 783 lines; `git show e7a7f05` = 783 lines, the last unrelated prior touch). 18-06 added 44 lines without splitting. This is a **pre-existing violation that the phase made larger, not a newly introduced one** — `tool/check_structure.dart`'s 59-file violation list already included files far larger before this phase (e.g. `set_type_menu.dart` grew from 1920→1953 lines in 18-03, `block_builder_view.dart` at 3398 lines untouched). Not a blocker per CLAUDE.md's own acknowledgment that the codebase carries 51+ pre-existing violations, but flagged since the phase had an opportunity to split under the `views/sheets/dialogs/widgets/` convention and did not. |
| `lib/features/workouts/data/planned_session_resolver.dart` | n/a | Was 664 lines pre-18-04 (already over limit), now 638 lines post-18-04 | INFO | Phase reduced this file's size (deleted `_automaticWarmups`/`_maxEffortSets`/`_copiedTemplateSets`), still over 600 but improved, not worsened. |

No TBD/FIXME/XXX markers, no placeholder/stub returns, no empty handlers found in the phase's touched files.

### Behavioral / Structural Checks

| Check | Command | Result | Status |
|-------|---------|--------|--------|
| `flutter analyze` | `flutter analyze` | 0 errors, 41 info/warning issues (all pre-existing, none introduced by phase-18 files) | PASS |
| `dart run tool/check_structure.dart` | layout rule checker | 59 violations, all pre-existing files (none newly crossed the 600-line threshold as a result of this phase's diffs — verified via `git show` before/after for the two files touched that appear on the list) | PASS (no new violations introduced) |
| `flutter test` | full suite | 1316 passed, 9 skipped, 0 failed | PASS |
| Domain purity (`domain/` no Flutter/drift imports) | manual import inspection | `warmup_resolver.dart` imports only `slot_role.dart`; `workout_duration_estimator.dart` imports only `set_type.dart`/`warmup_resolver.dart`; `slot_prescription_codec.dart` imports only `dart:convert`/`slot_prescription.dart`/`set_type.dart` | PASS |
| Schema 5-chore checklist | manual file inspection | schemaVersion bump + onUpgrade branch + drift schema dump (v43) + matching supabase migration all present with matching column names | PASS |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| PRES-01 | 18-01, 18-04, 18-06 | Preview/session byte parity via shared codec+resolver | SATISFIED | Single call site confirmed; codec confirmed; preview rendering confirmed wired. |
| PRES-02 | 18-02, 18-05 | Time-budget trimming protects main/supplemental | SATISFIED | Trim loop logic read directly and confirmed correctly scoped. |
| PRES-03 | 18-02, 18-04 | Warmup resolver replaces fixed tables, scales with intensity/order | SATISFIED | `WarmupResolver` implementation matches D-08/D-09 exactly. |
| PRES-04 | 18-03 | Hard-hide advanced techniques by role/opt-in | SATISFIED | Gate predicate + filtered instance getters confirmed as hard-hide, not disabled-state. |

No orphaned requirements found — all four PRES IDs are claimed by at least one plan and independently verified against source.

### Human Verification Required

None. All four PRES requirements resolve to structural, grep/read-verifiable code paths (resolver call sites, trim-loop role filters, density tables, list-construction-time filtering) rather than visual/UX judgment calls. The one visual aspect (calendar preview rendering) is covered by `test/features/workouts/day_detail_sheet_preview_test.dart` (4/4 passing, confirmed in full-suite run) and the formatting function's grouping logic was read directly rather than assumed.

### Gaps Summary

No gaps. All four PRES requirements are structurally satisfied, not just claimed:

- The preview/session parity claim (PRES-01) was independently verified by reading `scheduled_workout_service.dart` directly rather than trusting the SUMMARY — both call sites use the identical resolver call.
- The trim loop (PRES-02) was read line-by-line to confirm `SlotRole.main`/`supplemental` are structurally excluded from the trimmable-role predicate, not just documented as excluded.
- The warmup density/order logic (PRES-03) was read to confirm actual threshold tables and abbreviation math match the phase's D-08/D-09 decisions.
- The hard-hide gate (PRES-04) was read to confirm gated items are excluded at list-construction time (never added to the widget tree), matching D-13's "hard hide, not disabled" requirement.

The one documented deviation worth flagging for awareness (not a gap): `day_detail_sheet.dart`'s 827-line size is a **pre-existing violation made larger, not introduced** — confirmed via `git show` on the commit immediately before 18-06's change (783 lines already present). This does not block phase completion per CLAUDE.md's own acknowledgment of 51+ existing violations, but should be swept up whenever the file-size cleanup backlog is addressed.

`flutter analyze` (0 errors), `flutter test` (1316/9/0), and `dart run tool/check_structure.dart` (59 pre-existing violations, none newly introduced) were run directly, not assumed from SUMMARY claims.

---

_Verified: 2026-09-15_
_Verifier: Claude (gsd-verifier)_
