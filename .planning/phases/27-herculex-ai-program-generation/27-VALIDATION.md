---
phase: 27
slug: herculex-ai-program-generation
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-09-29
---

# Phase 27 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | `flutter_test` (widget/unit); Deno test runner for the Supabase Edge Function side |
| **Config file** | none — standard `flutter test` discovery over `test/` |
| **Quick run command** | `flutter test test/program_guardrails_test.dart test/block_builder_view_test.dart` |
| **Full suite command** | `flutter test` (redirect to file per CLAUDE.md — do not pipe to `tail`) |
| **Estimated runtime** | ~2 min (full suite, per CLAUDE.md) |

---

## Sampling Rate

- **After every task commit:** Run the targeted test file for the touched area (e.g. `flutter test test/program_guardrails_test.dart`)
- **After every plan wave:** Run `flutter test test/block_builder_view_test.dart test/program_review_view_test.dart test/program_guardrails_test.dart`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 120 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| TBD | TBD | TBD | AIP-01 | — | `ProgramBuildMode` gains a 4th value; builder offers it | widget | `flutter test test/block_builder_view_test.dart` | ✅ extend existing | ⬜ pending |
| TBD | TBD | TBD | AIP-02 | V5 | Brief never contains exercise IDs/sets/reps/load/RPE/tempo/time-caps; `SmartProgramPlanner` unchanged as selector | unit | `flutter test test/program_brief_test.dart` | ❌ Wave 0 | ⬜ pending |
| TBD | TBD | TBD | AIP-03 | V5 | Brief validated against schema + guardrails; rejected briefs fall back | unit | `flutter test test/program_brief_test.dart test/program_guardrails_test.dart` | ❌ Wave 0 (guardrails file exists, needs new group) | ⬜ pending |
| TBD | TBD | TBD | AIP-04 | V4 | AI program lands in `ProgramReviewView` archived/unactivated, shows per-day rationale, requires `_confirm()` | widget | `flutter test test/program_review_view_test.dart` | ✅ extend existing | ⬜ pending |
| TBD | TBD | TBD | AIP-05 | V5 | Degrades to Smart/Guided when offline/unconfigured/over-quota | unit/widget | new test on `HerculexAiBriefService` | ❌ Wave 0 | ⬜ pending |
| TBD | TBD | TBD | D-07 (regression) | — | `_create()`'s inline Max-Effort/6-day-PPL checks keep working for manual/smart/guided after extraction | widget | extend `test/block_builder_view_test.dart` — characterization tests BEFORE refactor | ❌ Wave 0 — blocking for the guardrail-extraction task | ⬜ pending |

*Task IDs, plan IDs, and wave numbers are TBD until the planner assigns them — the planner/checker should populate this table from the rows above once PLAN.md files exist.*

---

## Wave 0 Requirements

- [ ] `test/program_brief_test.dart` — new file covering `ProgramBrief.fromJson` strict enum rejection (D-02), exercise-field prohibition (AIP-02), and guardrail-triggered rejection message (D-05)
- [ ] `test/block_builder_view_test.dart` — extend with D-07 characterization tests for the two existing inline `_create()` throw conditions (Max-Effort-per-week, 6-day-PPL-with-Max-Effort), for each of the 3 existing modes, written **before** the guardrail extraction begins
- [ ] `test/program_guardrails_test.dart` — extend with a new test group for `ProgramGuardrails`'s new pre-materialization/configuration-level validation method (D-06/D-07)
- [ ] Supabase Edge Function test: a `program_brief` normalizer unit test in Deno's test runner (mirrors `usage_test.ts`'s pattern for `bumpUsage`) covering `normalizeProgramBriefResult()`'s unknown-enum-rejection behavior server-side

---

## Manual-Only Verifications

*None — all phase behaviors identified so far have automated verification paths (see Per-Task Verification Map). If the planner identifies a UI-only interaction that can't be asserted via `flutter_test` (e.g. a live Gemini call requiring a real API key), add it here.*

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 120s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
