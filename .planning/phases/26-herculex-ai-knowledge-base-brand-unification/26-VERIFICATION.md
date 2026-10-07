---
phase: 26-herculex-ai-knowledge-base-brand-unification
verified: 2026-09-28T00:00:00Z
status: passed
score: 8/8 must-haves verified (1 resolved via human override)
overrides_applied: 1
overrides:
  - item: "KB-04's 'labelled AI advice channel' scope for this phase"
    decision: "Deferred — treated as an intentional Phase 26 boundary, same pattern as KB-01/KB-02's D-04 corpus-consumption deferral. Not built in Phase 26. Not yet claimed by any specific future phase's ROADMAP.md goal — whichever phase first builds AI-driven, source-labelled user-facing advice (candidates: Phase 29's Herculex AI weekly-report narrative, or a dedicated Hercul enhancement) should pick this up and close it against KB-04 explicitly, rather than letting it stay implicitly deferred indefinitely."
    decided_by: "user, via orchestrator AskUserQuestion during phase 26 execute-phase run"
    decided_at: "2026-09-28"
human_verification: []
---

# Phase 26: Herculex AI Knowledge Base & Brand Unification Verification Report

**Phase Goal:** Establish the server-side coaching knowledge base that grounds every Herculex AI output, make provenance traceable, unify the user-facing brand on "Herculex AI", and replace the shared daily AI cap with per-kind quotas that fail closed.
**Verified:** 2026-09-28
**Status:** passed (1 override applied)
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | `knowledge_base.ts` ships a versioned corpus beside `prompts.ts`, never reaches the Flutter bundle (KB-01, foundational scope per D-02/D-03/D-09/D-04) | ✓ VERIFIED | `supabase/functions/gemini-analyze/knowledge_base.ts` exports exactly 5 `export const` (`core`, `programming`, `nutrition`, `recovery`, `KNOWLEDGE_VERSION = "kb-2026.10-1"`); no `lib/` import references it (grep confirmed); `deno test` on `knowledge_base_test.ts` passes 3/3. Per 26-CONTEXT.md D-04, no existing kind consumes it yet — this is documented, authorized foundational scope for this phase, not a gap. |
| 2 | System-instruction injection path is provably wired end-to-end, and `provenance.modelVersion` (not `knowledgeVersion`) is present on all 8 kinds' responses (KB-02, foundational scope per D-05/D-06/D-07/D-08) | ✓ VERIFIED | `buildSystemInstruction()` exported in `index.ts`, threaded into `generate()`'s REST body as `system_instruction`; `grep -c "provenance: { modelVersion"` = 8; `grep -c "knowledgeVersion"` = 0 (as intended — D-06 explicitly omits it this phase). `deno test index_test.ts` (3/3) proves primary vs. 429/503-fallback model reporting. |
| 3 | No user-visible string reads "Gemini" anywhere in the app; every AI surface reads "Herculex AI"; provider naming (class names, `kind` values, docs, sentinel error strings) is untouched (KB-03) | ✓ VERIFIED | Repo-wide grep of `lib/**/*.dart` for "Gemini"/"Gemini AI" finds **zero** remaining display strings — every hit is a protected class name (`GeminiBackend`, `GeminiFoodAnalyzerService`, `GeminiPhotoAnalysisDialog`…), a doc comment, an enum value (`LabelExtractionSource.gemini`), or the two `index.ts` sentinel-matching lines in `dream_physique_view.dart:307-308` (deliberately untouched, D-17/Pitfall-1). The GDPR Article 9 consent string at line 819 now reads "I agree to send these photos to Herculex AI (powered by Google Gemini)" — both `flutter test test/dream_physique_view_test.dart` (finds `Google Gemini` substring) and `flutter analyze` pass. Server-side `foodPhotoPrompt()` now instructs the model to return `"brand": "Herculex AI"`; all 4 Dart brand-literal defaults renamed; historical rows left un-migrated per D-18 (verified: no UPDATE/migration statement exists). |
| 4 | Hercul's deterministic rule engine and its closed-vocabulary test keep working, offline, completely unmodified by this phase (KB-04, non-regression half) | ✓ VERIFIED | `flutter test test/hercul_engine_test.dart` — 25/25 passing. `git diff` / `find lib/features/hercul` confirms no file in `lib/features/hercul/` was touched by any of the 7 plans. |
| 5 | Hercul gains a labelled AI advice channel alongside the deterministic engine (KB-04, "second channel" half) | ✓ RESOLVED (human override) | No such UI or plumbing exists anywhere in `lib/features/hercul/` or elsewhere in the codebase. Human decision (2026-09-28): deferred as an intentional Phase 26 boundary, mirroring the KB-01/KB-02 D-04 pattern. Whichever future phase first ships AI-driven, source-labelled user-facing advice (candidate: Phase 29's Herculex AI narrative work) should claim and close this against KB-04 explicitly. |
| 6 | Per-kind AI quotas replace the single shared daily cap; exhausting one kind never blocks another (KB-05, D-10/D-11/D-12) | ✓ VERIFIED | `index.ts`'s `kindLimits`/`limitForKind()` reads 8 `GEMINI_LIMIT_*` env vars tiered 30/15/10 per D-11; `grep -c "GEMINI_LIMIT_"` = 8. Migration `0021_ai_usage_bump_per_kind.sql` scopes the quota sum with `and kind = p_kind` (read directly, confirmed). `deno test usage_test.ts` proves `limitForKind("dream_physique")` = 10 with fallback to `dailyLimit` for unknown kinds. |
| 7 | Quota exhaustion fails closed (never silently allowed) after one retry, with a kind-specific message naming the capped feature and its limit (KB-05, D-13/D-14) | ✓ VERIFIED | `bumpUsage()` retries exactly once (`for (let attempt = 0; attempt < 2; ...)`) then returns `{ error: ... }` on both failures — `deno test usage_test.ts`'s "fails closed... after exactly one retry" test passes, asserting 2 RPC calls. The 429 response branch builds a message via `kindDisplayNames[...]` naming the specific feature and `${quota.limit}/day`, with a manual-fallback hint for `food_photo`/`rambler_food`. |
| 8 | The corrected `ai_usage_bump` SQL is live on the production Supabase project (`ldzgyzigvbwofbswitrv`), not just written locally (KB-05) | ✓ VERIFIED | Ran `npx supabase migration list` directly against the live project during this verification: migration `0021` shows `"local":"0021","remote":"0021"` — confirmed live, matching 26-02-SUMMARY.md's claim. `0018_shared_data_hardening.sql` is untouched (new file `0021` supersedes it logically only). |

**Score:** 8/8 truths verified (1 resolved via human override — see above).

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `supabase/functions/gemini-analyze/knowledge_base.ts` | 4 corpus segments + KNOWLEDGE_VERSION | ✓ VERIFIED | 5 `export const`, no Dart import, `deno test` passes |
| `supabase/functions/gemini-analyze/index.ts` | `buildSystemInstruction`, modelVersion threading, provenance in all 8 kinds, per-kind quota, fail-closed retry, KB-03 renames | ✓ VERIFIED | All grep/test assertions from plans 26-01/26-02 reproduced independently |
| `supabase/migrations/0021_ai_usage_bump_per_kind.sql` | kind-scoped WHERE clause, dropped default | ✓ VERIFIED | Read directly; confirmed live via `supabase migration list` |
| `supabase/functions/gemini-analyze/{knowledge_base,index,usage}_test.ts` | Deno test coverage | ✓ VERIFIED | `deno test -A supabase/functions/gemini-analyze/` → 11/11 passing |
| `lib/features/nutrition/data/gemini_food_analyzer_service.dart` | Brand defaults → "Herculex AI" | ✓ VERIFIED | grep confirms 0 "Gemini AI" occurrences; test passes |
| `lib/features/profile/presentation/dream_physique_view.dart` | 3 renamed strings, reworded consent, untouched sentinels | ✓ VERIFIED | grep shows exactly lines 307/308 (sentinels) and 819 (consent) contain "Gemini" |
| ~34 other brand-rename sites (measurements, nutrition dialogs, supplements, workouts, profile) | All renamed to "Herculex AI" | ✓ VERIFIED | Full repo grep sweep across `lib/` found zero remaining display-string occurrences of "Gemini"/"Gemini AI" outside protected identifiers/comments/sentinels |
| `lib/features/hercul/**` | Untouched, non-regressed | ✓ VERIFIED | No files changed; `flutter test test/hercul_engine_test.dart` 25/25 |
| A labelled second AI-advice channel next to Hercul | Per KB-04's full requirement text | ⏭ DEFERRED (human override, 2026-09-28) | No code found; deferred per RESEARCH.md and human decision — not yet claimed by a specific future phase, flagged for Phase 29 or a dedicated follow-up |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|----|--------|---------|
| `index.ts generate()` | Gemini REST request body | `system_instruction` sibling of `contents` | ✓ WIRED | Confirmed in source; test 1 of `index_test.ts` verifies shape |
| `index.ts` switch branches | `json()` response envelope | `provenance: { modelVersion }` | ✓ WIRED | 8/8 branches confirmed via direct read + grep count = 8 |
| `index.ts` quota call site | `limitForKind()` | per-kind limit lookup before `bumpUsage` | ✓ WIRED | `limitForKind(payload.kind)` passed into `bumpUsage(userId, payload.kind, limitForKind(payload.kind))` |
| `index.ts bumpUsage()` | `ai_usage_bump` RPC (migration 0021) | 3-arg fetch POST, `p_daily_limit: limit` | ✓ WIRED | Confirmed in source; live migration confirmed via `supabase migration list` |
| `dream_physique_view.dart:307-308` | `index.ts`'s untouched sentinel error strings | literal `.contains()` substring match | ✓ WIRED | Both sides verified byte-identical to pre-phase text |
| `prompts.ts foodPhotoPrompt()` → model JSON → `GeminiFoodAnalyzerService` → `gemini_photo_analysis_dialog.dart` save path | New food-log rows | brand literal "Herculex AI" propagated through all 5 sites | ✓ WIRED | All 5 sites confirmed; regression test for omitted-`brand`-key fallback passes |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| KB-01 | 26-01 | Versioned knowledge base ships server-side, injected as system instruction, never in app bundle | ✓ SATISFIED (foundational scope, per phase's own D-04 boundary) | knowledge_base.ts + buildSystemInstruction() plumbing; no kind consumes it yet by design |
| KB-02 | 26-01 | Every AI result records knowledgeVersion and modelVersion | ✓ SATISFIED (foundational scope, per phase's own D-06 boundary) | modelVersion ships on all 8 kinds now; knowledgeVersion intentionally deferred until a kind actually injects a corpus segment (Phase 27+) |
| KB-03 | 26-02/03/04/05/06/07 | No user-visible "Gemini" string; internal naming untouched | ✓ SATISFIED | Full repo grep sweep confirms zero remaining display strings; all identifiers/sentinels/consent preserved correctly |
| KB-04 | 26-02 | Hercul gains a labelled AI advice channel; hercul_rules.json/HerculSignals.all/closed-vocab test stay intact | ✓ SATISFIED (non-regression half; "channel" half deferred by human override) | Non-regression half fully verified (25/25 tests pass, files untouched). "Labelled AI advice channel" half deferred to a future phase per 2026-09-28 human decision |
| KB-05 | 26-02 | Per-kind quotas replace shared cap; fails closed with clear message | ✓ SATISFIED | Migration 0021 live in production; fail-closed-after-one-retry and kind-specific messaging both verified by independent test run |

No orphaned requirements — all of KB-01–05 are claimed by at least one plan's frontmatter, matching REQUIREMENTS.md §12.

### Anti-Patterns Found

None. Grep for `TBD|FIXME|XXX|TODO|HACK|PLACEHOLDER` across all 27 files touched by this phase's 7 plans returned zero matches.

### Behavioral Spot-Checks / Test Execution (run independently during this verification, not taken from SUMMARY.md claims)

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Edge function unit tests | `deno test -A supabase/functions/gemini-analyze/` | 11/11 passed (index_test.ts x3, knowledge_base_test.ts x3, prompts_test.ts x2, usage_test.ts x3) | ✓ PASS |
| Hercul non-regression | `flutter test test/hercul_engine_test.dart` | 25/25 passed | ✓ PASS |
| Food-analyzer brand fallback | `flutter test test/gemini_food_analyzer_service_test.dart` | 4/4 passed | ✓ PASS |
| Dream Physique consent string | `flutter test test/dream_physique_view_test.dart` | 1/1 passed | ✓ PASS |
| Static analysis | `flutter analyze` | 0 errors, 80 pre-existing warnings (1 in a touched file, `body_fat_ai_service.dart:186`, confirmed pre-existing and unrelated) | ✓ PASS |
| Live migration state | `npx supabase migration list` against `ldzgyzigvbwofbswitrv` | `0021`: local == remote | ✓ PASS |

### Human Verification Required

None outstanding — see Overrides Applied below.

### Overrides Applied

**1. KB-04's "labelled AI advice channel" scope decision — RESOLVED 2026-09-28**

**Question:** Was Phase 26 ever meant to build a second, source-labelled AI advice channel alongside Hercul's deterministic rule engine, or is this — like KB-01/KB-02's corpus-consumption half — intentionally deferred to a not-yet-scheduled future phase?
**Decision (user, via orchestrator):** Defer. Treated as an intentional Phase 26 boundary, same pattern as KB-01/KB-02's D-04 deferral. Not built in Phase 26. **Not yet claimed by any specific future phase** — whichever phase first ships AI-driven, source-labelled user-facing advice (candidate: Phase 29's Herculex AI weekly-report narrative) should explicitly claim and close this against KB-04, rather than letting it stay implicitly deferred indefinitely. Future phase planning for 27/28/29 should read this note.

### Gaps Summary

No BLOCKER-level gaps. All server-side (Deno) and Dart-side automated tests were re-run independently during this verification (not taken on SUMMARY.md's word) and all passed: 11 Deno tests, 30 Flutter tests across the 3 phase-relevant files, `flutter analyze` at 0 errors, and the live Supabase migration state was confirmed directly against the production project. KB-01, KB-02, KB-03, and KB-05 are fully satisfied against what this phase's own plans and locked context (D-01 through D-20) promised to build. KB-04's non-regression guarantee holds; its "labelled AI advice channel" half is deferred by explicit human decision (see Overrides Applied above) rather than treated as a code defect — but remains unclaimed by any future phase and should be tracked so it isn't lost.

---

*Verified: 2026-09-28*
*Verifier: Claude (gsd-verifier)*
