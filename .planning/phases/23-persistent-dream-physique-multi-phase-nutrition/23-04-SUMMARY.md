---
phase: 23-persistent-dream-physique-multi-phase-nutrition
plan: 04
subsystem: api
tags: [supabase-edge-function, gemini, deno, physique, consent]

requires:
  - phase: 26
    provides: per-kind quota pattern, knowledge_base.ts (core, KNOWLEDGE_VERSION)
provides:
  - physique_checkin kind on gemini-analyze (band, confidence, reason, limitations, provenance)
  - shared imageConsentError gate for dream_physique and physique_checkin
  - optional currentBfRangeMin/Max and assessmentConfidence on dream_physique
affects: [23-05, 23-08, 23-17]

tech-stack:
  added: []
  patterns: [shared consent gate before quota, whitelisting normaliser with percentage stripping]

key-files:
  created:
    - supabase/functions/gemini-analyze/physique_checkin_test.ts
  modified:
    - supabase/functions/gemini-analyze/index.ts
    - supabase/functions/gemini-analyze/prompts.ts
    - supabase/functions/gemini-analyze/prompts_test.ts
    - supabase/functions/gemini-analyze/usage_test.ts

key-decisions:
  - "Consent gate is one exported function covering every image kind, run before bumpUsage"
  - "Normaliser fails closed: invalid confidence becomes low; unknown keys dropped; percentages stripped"

requirements-completed: []

duration: 15min
completed: 2026-10-02
---

# Phase 23 Plan 04: Physique check-in edge function Summary

**gemini-analyze gains a consent-gated, quota-limited `physique_checkin` kind returning a percentage-free direction band with provenance, and Dream Physique now reports a BF range and assessment confidence.**

## Accomplishments
- `physiqueCheckinPrompt` with sanitised phase/weeks/trend context and a closed JSON contract; `dreamPhysiquePrompt` extended additively.
- `imageConsentError` replaces the inline dream_physique check; rejects before quota is consumed.
- `normalizePhysiqueCheckinResult` clamps/swaps band, strips percentages, caps limitations; `normalizeDreamPhysiqueResult` passes valid optional BF range/confidence.
- Response carries `provenance { modelVersion, knowledgeVersion }` and `Cache-Control: no-store`; no DB writes.
- 27 Deno tests pass.

## Task Commits
1. Task 1: prompts - 93dde0d
2. Task 2: index.ts handler, normalisers, tests - 75db3ba

## Deviations from Plan
None - plan executed exactly as written.

## Notes
- Function NOT deployed (Plan 17, human-gated; must precede client release).
- PHYS-07 and PHYS-04 are server halves only; requirements left unticked for the orchestrator.

## Self-Check: PASSED
