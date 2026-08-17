---
phase: 11
slug: gym-buddy-live-workout
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-08-17
---

# Phase 11 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Derived from `11-RESEARCH.md` § Validation Architecture (line 1103). That
> section is the authority for the full requirement→test map; this file is the
> execution contract.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | `flutter_test` (Flutter SDK 3.44.8) + `drift_dev` `SchemaVerifier` for migrations |
| **Config file** | none — `pubspec.yaml` `dev_dependencies` only; `analysis_options.yaml` for lints |
| **Quick run command** | `flutter test test/buddy/ test/migration_test.dart` |
| **Full suite command** | `flutter test` (baseline 538 passing / 4 skipped per STATE.md 2026-08-14) |
| **Live integration command** | `flutter test test/sync/live_buddy_test.dart --dart-define-from-file=.secrets/live_sync.json` (self-skips without credentials, mirroring `test/sync/live_round_trip_test.dart:36-48`) |
| **Estimated runtime** | ~15 s quick · ~90 s full offline · live suite network-bound |

---

## Sampling Rate

- **After every task commit:** `flutter test test/buddy/ test/migration_test.dart`
- **After every plan wave:** `flutter test` (full offline suite; live tests self-skip)
- **Before `/gsd:verify-work`:** full suite green **and** the live buddy suite green **twice in a row**, matching the bar `docs/rb02-sync-verification.md` set for RB-02
- **Max feedback latency:** 15 seconds

---

## Per-Task Verification Map

*Populated by the planner — every task must map to a row here or to a Wave 0 dependency.*

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| *pending planning* | — | — | BUD-01–06 | see RESEARCH § Security Domain | — | — | see RESEARCH § Validation Architecture | — | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

### Non-negotiable gates

Three tests are structural gates, not coverage. Each must be proven to **fail**
on a deliberately introduced violation before it counts as passing — the
precedent is `test/rep_tracker_write_boundary_test.dart` from Phase 10.

| Gate | Requirement | What it proves |
|------|-------------|----------------|
| `test/buddy/buddy_scope_boundary_test.dart` | BUD-03 | A `scope: mine` mutation produces zero publisher calls and zero log rows — the scope separation is structural, not a runtime boolean |
| `test/buddy/rls_frozen_test.dart` | BUD-05 | `supabase/migrations/0003_sync_rls.sql` is byte-identical to its pinned LF-normalised hash `f50be2f89c775245e2700c2e532065c7d89ea240da0ef5ed77ff14bb25697530`; asserts the file exists and is non-empty first so it cannot pass vacuously |
| `test/buddy/buddy_apply_test.dart -N "remove never discards logged sets"` | BUD-06 | The locked BUD-03 × BUD-06 resolution: a propagated `remove` unlinks rather than deletes when the local slot has logged work |

---

## Wave 0 Requirements

- [ ] `test/buddy/` directory — does not exist
- [ ] `test/buddy/fake_buddy_publisher.dart` — the seam every scope test drives; follow `test/sync/fake_sync_backend_service.dart`
- [ ] `test/support/two_device.dart` — extract the two-Drift-database harness from `test/sync/sync_payload_test.dart:22-26` rather than copy-pasting it
- [ ] `test/buddy/buddy_scope_boundary_test.dart` — BUD-03 structural gate
- [ ] `test/buddy/rls_frozen_test.dart` — BUD-05 pinned-hash gate
- [ ] `test/buddy/buddy_local_only_test.dart` — clone of `test/rep_local_only_test.dart`
- [ ] `test/buddy/buddy_two_device_test.dart` — BUD-02 / BUD-06 isolation
- [ ] `test/buddy/buddy_apply_test.dart` — idempotence, unresolvable refs, the remove gate
- [ ] `test/buddy/buddy_event_stream_test.dart` — ordering, gap-triggered backlog refetch
- [ ] `test/buddy/buddy_replay_test.dart` — cold-restart reconstruction
- [ ] `test/buddy/buddy_publisher_test.dart` — per-kind payloads
- [ ] `test/buddy/buddy_join_payload_test.dart` — QR encode/decode round trip
- [ ] `test/buddy/buddy_analytics_isolation_test.dart` — follow `test/analytics_soft_delete_test.dart`
- [ ] `test/sync/live_buddy_test.dart` — reuse the `_email`/`_email2` and `outsiderSkip()` idiom from `test/sync/live_round_trip_test.dart:445-456`
- [ ] `test/generated_migrations/schema_v29.dart` + `drift_schemas/drift_schema_v29.json` — generated, not hand-written
- [ ] `test/schema_v29_test.dart` — follow `test/schema_v28_test.dart`
- [ ] Framework install: **none needed**

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Two physical phones see the same exercise list within ~1 s of a change | BUD-03, BUD-04 | Cross-device latency cannot be observed from a single test process | Start a workout on phone A, share, scan on phone B, add an exercise with scope `both`, observe propagation |
| QR scan-to-join from the `+` menu | BUD-01 | Camera hardware | Display the QR on phone A, scan from phone B's `+` menu, confirm the joiner's session auto-starts and links |
| Supabase CLI migration applies cleanly against the live project | BUD-04, BUD-05 | Requires project credentials and a real Postgres | `supabase db push` against `ldzgyzigvbwofbswitrv`; then run the live buddy suite |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] The three structural gates are each verified to fail on an introduced violation
- [ ] No watch-mode flags
- [ ] Feedback latency < 15 s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
