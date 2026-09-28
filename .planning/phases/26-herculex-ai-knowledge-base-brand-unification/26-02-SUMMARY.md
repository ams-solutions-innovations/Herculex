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
  - "supabase/migrations/0021_ai_usage_bump_per_kind.sql — kind-scoped ai_usage_bump RPC (written, NOT yet applied to the live project — blocked at Task 3 checkpoint)"
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
  - "Task 3 (push migration 0021 to the live ldzgyzigvbwofbswitrv project) is a blocking human-verify checkpoint per the plan's own frontmatter (autonomous: false) and explicit orchestrator instructions not to touch the live database from this worktree — execution stops here, unresolved"

requirements-completed: []
# KB-03 and KB-05 are code-complete and unit-tested (Tasks 1-2), but KB-05's
# must_haves truth "the corrected ai_usage_bump SQL is live on the remote
# Supabase project, not just written locally" is NOT yet satisfied — Task 3
# (the live db push) is a blocking checkpoint awaiting human confirmation.
# Do not mark KB-03/KB-05 complete in REQUIREMENTS.md until Task 3 lands.
# KB-04 (Hercul non-regression) was verified via `flutter test
# test/hercul_engine_test.dart` (25/25 passing) but is not "completed" by
# this plan — it is a pre-existing requirement this plan must not regress.

# Metrics
duration: ~25min (partial — stopped at Task 3 checkpoint)
completed: 2026-09-28
---

# Phase 26: Herculex AI Knowledge Base & Brand Unification — Plan 02 Summary (PARTIAL — checkpoint pending)

**Per-kind AI quota enforcement with fail-closed retry, kind-specific 429 messages, and the final 3 KB-03 brand-rename strings in `index.ts`; the corresponding `ai_usage_bump` SQL fix is written but NOT yet pushed to the live Supabase project — Task 3 is a blocking human-verify checkpoint**

## Performance

- **Duration:** ~25 min (Tasks 1-2 only; Task 3 not started — requires human confirmation before touching the live database)
- **Tasks:** 2 of 3 completed; Task 3 is a `checkpoint:human-verify` (`gate="blocking"`) that this plan's own frontmatter (`autonomous: false`) and the orchestrator's explicit instructions require stopping for
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
3. **Task 3: [BLOCKING] Confirm Hercul non-regression, then push migration 0021 to the live database** — NOT STARTED (checkpoint reached; see below)

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
None beyond the deviation documented above.

## User Setup Required

**Task 3 is a blocking `checkpoint:human-verify` (`gate="blocking"`) that this execution run stopped at, per the plan's own frontmatter (`autonomous: false`) and explicit orchestrator instructions not to touch the live Supabase database from this worktree.**

What was already verified automatically in this run:
- `flutter test test/hercul_engine_test.dart` — **25/25 passing** (KB-04 non-regression confirmed; file untouched by this phase).

What still requires a human, from a machine with `SUPABASE_ACCESS_TOKEN` configured (this worktree has neither the token nor network access to the live project):
1. Run `npx supabase link --project-ref ldzgyzigvbwofbswitrv` (never `jioesomepkauponjrena` — see `docs/supabase-migrations.md` and `CLAUDE.md`).
2. Run `npx supabase migration list` and confirm it shows exactly 4 pending migrations with an empty Remote column: this plan's `0021_ai_usage_bump_per_kind.sql`, plus 3 pre-existing unrelated ones (`20260913000000` v41, `20260915000000` v43, `20260916000000` v44 — already reviewed/merged in Phases 16/18/21; this is expected, not a defect).
3. Confirm the 3 unrelated pending migrations aren't accidentally reverting anything (sanity check only, not new review work).
4. Run `npx supabase db push --yes` and confirm it reports all 4 migrations applied successfully.
5. Only after that, KB-03 and KB-05 can be marked complete in `.planning/REQUIREMENTS.md` — do not mark them complete based on this plan's code/tests alone, since KB-05's must-have truth explicitly requires the SQL fix to be **live**, not just written.

## Next Phase Readiness
- Code and tests for per-kind quota enforcement and the KB-03 brand sweep are complete and merged into this worktree's history (commits `83c7326`, `f6478d0`, `9ba7b05`).
- **Blocker:** `ai_usage_bump` migration `0021` is not yet live on `ldzgyzigvbwofbswitrv`. Until it is pushed, the OLD (fail-open, cross-kind-summing) RPC remains authoritative in production — `index.ts`'s new `p_daily_limit: limit` 3-arg call will still work against the old signature (since `create or replace` in 0018 already made the 3rd arg non-defaulted... actually the OLD migration 0018 gave `p_daily_limit` a `default 50`, so a 3-arg call works identically against either version), but the *quota-scoping bug* (summing across all kinds) is NOT fixed until 0021 is pushed. This is the entire reason Task 3 exists and must not be skipped.
- No other blockers for Phase 27/28/29/PHYS-07, which depend on this phase's `knowledge_base.ts` (26-01) and brand-unification work, not specifically on the quota fix.

---
*Phase: 26-herculex-ai-knowledge-base-brand-unification*
*Completed: 2026-09-28 (partial — Task 3 checkpoint pending)*
