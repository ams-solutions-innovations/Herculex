---
phase: 26-herculex-ai-knowledge-base-brand-unification
plan: 03
subsystem: nutrition
tags: [gemini, brand-unification, supabase-edge-function, drift-free-data-fix, tdd]

# Dependency graph
requires:
  - phase: 26 (plan 01)
    provides: provenance.modelVersion threading through gemini-analyze response envelopes
provides:
  - "All 5 brand/ratingReason write sites for new food-photo log entries (1 server prompt + 4 Dart defaults) now read 'Herculex AI' instead of 'Gemini AI'"
  - "Regression test proving the omitted-brand JSON fallback path stores 'Herculex AI', never null or the stale literal"
affects: [27-herculex-ai-program-generation, 29-weekly-report-narrative]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Brand-literal rename sites tracked as a closed set (prompt instruction + typed-result defaults + UI fallback) so a rename can be verified complete via a single combined grep, per D-17/D-18"

key-files:
  created: []
  modified:
    - supabase/functions/gemini-analyze/prompts.ts
    - supabase/functions/gemini-analyze/prompts_test.ts
    - lib/features/nutrition/data/gemini_food_analyzer_service.dart
    - lib/features/nutrition/presentation/dialogs/gemini_photo_analysis_dialog.dart
    - test/gemini_food_analyzer_service_test.dart

key-decisions:
  - "Historical rows already stored with brand: 'Gemini AI' are left untouched — no backfill migration, per D-18 (a diary entry is a historical record of what happened at logging time)"
  - "Test fixture's brand literal at test/gemini_food_analyzer_service_test.dart:101 was updated to 'Herculex AI' for internal consistency with the new default; D-18 does not protect test fixtures, only real stored rows"

patterns-established:
  - "New negative-case fake backend (_FakeGeminiBackendNoBrand extends _FakeGeminiBackend) isolates a single omitted-JSON-key test without duplicating the full fixture map"

requirements-completed: [KB-03]

# Metrics
duration: 27min
completed: 2026-09-27
---

# Phase 26 Plan 03: Gemini-to-Herculex AI Brand Rename (Food Photo Path) Summary

**All 5 write sites for the food-photo `brand`/`ratingReason` literal (1 server-side prompt instruction + 4 Dart default-value expressions) now read "Herculex AI", proven by a new regression test covering the omitted-brand JSON fallback.**

## Performance

- **Duration:** 27 min
- **Started:** 2026-09-27T16:30:00Z
- **Completed:** 2026-09-27T16:57:05Z
- **Tasks:** 2 completed
- **Files modified:** 5

## Accomplishments
- Closed RESEARCH.md's Pitfall 3: new food-log entries can no longer non-deterministically carry either `'Gemini AI'` or `'Herculex AI'` depending on whether the model's JSON response happens to include a `brand` key.
- Server-side prompt (`prompts.ts`'s `foodPhotoPrompt()`) now instructs the model to return `"brand": "Herculex AI"` for new analyses.
- All 4 Dart default-value expressions (constructor default, `fromJson` brand fallback, `fromJson` ratingReason fallback, dialog save-path fallback) plus 3 dialog display strings now read "Herculex AI".
- New TDD regression test (`_FakeGeminiBackendNoBrand`) proves the omitted-`brand`-key fallback path resolves to `'Herculex AI'`, never `'Gemini AI'` and never null.

## Task Commits

Each task was committed atomically:

1. **Task 1: Rename prompts.ts's brand instruction + extend prompts_test.ts** - `9e4279f` (feat)
2. **Task 2: Update the 4 Dart brand/ratingReason default sites + add the omitted-brand regression test** - RED `e13a4ad` (test) → GREEN `8be81a5` (feat)

**Plan metadata:** (this commit, docs: complete plan)

_Note: Task 2 was TDD — test commit added a failing test first, verified RED, then the implementation commit made it pass (GREEN)._

## TDD Gate Compliance

Task 2 (`tdd="true"`) followed the full RED → GREEN cycle:
- RED: `e13a4ad` (`test(26-03): add failing omitted-brand fallback test`) — verified failing with `Expected: 'Herculex AI', Actual: 'Gemini AI'` before any implementation change.
- GREEN: `8be81a5` (`feat(26-03): rename 4 Dart brand/ratingReason defaults to Herculex AI`) — verified all 4 tests passing after.
- No REFACTOR commit needed (no cleanup required beyond the direct literal renames).

Gate sequence confirmed present in `git log`: test commit precedes feat commit. No warning needed.

## Files Created/Modified
- `supabase/functions/gemini-analyze/prompts.ts` - `foodPhotoPrompt()`'s JSON-schema instruction now returns `"brand": "Herculex AI"`
- `supabase/functions/gemini-analyze/prompts_test.ts` - new assertion on the renamed literal
- `lib/features/nutrition/data/gemini_food_analyzer_service.dart` - `GeminiFoodAnalysisResult`'s constructor default, `fromJson` brand fallback, and `fromJson` ratingReason fallback all renamed
- `lib/features/nutrition/presentation/dialogs/gemini_photo_analysis_dialog.dart` - save-path brand fallback and 3 display strings renamed
- `test/gemini_food_analyzer_service_test.dart` - existing fixture's `brand` literal updated for consistency; new `_FakeGeminiBackendNoBrand` class and regression test added

## Decisions Made
- No backfill of historical rows (D-18) — verified no migration or update statement was written; existing `brand: 'Gemini AI'` rows are untouched by design.
- Test fixture literal updated alongside production defaults since D-18 explicitly does not protect test fixtures, only real stored data.

## Deviations from Plan

None - plan executed exactly as written. All 5 write sites and the test changes matched the plan's exact line-level instructions.

## Issues Encountered

None. `flutter test`, `flutter analyze`, and `deno test` all passed on first attempt after each implementation step. One unrelated side effect was observed and reverted: running `flutter test`/`flutter analyze` locally regenerated `linux/`, `macos/`, and `windows/` generated plugin registrant files (toolchain/platform-version noise, unrelated to this plan's task files) — these were reverted with `git checkout --` before the final task commit to keep the worktree clean, per the scope-boundary rule (out-of-scope, not caused by this plan's code changes).

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- KB-03 (this plan's requirement) is fully closed for the food-photo path: server prompt, all Dart defaults, and UI fallback are consistent, with a regression test locking the omitted-brand behavior in place.
- No blockers for downstream phases. Phase 27 (Herculex AI Program Generation) and Phase 29 (Weekly Report & Narrative) are unaffected by this plan's scope (food-photo brand literal only) but benefit from the established pattern of tracking brand-literal rename sites as a closed, greppable set.

---
*Phase: 26-herculex-ai-knowledge-base-brand-unification*
*Completed: 2026-09-27*

## Self-Check: PASSED

All created/modified files verified present on disk; all task commit hashes (9e4279f, e13a4ad, 8be81a5) verified present in `git log`.
