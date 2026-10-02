---
phase: 23-persistent-dream-physique-multi-phase-nutrition
plan: 08
subsystem: ai-client
tags: [gemini, physique, checkin, dream-physique, guardrails]
requires: ["23-04", "23-05"]
provides:
  - PhysiqueCheckInBackend interface and physiqueCheckInBackendProvider
  - PhysiqueCheckInService (sanitised, percent-free CheckInEvidence plus provenance)
  - DreamPhysiqueAnalysisResult BF range and assessmentConfidence
affects: [23-check-in UI plans]
tech-stack:
  added: []
  patterns: [separate backend interface to avoid breaking existing fakes, defense-in-depth sanitising]
key-files:
  created:
    - lib/features/physique/data/physique_checkin_service.dart
    - test/features/physique/physique_checkin_service_test.dart
  modified:
    - lib/services/ai/gemini_backend_service.dart
    - lib/features/profile/data/dream_physique_service.dart
    - test/dream_physique_service_test.dart
    - test/gemini_backend_service_test.dart
decisions:
  - "analyzePhysiqueCheckIn lives on PhysiqueCheckInBackend, not GeminiBackend, so eight existing fakes compile unchanged"
  - "BF range parsing is tolerant: inverted, non-numeric or outside [3,70] gives null/null, never throws"
metrics:
  tasks: 2
  completed: 2026-10-02
---

# Phase 23 Plan 08: Physique check-in client service Summary

Client half of PHYS-07: a `physique_checkin` backend method on a separate interface, a service that validates and percent-strips the evidence, and tolerant BF range/confidence on Dream Physique results.

## Commits
- c14c2cb: PhysiqueCheckInBackend, provider, Dream Physique BF range/confidence, tests
- 1ce128f: PhysiqueCheckInService, typed failures, tests

## Behavior
- Consent refused before any backend call; baselines capped at 3; images sent as JPEG.
- Request context is exactly phase, weeksInPhase, weightTrendKgPerWeek.
- Band clamped via `CheckInBand.clamped`; malformed band gives `malformedResponse`; absent/unknown confidence gives `unknown`.
- Percentages and stray `%` stripped from reason; empty result uses the fallback text; limitations trimmed, capped at 3.
- "are used up" gives `quotaExhausted`; other errors give `unavailable`. No verdict logic and no repository dependency.

## Deviations from Plan
- Supabase request shape (`kind: physique_checkin`, base64 payload, privacyConsent) is not unit tested: `SupabaseGeminiBackend` requires a live `SupabaseClient` and `gemini_backend_service_test.dart` has no request-construction harness. The service test covers the recorded request image counts and context keys instead. Unconfigured-backend behavior is tested.
- Otherwise: none.

## Known Stubs
None.

## Requirements
PHYS-07 and PHYS-04 not marked complete: this is only the client data layer; UI and end-to-end wiring come in later plans.

## Self-Check: PASSED
Both commits exist; analyze clean on touched dirs; all listed test files pass (7 fake-backend files, 161 physique tests); none of the five unrelated fake test files were modified.
