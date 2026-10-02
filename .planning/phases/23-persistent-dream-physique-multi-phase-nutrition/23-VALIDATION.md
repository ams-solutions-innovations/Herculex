---
phase: 23
slug: persistent-dream-physique-multi-phase-nutrition
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-10-02
---

# Phase 23 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Source of truth: `23-RESEARCH.md` § Validation Architecture.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | `flutter_test` (SDK 3.44.8); Deno test for edge functions |
| **Config file** | none (standard `test/` discovery); `tool/check_structure.dart` for layout |
| **Quick run command** | `flutter test test/features/physique` |
| **Full suite command** | `flutter test > test_output.txt 2>&1` (redirect, never pipe to `tail`; `tr '\r' '\n'` before grepping) |
| **Static gates** | `flutter analyze` (0 errors), `dart run tool/check_structure.dart`, `dart format lib test tool` |
| **Edge function** | `deno test --allow-env --allow-net supabase/functions/gemini-analyze/` |
| **Estimated runtime** | quick ~20s · full ~2–3 min · analyze ~30–60s |

---

## Sampling Rate

- **After every task commit:** `flutter test test/features/physique` plus the touched test file; `flutter analyze <touched paths>`
- **After every plan wave:** Compat suite (below), `test/migration_test.dart`, `test/auth/account_deletion_test.dart`, `deno test` for edge-function waves, full `flutter analyze`, `dart run tool/check_structure.dart`
- **Before `/gsd:verify-work`:** Full `flutter test` green (>= baseline recorded at execution start + new tests, 0 failures), 0 analyzer errors, `check_structure` passes, Deno tests pass
- **Max feedback latency:** ~60 seconds per task

Compat suite: `flutter test test/dream_physique_summary_repository_test.dart test/dream_physique_summary_card_test.dart test/dream_physique_nutrition_recommendation_test.dart test/dream_physique_nutrition_direction_card_test.dart test/dream_physique_priorities_view_test.dart test/block_builder_view_test.dart`

---

## Per-Task Verification Map

Task IDs are assigned by the planner; rows are keyed by requirement until plans exist.

| Req | Behavior | Test Type | Automated Command | File Exists | Status |
|-----|----------|-----------|-------------------|-------------|--------|
| PHYS-01 | v46→v47 migration replay; four tables; sync_uuid unique indexes; outbox row on insert | migration | `flutter test test/migration_test.dart test/physique_sync_registration_test.dart` | ❌ W0 (registration) | ⬜ pending |
| PHYS-01 | Supabase SQL parity: drift columns ⊆ Postgres, RLS, triggers, realtime | text-level | `flutter test test/physique_supabase_migration_test.dart` | ❌ W0 | ⬜ pending |
| PHYS-01 | Legacy migrator: idempotent, skips missing files, deletes originals only after commit | unit | `flutter test test/features/physique/physique_legacy_migrator_test.dart` | ❌ W0 | ⬜ pending |
| PHYS-02 | Sanitiser strips EXIF (GPS/make/model), bakes orientation, preserves size; unreadable → typed error | unit | `flutter test test/features/physique/physique_photo_sanitizer_test.dart` | ❌ W0 | ⬜ pending |
| PHYS-02 | Blur via fake `FaceDetectorPort`; zero faces reported, not silently "blurred" | unit | same file | ❌ W0 | ⬜ pending |
| PHYS-02 | Account wipe removes physique photo files and tables | integration | `flutter test test/auth/account_deletion_test.dart` | ✅ extend | ⬜ pending |
| PHYS-03 | Tempo caps preset by % bw/week; plannedWeeks; first phase matches old recommender; draft invariants | unit | `flutter test test/features/physique/physique_roadmap_test.dart test/features/physique/physique_tempo_policy_test.dart` | ❌ W0 | ⬜ pending |
| PHYS-04 | Eligibility matrix (age <18/null/18, low confidence, unknown) × phases; `DietPhaseCalculator.apply` default unchanged | unit | `flutter test test/features/physique/physique_guardrails_test.dart test/diet_phase_test.dart` | ❌ W0 (guardrails) | ⬜ pending |
| PHYS-04 | Editor blocks restricted phases at both call sites; deep-link `extra` coerced | widget | `flutter test test/features/nutrition` | ✅ extend | ⬜ pending |
| PHYS-05 | Exit evaluator per phase via fake `Clock`; advance offer; postpone; never writes targets | unit | `flutter test test/features/physique/roadmap_exit_criteria_test.dart` | ❌ W0 | ⬜ pending |
| PHYS-05 | Progress screen shows active phase, "N of M", time in phase, exit criteria | widget | `flutter test test/features/physique/physique_progress_view_test.dart` | ❌ W0 | ⬜ pending |
| PHYS-06 | 7-day cap: `CheckInTooSoonException`, day-7 allowed, DST, soft-delete still counts, per-goal isolation, concurrent submits → one wins | unit | `flutter test test/features/physique/physique_assessment_repository_test.dart` | ❌ W0 | ⬜ pending |
| PHYS-06 | Button disabled with "Next check-in available <date>" | widget | progress view test | ❌ W0 | ⬜ pending |
| PHYS-07 | Verdict classifier truth table; weight trend may only downgrade; no `%` in rendered verdict | unit+widget | `flutter test test/features/physique/check_in_verdict_test.dart` | ❌ W0 | ⬜ pending |
| PHYS-07 | Edge function: consent for `physique_checkin`, per-kind quota, normaliser rejects percent fields, provenance fields | Deno | `deno test --allow-env --allow-net supabase/functions/gemini-analyze/` | ❌ W0 (`physique_checkin_test.ts`) | ⬜ pending |
| PHYS-07 | Dart parser tolerates absent confidence (`unknown`), rejects malformed band | unit | `flutter test test/features/physique/physique_checkin_service_test.dart` | ❌ W0 | ⬜ pending |
| PHYS-08 | Series builders: weight trend+band, e1RM per canonical lift, level series; no `features/gamification/` import | unit | `flutter test test/features/physique/physique_series_test.dart` | ❌ W0 | ⬜ pending |
| PHYS-08 | Charts render with empty/sparse data | widget | progress view test | ❌ W0 | ⬜ pending |
| Layout | Files ≤600 lines, domain purity, routes via `AppRoutes` | static | `dart run tool/check_structure.dart` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/features/physique/` — all pure-Dart domain tests listed above
- [ ] `test/physique_sync_registration_test.dart`, `test/physique_supabase_migration_test.dart` — copy the tdee pair, four tables
- [ ] `test/support/` — fake `FaceDetectorPort` and synthetic-EXIF JPEG fixture builder (ML Kit cannot run under `flutter test`)
- [ ] Fake `Clock` helper — check `test/support/` first, create only if absent
- [ ] `supabase/functions/gemini-analyze/physique_checkin_test.ts`

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Real-device face blur on a rotated sample photo | PHYS-02 | ML Kit needs a device; not runnable under `flutter test` | Take a rotated portrait, enable blur, confirm faces blurred and orientation correct in the stored file |
| Supabase v47 push + read-only verification queries | PHYS-01 | Remote DB change is human-gated (as in 27-10) | Apply the new `supabase/migrations/NNNN_*.sql`, then confirm four tables, RLS policies and realtime publication |
| iOS `pod install` / run with face detection | PHYS-02 | Not verifiable on Windows host; iOS target vs ML Kit minimum unresolved | On macOS: `pod install`, run on device/simulator, confirm build and detection |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 60s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
