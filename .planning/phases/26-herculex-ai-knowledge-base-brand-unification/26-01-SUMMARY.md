---
phase: 26-herculex-ai-knowledge-base-brand-unification
plan: 01
subsystem: api
tags: [deno, supabase-edge-functions, gemini, prompt-engineering]

# Dependency graph
requires: []
provides:
  - "knowledge_base.ts with 4 named coaching-mentality corpus segments (core/programming/nutrition/recovery) + KNOWLEDGE_VERSION"
  - "buildSystemInstruction() helper wiring an optional systemInstruction into generate()'s REST body as system_instruction"
  - "modelVersion threaded through generate()/generateJson()/generateGroundedJson(), surfaced as provenance.modelVersion in all 8 Gemini kind response envelopes"
affects: [27-ai-program-generation, 28-knowledge-base-content, 29-weekly-report, phys-07]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "One-file/named-export module pattern (mirrors prompts.ts) for corpus/prompt content"
    - "Deno.test + jsr:@std/assert@1 with globalThis.fetch stubbing in try/finally for edge-function unit tests"

key-files:
  created:
    - supabase/functions/gemini-analyze/knowledge_base.ts
    - supabase/functions/gemini-analyze/knowledge_base_test.ts
    - supabase/functions/gemini-analyze/index_test.ts
  modified:
    - supabase/functions/gemini-analyze/index.ts

key-decisions:
  - "No kind consumes a real corpus segment yet (D-04) — systemInstruction wiring is provably testable but stays undefined at every existing call site this phase"
  - "provenance.modelVersion added to all 8 kinds; knowledgeVersion intentionally omitted (D-06), deferred to a later phase"

patterns-established:
  - "provenance: { modelVersion } as a top-level response envelope key, sourced from generate()'s usedModel (primary geminiModel, or geminiFallbackModel on 429/503 retry)"

requirements-completed: [KB-01, KB-02]

# Metrics
duration: 5min
completed: 2026-09-27
---

# Phase 26: Herculex AI Knowledge Base & Brand Unification — Plan 01 Summary

**knowledge_base.ts corpus + provenance.modelVersion threaded through generate()/generateJson()/generateGroundedJson() into all 8 Gemini kind response envelopes**

## Performance

- **Duration:** ~5 min (18:21:39–18:26:05 UTC+2)
- **Started:** 2026-09-27T18:21:39+02:00
- **Completed:** 2026-09-27T18:26:05+02:00
- **Tasks:** 3 completed
- **Files modified:** 4

## Accomplishments
- `knowledge_base.ts` exports `core`, `programming`, `nutrition`, `recovery`, and `KNOWLEDGE_VERSION = "kb-2026.10-1"`, mirroring `prompts.ts`'s style; never imported by `lib/`.
- `buildSystemInstruction()` exported and threaded into `generate()`'s request body as a `system_instruction` sibling of `contents`, with zero behavior change to any existing kind.
- `generate()`/`generateJson()`/`generateGroundedJson()` all return `modelVersion`, correctly reporting the fallback model on a 429/503 retry.
- All 8 Gemini kinds' JSON responses now include `provenance: { modelVersion }`; none include `knowledgeVersion` yet.

## Task Commits

Each task was committed atomically (TDD red/green pairs for Tasks 1 and 2):

1. **Task 1: Create knowledge_base.ts + knowledge_base_test.ts** — `e6f837e` (test), `277d5c9` (feat)
2. **Task 2: Thread systemInstruction + modelVersion through generate()/generateJson()/generateGroundedJson()** — `00281af` (test), `f58db1f` (feat)
3. **Task 3: Wire provenance.modelVersion into all 8 kind response envelopes** — `8107de7` (feat)

## Files Created/Modified
- `supabase/functions/gemini-analyze/knowledge_base.ts` — 4 coaching-mentality corpus segments + KNOWLEDGE_VERSION
- `supabase/functions/gemini-analyze/knowledge_base_test.ts` — 3 Deno.test blocks covering segment shape, version format, and injection-safety
- `supabase/functions/gemini-analyze/index.ts` — `buildSystemInstruction()`, `modelVersion` threading, `provenance.modelVersion` in all 8 switch branches
- `supabase/functions/gemini-analyze/index_test.ts` — 3 Deno.test blocks covering `buildSystemInstruction()` shape and primary/fallback `modelVersion` reporting

## Decisions Made
None — followed plan as specified.

## Deviations from Plan
None - plan executed exactly as written.

## Issues Encountered
None during implementation. During orchestrator recovery (see below), `deno test` initially failed with `NotCapable` errors for env/net access — this is a permission-flag issue (the edge function calls `Deno.serve()` and `Deno.env.get()` at module load), not a code defect; running with `deno test -A` passes all 8 tests (5 pre-existing + 3 new... actually 3 knowledge_base + 3 index + 2 prompts = 8 total).

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- `knowledge_base.ts` corpus location and `provenance.modelVersion` envelope shape are ready for Phase 27/28/29/PHYS-07 to build on.
- No blockers.

---
*Phase: 26-herculex-ai-knowledge-base-brand-unification*
*Completed: 2026-09-27*
