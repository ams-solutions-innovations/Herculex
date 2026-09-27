---
phase: 26
slug: herculex-ai-knowledge-base-brand-unification
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-09-27
---

# Phase 26 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | `Deno.test` (`jsr:@std/assert@1`) for `supabase/functions/gemini-analyze/`; `flutter_test` for `lib/` |
| **Config file** | none — `deno test <path>` works directly, verified live during research |
| **Quick run command** | `deno test supabase/functions/gemini-analyze/` (whole dir) or `flutter test test/hercul_engine_test.dart` for the KB-04 non-regression check |
| **Full suite command** | `deno test supabase/functions/gemini-analyze/` then `flutter analyze` then `flutter test` (redirect to file, not `tail`, per CLAUDE.md) |
| **Estimated runtime** | ~1 min (Deno) + ~1 min (analyze) + ~2 min (flutter test) |

---

## Sampling Rate

- **After every task commit:** `deno test supabase/functions/gemini-analyze/` (fast, no network) and `flutter analyze` for any touched Dart file.
- **After every plan wave:** Full `deno test` dir + `flutter test` (redirected to file per CLAUDE.md, `tr '\r' '\n'` before grepping) + a manual `grep -rn "Gemini"` sweep against the Brand Rename Inventory in RESEARCH.md.
- **Before `/gsd:verify-work`:** Full suite must be green, plus human confirmation that `supabase db push`'s dry-run output for the new migration was reviewed (3 unrelated pending migrations — v41/v43/v44 — will also show up; don't apply this phase's fix blind to that, per Pitfall 5).
- **Max feedback latency:** ~5 seconds (no network-dependent tests in this phase's suite).

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 26-01-W0 | TBD | 0 | KB-01 | V13 | `knowledge_base.ts` exports 4 segments + `KNOWLEDGE_VERSION`; `system_instruction` included in request body when provided | unit | `deno test supabase/functions/gemini-analyze/knowledge_base_test.ts` | ❌ W0 | ⬜ pending |
| 26-02-W0 | TBD | 0 | KB-02 | — | Every one of 8 kinds' response includes `provenance.modelVersion`; grounded/fallback paths report the correct model | unit | `deno test supabase/functions/gemini-analyze/index_test.ts` | ❌ W0 | ⬜ pending |
| 26-03 | TBD | — | KB-03 | — | No literal "Gemini"/"Gemini AI" substring remains except the one consent string | manual | `grep -rn "Gemini" lib/ supabase/functions/gemini-analyze/index.ts` reviewed against Brand Rename Inventory | N/A — manual by design | ⬜ pending |
| 26-04 | TBD | — | KB-04 (non-regression) | — | `HerculSignals.all` and the closed-vocabulary rejection test still pass, unmodified | unit (existing) | `flutter test test/hercul_engine_test.dart` | ✅ exists | ⬜ pending |
| 26-05-W0 | TBD | 0 | KB-05 | V4 | `ai_usage_bump` sums per-kind not globally; `bumpUsage()` fails closed after 2 failed attempts; kind-specific error messages | unit | `deno test supabase/functions/gemini-analyze/usage_test.ts` | ❌ W0 | ⬜ pending |
| 26-06-W0 | TBD | 0 | Pitfall 3 (brand data consistency) | — | A food photo logged with a Gemini response missing `brand` (or a manually-constructed result) stores `brand: 'Herculex AI'` | unit | `flutter test` (new/extended `gemini_food_analyzer_service_test.dart`) | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `supabase/functions/gemini-analyze/knowledge_base_test.ts` — covers KB-01 (segment exports, `KNOWLEDGE_VERSION` format, `system_instruction` body shape)
- [ ] `supabase/functions/gemini-analyze/index_test.ts` — covers KB-02 (no test file exists for `index.ts` today; extract `limitForKind()`, `bumpUsage()`, and the provenance-envelope construction into testable pure functions — the D-05/D-12/D-13 refactor already requires this)
- [ ] `supabase/functions/gemini-analyze/usage_test.ts` — covers KB-05's `bumpUsage()` fail-closed-with-retry behavior via a mocked/stubbed `fetch`
- [ ] `gemini_food_analyzer_service_test.dart` (or equivalent, does not appear to exist today) — covers Pitfall 3's four-site `brand` default consistency

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| No user-visible "Gemini" string remains (except the one consent string) | KB-03 | D-20 explicitly declines an automated regression guard; a precise guard would need to distinguish string-literal UI text from legitimate identifiers/kind-values/docs | `grep -rn "Gemini" lib/ supabase/functions/gemini-analyze/index.ts`, review every hit against the Brand Rename Inventory table in RESEARCH.md, confirm each is Rename (done)/Keep (consent string)/Untouched (identifier or Pitfall-1 sentinel) |
| `supabase db push` dry-run reviewed before real deploy | KB-05 | Shared, remote, already-in-production database; 3 unrelated pending migrations (v41/v43/v44) will also appear in the same push (Pitfall 5) — human must confirm before applying | Run `supabase db push --dry-run` (or equivalent preview), confirm `0021_ai_usage_bump_per_kind.sql` plus the 3 pending timestamped migrations are all expected, then push for real |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references (knowledge_base_test.ts, index_test.ts, usage_test.ts, brand-default test)
- [ ] No watch-mode flags
- [ ] Feedback latency < 5s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
