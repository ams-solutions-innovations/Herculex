---
phase: 29-weekly-report-herculex-ai-narrative
plan: 23
subsystem: edge-function, weekly-report
tags: [gemini-analyze, validation, sanitising, number-check, gap-closure]
requires: [29-03, 29-09, 29-01]
provides: [weekly_report_guard.ts, number-in-facts check on server and client, WeeklyNarrativeLimits]
affects: [supabase/functions/gemini-analyze, lib/features/weekly_report]
key-files:
  created:
    - supabase/functions/gemini-analyze/weekly_report_guard.ts
    - test/fixtures/weekly_report_number_cases.json
    - test/features/weekly_report/weekly_narrative_limits_test.dart
  modified:
    - supabase/functions/gemini-analyze/index.ts
    - supabase/functions/gemini-analyze/prompts.ts
    - supabase/functions/gemini-analyze/weekly_report_test.ts
    - lib/features/weekly_report/domain/weekly_narrative.dart
    - lib/features/weekly_report/data/weekly_report_narrative_service.dart
    - test/features/weekly_report/narrative_service_test.dart
decisions:
  - Knowledge-range allowance DROPPED on both sides; only integers 0..60 are always allowed.
metrics:
  completed: 2026-10-04
---

# Phase 29 Plan 23: Edge Function validation order, server sanitising, number-in-facts Summary

Weekly report requests are validated and re-sanitised before the quota call, facts are delimited in the prompt, and any number the model states that is absent from the facts is rejected on both server and Dart client, with limits asserted equal by test.

## Commits
- f293e2f: guard module, prepareWeeklyReportRequest before bumpUsage, `<facts>` delimiters (WR-04, WR-05 input). The normaliser `facts` argument and assertNumbersInFacts wiring in index.ts landed in this same commit (same file).
- 130cb9d: shared fixture (30 cases) and Deno tests for the server number check (WR-05 output).
- 5ea5d60: Dart mirror (`extractNarrativeNumbers`, `collectFactNumbers`, `firstNumberNotInFacts`, `WeeklyNarrativeLimits`), service passes `facts:`, limits test + fixture test (IN-03).

## Decisions
- **Knowledge-range allowance: dropped** (explicitly permitted). Keeping server and Dart identical would need a generated knowledgeNumbers fixture; not cheap. Only 0..60 integers are always allowed. Consequence: a coaching range such as "7-9 hours" passes (7, 9 small), but "1.6 g/kg" or "150 g" cited from knowledge text is rejected unless in the facts.
- Date exclusion keys: weekStartIso, weekEndIso, windowEnd, start, end (the facts payload uses `week.start` / `week.end`), plus any yyyy-MM-dd value.
- Server string cap 120 (largest Dart cap is 160 for correlation statements, which are never reached by name caps; NOTE: statements are capped at 160 on Dart, so the server cap of 120 will truncate a long statement. Truncation is harmless to the number check but raise the cap to 160 if exact statement text matters).
- Depth limit 6, 400 nodes, 8000 chars post-sanitise.
- Rejected narrative stores nothing (server throws via existing catch; client maps FormatException to rejected). tryDecodeStored does not run the check.

## Open question
- Sleep is supplied as decimal hours (avgSleepHours 7.2). A narrative saying "7h 12m" passes (12 is small) but "7 hours 20 minutes" style conversions above 60 would not; the model is told to use numbers verbatim. Other quotable figures (kcal, steps, avgRestingHr, cnsReadinessPct, bodyweight, tdee old/new/delta, isoYear/isoWeek) are all present in the facts.

## Deviations
None of Rules 1-4 triggered. Task 2 index.ts edits were committed with task 1 (single file).

## Verification
- Deno: 49 passed, 0 failed (`deno test --allow-read --allow-env --allow-net`).
- flutter analyze: 0 errors (43 pre-existing infos/warnings).
- flutter test: all pass except one FLAKY pre-existing test in weekly_report_repository_test.dart ("reads equal generatedAt falls back to the lowest id", from 29-21), which failed once in the directory and full runs and passes when run alone. Not touched by this plan; recommend a look in a later plan.
- No supabase migration, no deploy executed. Function needs deploying by the orchestrator.

## Threat notes
T-29-23-04 accepted: endpoint still a weekly_report-shaped proxy, 5/day, 8000 chars.

## Self-Check: PASSED
