---
phase: 27-herculex-ai-program-generation
plan: 05
subsystem: ai
tags: [dart, gemini, supabase, provenance, program-brief]

# Dependency graph
requires:
  - phase: 27-herculex-ai-program-generation (plan 03)
    provides: ProgramBrief/DayRoleBrief domain model this method's JSON result feeds into
affects: [27-06 (Edge Function's program_brief kind, called via this method's 'kind' body key), 27-09 (HerculexAiBriefService will call generateProgramBrief() exclusively)]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Dart record return type (Map, Map) for a client method that must surface both a result and separate provenance metadata, as a sibling to the existing result-only _resultMap() contract rather than a breaking change to it"

key-files:
  created:
    - test/gemini_backend_service_test.dart
  modified:
    - lib/services/ai/gemini_backend_service.dart
    - test/gemini_food_analyzer_service_test.dart
    - test/dream_physique_service_test.dart
    - test/supplement_ai_service_test.dart
    - test/body_fat_ai_service_test.dart

key-decisions:
  - "generateProgramBrief() is the only GeminiBackend method returning a (result, provenance) record; the existing 8 methods and _resultMap() are untouched, per RESEARCH.md Pitfall 2's explicit avoid-breaking-change guidance"
  - "_resultWithProvenance() reuses _resultMap() internally for result extraction/validation rather than duplicating the Map-vs-Map<String,dynamic> cast logic"
  - "dream_physique_service_test.dart has TWO classes that implement GeminiBackend directly (_MockGeminiBackend and _FailingGeminiBackend), not one as the plan's <interfaces> section stated — both were updated, matching their shared UnimplementedError convention"
  - "Testing SupabaseGeminiBackend.generateProgramBrief's actual _invoke body construction ('kind': 'program_brief') was left to code review rather than a live test, since no existing test in this codebase exercises SupabaseGeminiBackend directly (it requires a real/mocked SupabaseClient, a pattern not established anywhere in the suite) — the client-side test coverage instead targets UnconfiguredGeminiBackend's throw and the provenance-extraction logic, per the plan's own allowance for a standalone/static extraction helper when direct testing isn't feasible"

patterns-established:
  - "Provenance-surfacing sibling method pattern: when a new backend method needs richer return data than the existing shared helper provides, add a new sibling method that internally reuses the existing helper for the parts of its contract that are unchanged, rather than widening the existing helper's signature for all callers"

requirements-completed: []  # AIP-02/AIP-03 remain partial - see Deviations/Decisions; not marked complete here, consistent with the phase's existing partial-completion convention (see 27-03-SUMMARY.md)

# Metrics
duration: 35min
completed: 2026-09-30
---

# Phase 27 Plan 05: GeminiBackend.generateProgramBrief() Summary

**generateProgramBrief() added to all three GeminiBackend tiers (interface, UnconfiguredGeminiBackend, SupabaseGeminiBackend), returning a (result, provenance) Dart record via a new _resultWithProvenance() helper that reuses _resultMap() without discarding modelVersion/knowledgeVersion, plus generateProgramBrief() stub overrides on all five direct-implementer test fakes across four files so the suite keeps compiling.**

## Performance

- **Duration:** ~35 min
- **Started:** 2026-09-30T07:40:00Z (approx, first file read)
- **Completed:** 2026-09-30T08:15:23Z
- **Tasks:** 2 completed
- **Files modified:** 6 (1 new test file, 5 modified)

## Accomplishments
- `GeminiBackend.generateProgramBrief({required Map<String, dynamic> profileInputs, String? userNote})` added to the abstract interface, returning `Future<(Map<String, dynamic> result, Map<String, dynamic> provenance)>`.
- `UnconfiguredGeminiBackend.generateProgramBrief` throws the exact same `_notConfigured()` Exception every sibling method throws (verified by test: identical `.toString()` against `analyzeRamblerText`'s throw).
- `SupabaseGeminiBackend.generateProgramBrief` builds `{'kind': 'program_brief', 'profileInputs': profileInputs, 'userNote': userNote}`, calls the existing `_invoke(body)` unchanged (text-only, no images, no privacyConsent block — confirmed this is not an image-consuming kind like `dream_physique`), and returns `_resultWithProvenance(data)`.
- New `SupabaseGeminiBackend._resultWithProvenance()` reuses `_resultMap(data)` internally (zero duplicated Map-vs-Map<String,dynamic> cast logic), then reads `data['provenance']` with the same defensive cast pattern, returning an empty map (never throwing) when provenance is absent or malformed.
- `_resultMap()` itself and all 8 existing callers are byte-for-byte unchanged — confirmed via `git diff` showing only additive hunks.
- All 5 existing test-only classes that `implements GeminiBackend` directly (across 4 files) now compile against the widened interface: `_FakeGeminiBackend` (gemini_food_analyzer_service_test.dart, canned-return convention), `_MockGeminiBackend` and `_FailingGeminiBackend` (dream_physique_service_test.dart — two fakes in one file, both UnimplementedError convention), `_MockSupplementBackend` (supplement_ai_service_test.dart), `_MockGeminiBackend` (body_fat_ai_service_test.dart).

## Task Commits

1. **Task 1: generateProgramBrief() across the 3-tier GeminiBackend interface** - `22bb500` (feat)
2. **Task 2: Add generateProgramBrief() stubs to every existing GeminiBackend test fake** - `fc4bef3` (test)

**Plan metadata:** this commit (docs: complete plan) — see final commit below.

## Files Created/Modified
- `lib/services/ai/gemini_backend_service.dart` - added `generateProgramBrief()` to the interface, `UnconfiguredGeminiBackend`, and `SupabaseGeminiBackend`; added `_resultWithProvenance()` private helper
- `test/gemini_backend_service_test.dart` (new) - 5 unit tests: unconfigured-throw message parity, and 4 cases for the provenance-extraction logic (success, missing provenance, loose-Map provenance, invalid result still throws) via a standalone helper mirroring the private method
- `test/gemini_food_analyzer_service_test.dart` - `_FakeGeminiBackend` gains a `generateProgramBrief` override matching its canned-return convention (`_FakeGeminiBackendNoBrand` inherits it, no change needed)
- `test/dream_physique_service_test.dart` - both `_MockGeminiBackend` and `_FailingGeminiBackend` gain `generateProgramBrief` overrides matching their `UnimplementedError` convention
- `test/supplement_ai_service_test.dart` - `_MockSupplementBackend` gains a `generateProgramBrief` override (`UnimplementedError`)
- `test/body_fat_ai_service_test.dart` - `_MockGeminiBackend` gains a `generateProgramBrief` override (`UnimplementedError`)

## Decisions Made
See `key-decisions` in frontmatter. The one substantive deviation from the plan's `<interfaces>` section: it stated each of the four test files has one class implementing `GeminiBackend`, but `dream_physique_service_test.dart` actually has two (`_MockGeminiBackend` and `_FailingGeminiBackend`). Both were found via `grep "implements GeminiBackend"` before editing and both were updated — this is not a scope change, just a more accurate count than the plan's `<interfaces>` hint gave.

## Deviations from Plan

None requiring a deviation rule — the above two-fakes-in-one-file discovery was handled within Task 2's existing scope (the task's own acceptance criteria already covers "all four files compile and pass," which requires updating every direct implementer in each file, not just one per file).

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

`GeminiBackend.generateProgramBrief()` is ready for plan 27-06 (the Edge Function's new `program_brief` kind, which this method's `'kind': 'program_brief'` body key targets) and plan 27-09 (`HerculexAiBriefService`, the sole intended caller). The `(result, provenance)` record shape is confirmed compatible with `ProgramBrief.fromJson(result)` (plan 27-03) for the result half, and with the `HerculexAiProgramBriefs` table's `knowledgeVersion`/`modelVersion` columns (plan 27-04) for the provenance half — no adapter code should be needed at either consumption point.

No blockers. `test/gemini_backend_service_test.dart`'s SupabaseGeminiBackend body-construction claim (`'kind': 'program_brief'`) is verified by direct code read in this session, not by an automated test — the codebase has no existing pattern for mocking `SupabaseClient.functions.invoke`, so plan 27-06's Edge Function work will be the first practical opportunity to exercise this path end-to-end (via `HerculexAiBriefService`'s own tests in plan 27-09, most likely).

## Self-Check: PASSED

- FOUND: lib/services/ai/gemini_backend_service.dart
- FOUND: test/gemini_backend_service_test.dart
- FOUND: .planning/phases/27-herculex-ai-program-generation/27-05-SUMMARY.md
- FOUND: 22bb500 (Task 1 commit)
- FOUND: fc4bef3 (Task 2 commit)
- Full-repo `flutter analyze`: 42 pre-existing info/warning issues, 0 errors (confirmed no error lines in output; none of the 42 issues touch this plan's 6 files)

---
*Phase: 27-herculex-ai-program-generation*
*Completed: 2026-09-30*
