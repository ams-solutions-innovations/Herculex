---
phase: 11
slug: gym-buddy-live-workout
status: planned
nyquist_compliant: true
wave_0_complete: false
created: 2026-08-17
updated: 2026-08-18
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

37 tasks across 11 plans. Three are human checkpoints using the `<how-to-verify>` /
`<resume-signal>` idiom rather than an automated command — they are credential-bound or
supply-chain decisions that cannot be automated, and each is listed in Manual-Only
Verifications below.

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 11-01-01 | 01 | 1 | BUD-04, BUD-05 | — | Migration tooling is reproducible, not tribal | CLI | `supabase --version` | ✅ | ⬜ pending |
| 11-01-02 | 01 | 1 | BUD-04, BUD-05 | T-11-05 | Links the Herculex ref, never SummitSki; no token in the repo | checkpoint | *human — see Manual-Only* | n/a | ⬜ pending |
| 11-01-03 | 01 | 1 | BUD-05 | T-11-05 | The frozen-policy rule is written down where the next person finds it | CLI | `grep` chain over `docs/supabase-migrations.md` | ❌ W0 | ⬜ pending |
| 11-02-01 | 02 | 1 | BUD-03 | T-11-24 | `scope` is not on the wire and cannot be | unit | `flutter test test/buddy/buddy_event_test.dart` | ❌ W0 | ⬜ pending |
| 11-02-02 | 02 | 1 | BUD-03 | T-11-24 | The publisher seam has no scope parameter | unit | `flutter analyze lib/features/buddy/ test/buddy/` | ❌ W0 | ⬜ pending |
| 11-02-03 | 02 | 1 | BUD-03, BUD-05 | T-11-24, T-11-05 | **Gate ×2**, each proven to fail on a violation | static source | `flutter test test/buddy/rls_frozen_test.dart test/buddy/buddy_scope_boundary_test.dart` | ❌ W0 | ⬜ pending |
| 11-03-01 | 03 | 2 | BUD-02, BUD-04 | T-11-15 | Buddy mirror tables carry no sync columns; placeholder representable | unit | `dart run build_runner build && flutter analyze lib/data/local/` | ✅ | ⬜ pending |
| 11-03-02 | 03 | 2 | BUD-02 | T-11-16 | v29 migrates without dropping rows | unit | `flutter test test/migration_test.dart test/schema_v29_test.dart` | ⚠️ extend | ⬜ pending |
| 11-03-03 | 03 | 2 | BUD-02, BUD-04 | T-11-15 | No outbox trigger on buddy tables; `buddy_session_id` round-trips | unit | `flutter test test/buddy/buddy_local_only_test.dart test/sync/sync_payload_test.dart` | ❌ W0 | ⬜ pending |
| 11-04-01 | 04 | 2 | BUD-05 | T-11-07, T-11-08 | `plpgsql` helper (never inlined); definer + empty search_path | static source | `grep` gate chain over `0011_buddy_sessions.sql` | ❌ W0 | ⬜ pending |
| 11-04-02 | 04 | 2 | BUD-01, BUD-04, BUD-06 | T-11-04, T-11-17 | Gapless seq under row lock; no `bigserial`; safe topic policy | static source | `grep` gate chain over `0011_buddy_sessions.sql` | ❌ W0 | ⬜ pending |
| 11-04-03 | 04 | 2 | BUD-05 | T-11-05 | No `0003` policy is touched by the new migration | static source | frozen-policy scan loop over `0003_sync_rls.sql` table list | ❌ W0 | ⬜ pending |
| 11-05-01 | 05 | 3 | BUD-04, BUD-05 | — | Schema is actually on the server, not just in a file | checkpoint | *human — see Manual-Only* | n/a | ⬜ pending |
| 11-05-02 | 05 | 3 | BUD-01, BUD-04, BUD-05, BUD-06 | T-11-01, T-11-04, T-11-05 | Live: token gates, gapless seq, cross-user negatives, departed-writer rejection | integration (live) | `flutter test test/sync/live_buddy_test.dart --dart-define-from-file=.secrets/live_sync.json` | ❌ W0 | ⬜ pending |
| 11-06-01 | 06 | 4 | BUD-04 | T-11-22 | Ordering, dedupe, gap refetch; no event lost in the subscribe/backfill gap | unit | `flutter test test/buddy/buddy_event_stream_test.dart` | ❌ W0 | ⬜ pending |
| 11-06-02 | 06 | 4 | BUD-01, BUD-04 | T-11-27 | One generic join failure; client cannot insert into the log | unit | `flutter analyze lib/features/buddy/ && flutter test test/buddy/buddy_scope_boundary_test.dart` | ❌ W0 | ⬜ pending |
| 11-06-03 | 06 | 4 | BUD-06 | T-11-06, T-11-28 | Explicit teardown; channel independent of `SyncService` | unit | `flutter test test/buddy/ && flutter analyze lib/features/buddy/` | ❌ W0 | ⬜ pending |
| 11-07-01 | 07 | 5 | BUD-02, BUD-04 | T-11-21 | Slot mapping incl. placeholders; unlink preserves the exercise | unit | `flutter test test/buddy/ && flutter analyze lib/features/buddy/` | ❌ W0 | ⬜ pending |
| 11-07-02 | 07 | 5 | BUD-03, BUD-04 | T-11-09, T-11-21 | Never inserts into `exercise_catalog`; unresolvable ref becomes a visible placeholder | unit | `flutter test test/buddy/buddy_apply_test.dart` | ❌ W0 | ⬜ pending |
| 11-07-03 | 07 | 5 | BUD-06 | T-11-20 | **Gate:** a propagated remove never discards logged sets | unit | `flutter test test/buddy/buddy_apply_test.dart -N "remove never discards logged sets"` | ❌ W0 | ⬜ pending |
| 11-07-04 | 07 | 5 | BUD-04 | T-11-22 | Cold restart reconstructs from the log; a throw does not advance the cursor | unit | `flutter test test/buddy/buddy_replay_test.dart` | ❌ W0 | ⬜ pending |
| 11-08-01 | 08 | 6 | BUD-05 | T-11-09 | A custom exercise is forced local with a stated reason | unit | `flutter test test/buddy/buddy_sender_test.dart -N "share policy"` | ❌ W0 | ⬜ pending |
| 11-08-02 | 08 | 6 | BUD-03 | T-11-24, T-11-25, T-11-26 | **Gate:** scope `mine` produces zero publisher calls; failed append rolls back | unit | `flutter test test/buddy/buddy_sender_test.dart test/buddy/buddy_scope_boundary_test.dart` | ❌ W0 | ⬜ pending |
| 11-08-03 | 08 | 6 | BUD-03 | T-11-24 | No payload map carries a `scope` key, for any kind | unit | `flutter test test/buddy/buddy_publisher_test.dart` | ⚠️ extend | ⬜ pending |
| 11-09-01 | 09 | 7 | BUD-01 | T-11-01 | Payload carries only the token; `tryDecode` never throws | unit | `flutter test test/buddy/buddy_join_payload_test.dart` | ❌ W0 | ⬜ pending |
| 11-09-02 | 09 | 7 | BUD-02, BUD-04 | T-11-28 | Subscribe precedes backfill; own session row otherwise untouched | unit | `flutter test test/buddy/buddy_session_controller_test.dart -N "host"` | ❌ W0 | ⬜ pending |
| 11-09-03 | 09 | 7 | BUD-01, BUD-02 | T-11-27, T-11-29 | Auto-start creates the joiner's OWN session; one generic failure | unit | `flutter test test/buddy/buddy_session_controller_test.dart -N "join"` | ❌ W0 | ⬜ pending |
| 11-09-04 | 09 | 7 | BUD-06 | T-11-06, T-11-28 | Leaving is safe; `SyncService.stop()` does not kill the channel | unit | `flutter test test/buddy/buddy_session_controller_test.dart -N "leave"` | ❌ W0 | ⬜ pending |
| 11-09-05 | 09 | 7 | BUD-04 | T-11-28 | Controller lifetime follows the session, not auth | unit | `flutter analyze lib/features/buddy/ && flutter test test/buddy/` | ❌ W0 | ⬜ pending |
| 11-10-01 | 10 | 8 | BUD-01 | — | QR dependency is a looked-at supply-chain decision | checkpoint | *human — see Manual-Only* | n/a | ⬜ pending |
| 11-10-02 | 10 | 8 | BUD-01 | T-11-01 | QR clears on join; token never rendered as text | widget | `flutter analyze lib/features/buddy/presentation/ && flutter test` | ❌ W0 | ⬜ pending |
| 11-10-03 | 10 | 8 | BUD-01 | T-11-27, T-11-31 | Generic failure in the UI; scanner survives a non-buddy code | widget | `flutter analyze lib/features/buddy/presentation/ lib/features/shell/ && flutter test` | ❌ W0 | ⬜ pending |
| 11-10-04 | 10 | 8 | BUD-03 | T-11-30 | Sticky defaults; remove defaults to only-me; forced reason shown | widget | `flutter test test/buddy/ && flutter analyze lib/features/buddy/ lib/features/workouts/` | ❌ W0 | ⬜ pending |
| 11-10-05 | 10 | 8 | BUD-03, BUD-06 | T-11-21 | Placeholder slots and the kept-your-work notice are visible | widget | `flutter analyze lib/features/workouts/ lib/features/buddy/ && flutter test` | ❌ W0 | ⬜ pending |
| 11-11-01 | 11 | 9 | BUD-02, BUD-06 | T-11-02 | **Proof:** neither device holds the other's set rows | unit (two DBs) | `flutter test test/buddy/buddy_two_device_test.dart` | ❌ W0 | ⬜ pending |
| 11-11-02 | 11 | 9 | BUD-02 | T-11-32 | Analytics totals identical with and without a buddy session | unit | `flutter test test/buddy/buddy_analytics_isolation_test.dart` | ❌ W0 | ⬜ pending |
| 11-11-03 | 11 | 9 | BUD-02 | T-11-33 | `buddySessionId` survives push/pull — BUD-07's only dependency | unit | `flutter test test/sync/sync_payload_test.dart -N "buddy_session_id"` | ⚠️ extend | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

### Non-negotiable gates

Three tests are structural gates, not coverage. Each must be proven to **fail** on a
deliberately introduced violation before it counts as passing — the precedent is
`test/rep_tracker_write_boundary_test.dart` from Phase 10.

| Gate | Task | Requirement | What it proves |
|------|------|-------------|----------------|
| `test/buddy/buddy_scope_boundary_test.dart` | 11-02-03, re-asserted 11-08-02 | BUD-03 | A `scope: mine` mutation produces zero publisher calls and zero log rows — the scope separation is structural, not a runtime boolean |
| `test/buddy/rls_frozen_test.dart` | 11-02-03 | BUD-05 | `supabase/migrations/0003_sync_rls.sql` is byte-identical to its pinned LF-normalised hash `f50be2f89c775245e2700c2e532065c7d89ea240da0ef5ed77ff14bb25697530`; asserts the file exists and is non-empty first so it cannot pass vacuously |
| `buddy_apply_test.dart -N "remove never discards logged sets"` | 11-07-03 | BUD-06 | The locked BUD-03 × BUD-06 resolution: a propagated `remove` unlinks rather than deletes when the local slot has logged work |

---

## Wave 0 Requirements

- [ ] `test/buddy/` directory — does not exist
- [ ] `test/buddy/fake_buddy_publisher.dart` — the seam every scope test drives; follow `test/sync/fake_sync_backend_service.dart`
- [ ] `test/buddy/fake_buddy_gateway.dart` — records `fetchEventsSince` calls; carries `failWith`
- [ ] `test/support/two_device.dart` — extract the two-Drift-database harness from `test/sync/sync_payload_test.dart:22-26` rather than copy-pasting it
- [ ] `test/buddy/buddy_scope_boundary_test.dart` — BUD-03 structural gate
- [ ] `test/buddy/rls_frozen_test.dart` — BUD-05 pinned-hash gate
- [ ] `test/buddy/buddy_local_only_test.dart` — clone of `test/rep_local_only_test.dart`
- [ ] `test/buddy/buddy_event_test.dart` — wire contract round trips
- [ ] `test/buddy/buddy_event_stream_test.dart` — ordering, dedupe, gap-triggered backlog refetch
- [ ] `test/buddy/buddy_apply_test.dart` — per-kind apply, idempotence, the remove gate, unresolvable refs
- [ ] `test/buddy/buddy_replay_test.dart` — cold-restart reconstruction
- [ ] `test/buddy/buddy_sender_test.dart` — scope gating, rollback, custom-exercise refusal
- [ ] `test/buddy/buddy_publisher_test.dart` — per-kind payloads, no `scope` key
- [ ] `test/buddy/buddy_join_payload_test.dart` — QR encode/decode round trip and malformed-input fuzz
- [ ] `test/buddy/buddy_session_controller_test.dart` — host, join, leave, teardown
- [ ] `test/buddy/buddy_two_device_test.dart` — BUD-02 isolation proof
- [ ] `test/buddy/buddy_analytics_isolation_test.dart` — follow `test/analytics_soft_delete_test.dart`
- [ ] `test/sync/live_buddy_test.dart` — reuse the `_email`/`_email2` and `outsiderSkip()` idiom from `test/sync/live_round_trip_test.dart:445-456`
- [ ] `test/generated_migrations/schema_v29.dart` + `drift_schemas/drift_schema_v29.json` — generated, not hand-written
- [ ] `test/schema_v29_test.dart` — follow `test/schema_v28_test.dart`
- [ ] Framework install: **none needed**

---

## Manual-Only Verifications

| Task | Behavior | Requirement | Why Manual | Test Instructions |
|------|----------|-------------|------------|-------------------|
| 11-01-02 | CLI authenticated and repo linked to the Herculex project | BUD-04, BUD-05 | Requires a personal access token and a DB password that must not enter the repo | Export `SUPABASE_ACCESS_TOKEN`, run `supabase link --project-ref ldzgyzigvbwofbswitrv`, confirm the ref is **not** `jioesomepkauponjrena`, then `supabase migration list` |
| 11-05-01 | `0011_buddy_sessions.sql` applied to the live project | BUD-04, BUD-05 | Writes to production Postgres; credential-bound | `supabase db push`, then `supabase migration list` showing `0011` remote |
| 11-10-01 | QR generation package vetted | BUD-01 | Supply-chain decision; slopcheck has no pub.dev ecosystem so the package could not be machine-verified | Check publish date, licence, maintenance status and Flutter SDK support on pub.dev before adopting |
| — | Two physical phones see the same exercise list within ~1 s of a change | BUD-03, BUD-04 | Cross-device latency cannot be observed from a single test process | Start a workout on phone A, share, scan on phone B, add an exercise with scope `both`, observe propagation |
| — | QR scan-to-join from the `+` menu | BUD-01 | Camera hardware | Display the QR on phone A, scan from phone B's `+` menu, confirm the joiner's session auto-starts and links |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify, a `<how-to-verify>` checkpoint, or Wave 0 dependencies — 34 of 37 automated, 3 checkpoints listed above
- [x] Sampling continuity: no 3 consecutive tasks without automated verify (each checkpoint is followed immediately by an automated task)
- [x] Wave 0 covers all MISSING references
- [ ] The three structural gates are each verified to fail on an introduced violation — *proven during execution, not planning*
- [x] No watch-mode flags
- [x] Feedback latency < 15 s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** pending execution
