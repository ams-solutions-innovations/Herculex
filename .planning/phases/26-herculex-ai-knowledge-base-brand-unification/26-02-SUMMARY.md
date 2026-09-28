---
phase: 26-herculex-ai-knowledge-base-brand-unification
plan: 02
subsystem: api
tags: [deno, supabase-edge-functions, gemini, postgres, quota, brand-unification]

# Dependency graph
requires:
  - phase: 26-01
    provides: "knowledge_base.ts corpus, buildSystemInstruction()/modelVersion threading, provenance.modelVersion envelope"
provides:
  - "supabase/migrations/0021_ai_usage_bump_per_kind.sql — kind-scoped ai_usage_bump RPC, live on ldzgyzigvbwofbswitrv"
  - "Per-kind AI quota enforcement in index.ts: kindLimits/limitForKind() via 8 GEMINI_LIMIT_* env vars"
  - "bumpUsage() fails closed after exactly one retry, uniformly across all 8 kinds"
  - "Kind-specific 429 messages naming the capped feature and its limit, with a manual-logging hint for food_photo/rambler_food"
  - "3 remaining KB-03 brand-rename strings in index.ts (Gemini -> Herculex AI)"
affects: [27-ai-program-generation, 29-weekly-report, phys-07]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Runtime-read env vars inside a function body (not module-load-time consts) for values a Deno.test needs to override per-test via Deno.env.set()"

key-files:
  created:
    - supabase/migrations/0021_ai_usage_bump_per_kind.sql
    - supabase/functions/gemini-analyze/usage_test.ts
  modified:
    - supabase/functions/gemini-analyze/index.ts

key-decisions:
  - "bumpUsage() reads SUPABASE_URL/SUPABASE_SERVICE_ROLE_KEY via Deno.env.get() at call time instead of as module-load-time consts (deviation, see below) — the plan's own required fail-closed/retry test behavior was otherwise untestable without a live Supabase project, since module-level consts are computed once at import and Deno.env.set() calls inside a test's Deno.test() body run after that import already evaluated"
  - "Task 3's migration originally used create-or-replace to drop p_daily_limit's default; Postgres rejects that (SQLSTATE 42P13). Fixed to drop+recreate the function, with 0018's revoke re-applied since a drop resets grants to the Postgres default (PUBLIC gets EXECUTE)"

requirements-completed: [KB-03, KB-04, KB-05]

# Metrics
duration: ~30min (Tasks 1-2: ~25min: Task 3 checkpoint + migration fix + push: ~5min)
completed: 2026-09-28
---

# Phase 26: Herculex AI Knowledge Base & Brand Unification — Plan 02 Summary

**Per-kind AI quota enforcement with fail-closed retry, kind-specific 429 messages, the final 3 KB-03 brand-rename strings in `index.ts`, and the corrected `ai_usage_bump` SQL live on the production Supabase project**

## Performance

- **Duration:** ~30 min (Tasks 1-2: ~25 min; Task 3, including the orchestrator's migration-bug fix and live push: ~5 min)
- **Tasks:** 3 of 3 completed
- **Files modified:** 3 (1 new migration, 1 new test file, 1 modified edge function)

## Accomplishments
- `supabase/migrations/0021_ai_usage_bump_per_kind.sql` (new): `ai_usage_bump`'s quota sum now scopes `and kind = p_kind` (D-12) instead of summing across all kinds of a user/day — exhausting `dream_physique` no longer blocks `food_photo`. Drops the `p_daily_limit default 50` so no caller can silently reintroduce the old shared-cap number. `0018_shared_data_hardening.sql` is verified byte-identical (untouched).
- `index.ts` gains `kindLimits`/`limitForKind()` (8 new `GEMINI_LIMIT_*` env vars, tiered defaults per D-11) and `kindDisplayNames` (D-14 feature names for 429 messages).
- `bumpUsage()` rewritten: now takes a required 3rd `limit` argument, retries the RPC exactly once on failure, then fails **closed** (`{ error: ... }`) — replacing the previous fail-open behavior inherited from migration 0018. This applies uniformly to all 8 kinds.
- The quota-exceeded 429 response now names the specific capped feature and its limit (e.g. "Today's Photo food scans (30/day) are used up — try again tomorrow, or log this meal manually."), with the manual-logging hint reserved for `food_photo`/`rambler_food` per the plan.
- 3 remaining KB-03 brand strings renamed in `index.ts`: `"Gemini is not configured on the server."` → `"Herculex AI is not configured on the server."`; `"Unsupported Gemini analysis kind."` → `"Unsupported Herculex AI analysis kind."`; `"Gemini analysis failed. Please try again."` → `"Herculex AI analysis failed. Please try again."`. The 2 Pitfall-1 sentinel strings, the `processor: "Google Gemini"` privacy field, and every D-17-protected identifier (`GeminiKind`, `callGemini`, `geminiModel`/`geminiFallbackModel`, existing comments) are verified untouched via `git diff`.
- `usage_test.ts` (new): 3 passing `Deno.test` blocks covering the disallowed-result passthrough, fail-closed-after-one-retry (asserts the RPC was called exactly twice), and `limitForKind` tiering/fallback.
- KB-04 non-regression confirmed: `flutter test test/hercul_engine_test.dart` — 25/25 passing, file untouched by this plan.

## Task Commits

1. **Task 1: Write migration 0021_ai_usage_bump_per_kind.sql** — `83c7326` (feat)
2. **Task 2: Per-kind quota enforcement, fail-closed retry, kind-specific messages, KB-03 index.ts renames** — `f6478d0` (test, RED), `9ba7b05` (feat, GREEN)
3. **Task 3: Confirm Hercul non-regression, then push migration 0021 to the live database** — `cfa861d` (fix: drop+recreate instead of create-or-replace, found when the first push attempt failed), then `npx supabase db push --include-all --yes` against `ldzgyzigvbwofbswitrv` — all 4 pending migrations applied, confirmed via `npx supabase migration list` (local == remote across the board)

## Files Created/Modified
- `supabase/migrations/0021_ai_usage_bump_per_kind.sql` — kind-scoped `ai_usage_bump`, dropped default limit param; `0018` untouched
- `supabase/functions/gemini-analyze/index.ts` — `kindLimits`/`limitForKind()`/`kindDisplayNames`, rewritten `bumpUsage()` (fail-closed, one retry, 3-arg signature, both exported), updated call site, 3 KB-03 string renames
- `supabase/functions/gemini-analyze/usage_test.ts` — 3 `Deno.test` blocks for `bumpUsage`/`limitForKind`

## Decisions Made
- Changed `bumpUsage()`'s `SUPABASE_URL`/`SUPABASE_SERVICE_ROLE_KEY` reads from module-load-time consts to per-call `Deno.env.get()` reads (documented as a Rule 3 deviation below) — this was necessary for `usage_test.ts` to exercise the real fetch/retry code path at all, since the plan's Task 2 `<behavior>` explicitly requires testing that path with a mocked `fetch`.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Moved SUPABASE_URL/SUPABASE_SERVICE_ROLE_KEY reads from module-load-time consts into `bumpUsage()`'s body**
- **Found during:** Task 2, while making `usage_test.ts`'s Test 1 and Test 2 pass
- **Issue:** The pre-existing code read `supabaseUrl`/`serviceRoleKey` as top-level `const`s evaluated once at module import. `Deno.env.set()` calls inside a `Deno.test()` body run at test-execution time, strictly after the module has already been imported and its top-level consts already computed as `undefined` in the bare test environment (no `SUPABASE_URL` set). This meant `bumpUsage()` always took the "not configured" branch and the plan's required fetch-mocking tests (Test 1: 200 response passthrough; Test 2: fail-closed after one retry) could never reach the `fetch()` call at all — structurally untestable as originally read.
- **Fix:** `bumpUsage()` now calls `Deno.env.get("SUPABASE_URL")`/`Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")` itself, at the top of the function body, on every invocation. `usage_test.ts` sets both via `Deno.env.set()` once at the top of the test file (before any `Deno.test()` runs). No other code in `index.ts` referenced these two values (confirmed via `git diff` — only `bumpUsage()` used them), so this is a self-contained, zero-behavior-change-in-production refactor: production still reads the same env vars, just at call time instead of import time (a Deno edge function's `Deno.env.get()` is not meaningfully more expensive per-call, and neither value changes during an instance's lifetime).
- **Files modified:** `supabase/functions/gemini-analyze/index.ts`, `supabase/functions/gemini-analyze/usage_test.ts`
- **Verification:** `deno test -A supabase/functions/gemini-analyze/usage_test.ts` — 3/3 passing; `deno test -A supabase/functions/gemini-analyze/` (whole directory) — 11/11 passing; `deno check supabase/functions/gemini-analyze/index.ts` — 0 errors.
- **Committed in:** `9ba7b05` (Task 2 GREEN commit)

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** Necessary to make the plan's own required test behavior achievable at all; no production behavior change, no scope creep.

### Note on a pre-existing acceptance-criteria mismatch (not a deviation, not fixed)

Task 2's acceptance criteria state `grep -c "Gemini server authorization failed" supabase/functions/gemini-analyze/index.ts` should return `1`. It actually returns `2` — but this is **pre-existing and untouched by this plan**: the file has always contained both the literal sentinel string (line ~846: `"Gemini server authorization failed. Configure GEMINI_API_KEY..."`) and an unrelated `.startsWith("Gemini server authorization failed")` check a few lines earlier (line ~426) that happens to contain the same substring. `git diff` confirms neither line was touched by this plan's edits. Not fixed because CLAUDE.md/plan scope boundary excludes pre-existing, out-of-scope issues; flagging here per the deviation-rules "scope boundary" guidance rather than silently ignoring it.

## Issues Encountered

**Migration 0021 as originally written failed to apply to the live database.** The plan's Task 1 called for `create or replace function` to drop `p_daily_limit`'s `default 50`, but Postgres rejects removing a parameter default that way (`SQLSTATE 42P13: cannot remove parameter defaults from existing function`). The first `supabase db push --include-all --yes` attempt failed cleanly at statement 0 with no partial state (confirmed via `npx supabase migration list` immediately after — all 4 migrations still showed an empty Remote column). Fixed by switching to `drop function if exists ... ; create function ...`, and re-adding 0018's `revoke execute ... from public, anon, authenticated` (a drop+recreate resets grants to the Postgres default of PUBLIC-executable, unlike `create or replace` which preserves them) — committed as `cfa861d`. Re-running the push then succeeded; `migration list` afterward shows local == remote for all migrations including `0021` and the 3 previously-pending v41/v43/v44 ones.

## User Setup Required
None - no external service configuration required. The live database push (Task 3) was completed by the orchestrator with explicit user approval before running `supabase db push`.

## Next Phase Readiness
- Per-kind quota enforcement and the KB-03 brand sweep are complete, tested, and merged (commits `83c7326`, `f6478d0`, `9ba7b05`, `cfa861d`).
- `ai_usage_bump` migration `0021` is live on `ldzgyzigvbwofbswitrv`, along with 3 previously-outstanding, unrelated migrations (v41/v43/v44 — additive `add column if not exists` changes matching local Drift schema versions already shipped in Phases 16/18/21, so this also closes a real pre-existing local/remote schema drift, not just a bookkeeping catch-up).
- No blockers for Phase 27/28/29/PHYS-07.

---
*Phase: 26-herculex-ai-knowledge-base-brand-unification*
*Completed: 2026-09-28*

## Self-Check: PASSED
- FOUND: supabase/migrations/0021_ai_usage_bump_per_kind.sql
- FOUND: supabase/functions/gemini-analyze/usage_test.ts
- FOUND: .planning/phases/26-herculex-ai-knowledge-base-brand-unification/26-02-SUMMARY.md
- FOUND commit: 83c7326 (Task 1)
- FOUND commit: f6478d0 (Task 2 RED)
- FOUND commit: 9ba7b05 (Task 2 GREEN)
- FOUND commit: 33a7d72 (SUMMARY)
