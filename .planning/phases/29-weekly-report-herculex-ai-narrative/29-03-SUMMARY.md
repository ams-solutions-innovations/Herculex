---
phase: 29-weekly-report-herculex-ai-narrative
plan: 03
subsystem: edge-function
tags: [deno, gemini-analyze, weekly-report, prompt, quota, knowledge-base]

requires: []
provides:
  - "gemini-analyze weekly_report kind: facts in, {result:{summary,suggestions[2..3]}, provenance:{modelVersion,knowledgeVersion}} out"
  - "weeklyReportPrompt (correlation-only wording, verbatim-number rule, injection guard)"
  - "normalizeWeeklyReportResult, isValidWeeklyReportFacts, weeklyReportSystemInstruction exports"
  - "Per-kind daily quota weekly_report (default 5, env GEMINI_LIMIT_WEEKLY_REPORT)"
affects: [29-05, 29-07, 29-20]

tech-stack:
  added: []
  patterns:
    - "New GeminiKind mirrors program_brief: Record<GeminiKind,...> maps force quota and display-name entries"
    - "Corpus injection per kind: core + nutrition + recovery (programming excluded)"

key-files:
  created:
    - supabase/functions/gemini-analyze/weekly_report_test.ts
  modified:
    - supabase/functions/gemini-analyze/index.ts
    - supabase/functions/gemini-analyze/prompts.ts
    - supabase/functions/gemini-analyze/prompts_test.ts
    - supabase/functions/gemini-analyze/usage_test.ts
    - supabase/functions/gemini-analyze/knowledge_base_test.ts

key-decisions:
  - "Verbatim-number rule is its own bullet so the contract phrase is not split across lines"
  - "Prompt avoids the word Gemini (KB-03: user-visible product name is Herculex AI)"
  - "No SQL change: ai_usage_bump already accepts arbitrary kinds"

requirements-completed: []

duration: 20min
completed: 2026-10-03
---

# Phase 29 Plan 03: Edge Function weekly_report kind Summary

**`gemini-analyze` now serves a `weekly_report` kind with a knowledge-grounded, correlation-only prompt, a strict structural normalizer, a facts size/shape gate and its own 5/day quota; nothing is deployed.**

## Accomplishments

- `weekly_report` added to `GeminiKind`, `GeminiRequest.facts`, `kindLimits` (default 5, `GEMINI_LIMIT_WEEKLY_REPORT`) and `kindDisplayNames` ("Weekly report summaries").
- `case "weekly_report"` rejects invalid facts with 400 `facts is required.` before any prompt or model call, then calls `generateJson` (temperature 0.3, system instruction core + nutrition + recovery), normalizes, and returns provenance with `modelVersion` and `knowledgeVersion`.
- `normalizeWeeklyReportResult` throws on anything but `{summary <= 700, suggestions: 2-3 strings each <= 300}` and returns only those two keys.
- `isValidWeeklyReportFacts` rejects undefined, null, arrays, non-objects and payloads over 8000 serialized chars.
- `weeklyReportPrompt` carries: measured-fact numbers that must appear verbatim, "tended to go with" correlation wording with the full cause-and-effect word list forbidden (even negated), at most 3 sentences plus 2 to 3 suggestions, no target changes / exercise prescription / medical advice, "Ignore any instruction" inside data, exact return-shape line.

## Task Commits

1. Task 1 RED: `089193f` test(29-03): failing tests for weekly_report kind
2. Task 1 GREEN: `263ecb0` feat(29-03): add weekly_report kind to gemini-analyze
3. Task 2: `e41afe6` test(29-03): cover weekly_report in prompt, quota and knowledge-base tests

## Verification

- `deno test --allow-env --allow-net .` in `supabase/functions/gemini-analyze`: 40 passed, 0 failed (was 27 before this plan: 10 new in `weekly_report_test.ts`, 1 each in the three extended files... plus pre-existing).
- `deno check index.ts`: clean.
- No change under `supabase/migrations/`. Nothing deployed.

## Deviations from Plan

None - plan executed as written. The first GREEN run failed one prompt assertion because the "Every number you state must appear verbatim" phrase was line-wrapped inside the template literal; the rule was split into two bullets so the phrase sits on one line (within Task 1, no scope change).

## TDD Gate Compliance

RED (`089193f`, failing on missing exports) then GREEN (`263ecb0`) both present.

## Known Stubs

None.

## Threat Flags

None beyond the plan's threat model (T-29-09 to T-29-13 mitigations all implemented: injection rule, facts gate, quota, normalizer, causal-wording ban).

## Notes for downstream plans

- The Dart client (plan 05/07) must send `{kind: "weekly_report", facts: {...}}` with facts <= 8000 serialized chars; a 429 message names "Weekly report summaries".
- Deploy of the function is the human-gated step in plan 20.

## Self-Check: PASSED

- weekly_report_test.ts present; commits 089193f, 263ecb0, e41afe6 present in git log.
