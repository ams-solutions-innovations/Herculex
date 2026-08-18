# RB-02 — Cloud sync verification

> **How migrations reach the server is now documented in
> [`docs/supabase-migrations.md`](supabase-migrations.md)** — the Supabase
> CLI is installed and linked, and `supabase db push` replaces the
> undocumented "applied via the Supabase MCP tools" mechanism referenced
> below.

> ⚠️ **Wrong project (corrected 2026-08-15).** Everything below was carried out
> against `jioesomepkauponjrena`, which is the **SummitSki** project, not
> Herculex. Herculex's real backend is **`ldzgyzigvbwofbswitrv`**. The findings
> and defect analysis remain valid — the schema and client code were the same —
> but the server-side verification tables describe SummitSki's database. The
> migrations were re-applied to `ldzgyzigvbwofbswitrv` on 2026-08-15; that
> project has **not** been through the device and round-trip passes recorded
> here. The test accounts named below exist only in the old project.

Covers `docs/app-audit-report-2026-08-10.md` release blocker #2 ("Cloud sync
reports success without real cloud sync").

The sync layer was fully unit-tested against `FakeSyncBackendService` long
before any data moved. That was never enough on its own: the fake
*reimplements* the semantics it is meant to verify (the server `updated_at`
clock, the tombstone triggers, the inclusive/exclusive `deleted_at` boundary)
and has no RLS policies at all, because RLS is enforced server-side. As of
2026-08-12 the live project reported 0 auth users and 0 rows in every table —
nothing had ever round-tripped.

This document is how that gap is closed. Most of it is now automated; a short
manual pass covers what a headless test genuinely cannot reach.

---

## Already verified server-side (no device needed)

Checked via the Supabase MCP tools, after applying migrations `0001`–`0007`:

| Check | Result |
| --- | --- |
| Migrations applied | `0001`–`0007` |
| Synced tables | 36, all with `rls_enabled = true` |
| RLS policies | 4 per synced table (`select`/`insert`/`update`/`delete`, all `user_id = auth.uid()`) |
| `updated_at` triggers | 36 (`t_set_updated_at_*`) |
| Tombstone triggers | 36 (`t_record_tombstone_*`) |
| `sync_tombstones` policies | 1 (select-own only; writes are trigger-only, `security definer`) |
| Realtime publication | 37 tables (36 synced + `sync_tombstones`) — none were published before `0005`, so every Realtime subscription the client opened was silently dead |
| Retention job | `sync_tombstones_gc`, `17 3 * * *`, active, 90-day window |
| Security advisors | clean |

---

## The automated round trip

`test/sync/live_round_trip_test.dart` runs two "devices" — two `SyncService`
instances over two in-memory Drift databases, each with its own
`SupabaseClient` signed in as the same test account — against the **live**
project. A bare `SupabaseClient` is pure Dart, so this needs no emulator and
no Flutter plugin channels.

It proves:

1. a local write reaches Postgres, owned by the signed-in uid;
2. `updated_at` is stamped by the server — asserted by forcing a nonsense
   local clock (2001-01-01) and checking the row still moves *forward* in
   time;
3. the row arrives on the second device;
4. a hard delete propagates via `sync_tombstones` — the case that was
   impossible before `0005`;
5. applying that tombstone does not enqueue an outbox delete (no ping-pong);
6. a custom exercise and the micro workout referencing it both survive, with
   `is_custom` intact and the FK re-resolved to the second device's own local
   id (see the `0007` note below);
7. cross-user RLS: a second account sees an empty set, not a 403, and cannot
   forge a row owned by the first;
8. realtime actually delivers a hint (opt-in — the one timing-dependent
   assertion, isolated so its flakiness cannot take the file down).

### Running it

The test **skips itself** unless credentials are present, so plain
`flutter test` stays green and offline. Create `.secrets/live_sync.json`
(gitignored):

```json
{
  "SUPABASE_URL": "https://ldzgyzigvbwofbswitrv.supabase.co",
  "SUPABASE_ANON_KEY": "<publishable key>",
  "SUPABASE_TEST_EMAIL": "<throwaway account 1>",
  "SUPABASE_TEST_PASSWORD": "<password>",
  "SUPABASE_TEST_EMAIL_2": "<throwaway account 2>",
  "SUPABASE_TEST_PASSWORD_2": "<password>"
}
```

```
flutter test test/sync/live_round_trip_test.dart --dart-define-from-file=.secrets/live_sync.json
```

Add `"SUPABASE_TEST_REALTIME": true` to include the realtime probe.

The second account is only used for the RLS check, which cannot be faked:
`user_id` has a foreign key to `auth.users`, so there is no synthetic foreign
owner to test against. Without it that one test skips and the rest still run.

The test cleans up after itself — `wipeRemote` deletes everything the test
accounts own, children first, in both `setUpAll` and `tearDownAll`, so it is
robust to a mid-test failure and safe to re-run. Running it twice in a row is
itself a useful check: it proves cleanup and cursor seeding are idempotent.

`sync_tombstones` rows are deliberately *not* cleaned — `0005` revokes client
writes on that table and the 90-day `sync_tombstones_gc` job owns it. Left
behind they are inert, since every run starts from fresh in-memory databases
whose tombstone cursor seeds to "now".

---

---

## Device Verification Results (2026-08-13) — PASSED

Tested on physical Samsung Galaxy S25 Ultra (SM-S938B, Android 16):

1. **Sign-in starts sync**: Signed out badge showed `"Cloud sync off"`. Upon signing in, transitioned to `"Syncing…"` and settled on `"Synced"`.
2. **Offline queueing**: In Airplane Mode, creating logs correctly displayed `"5 pending"`.
3. **Reconnection**: Turning Airplane Mode OFF immediately triggered the network listener and flushed the pending ops back to `"Synced"`. Verified live with Supabase Postgres.

---

## Defects this pass found

- **`is_custom` never crossed the wire** (`0007_catalogue_is_custom.sql`).
  It was marked local-only on all four catalogue tables, on the reasoning that
  only custom rows are ever pushed so the flag is redundant. That holds going
  up and fails coming down: the receiving device's local default is `false`,
  so a pulled custom row became a *seeded* one.
  `SyncIdResolver.resolveCatalogueRefForPush` then took the wrong branch for
  every child referencing it — for exercises and foods the natural key is null
  on custom rows, so the payload carried both catalogue columns null and
  Postgres rejected it on the `check` constraint (eight retries, quarantine, a
  red badge); for accessories and bands it resolved to *some other* row
  silently. Regression tests in `test/sync/sync_payload_test.dart`.
- **The outbox drained in an order that could put a child before its parent.**
  The triggers stamp `created_at` with `strftime('%s','now')`, so rows
  enqueued in the same second tie and `ORDER BY created_at` alone left the
  order to the query plan. Now `ORDER BY created_at, id`. Re-editing an
  already-pending parent can still move it past its child, but that case
  self-heals through the normal retry path.
- **A freshly pulled row could get stuck immune to deletion.** Found by the
  live run itself — no unit test caught it first. Writing down a row pulled
  for the first time is a plain SQLite `INSERT`, which fires the same
  `trg_outbox_ins_*` trigger a real local edit would, leaving a phantom
  `pending_sync_ops` entry behind. Until something happened to push that
  entry away, `_applyTombstoneBatch`'s local-wins check read it as a genuine
  unpushed edit and refused to apply a delete for that row — a delete from
  another device landing soon after the row's first arrival would sit
  invisibly stuck for up to the 20-second push timer, or longer if that push
  failed. `_applyPulledRow` now deletes its own echo right after writing the
  row. Two regression tests reproduce it directly in
  `test/sync/sync_service_test.dart`.

---

## Round trip results (2026-08-13)

Ran twice in a row against the live project (`test/sync/live_round_trip_test.dart`,
including the opt-in realtime probe), both green. Server-side afterward:

| Check | Result |
| --- | --- |
| Rows left in any synced table for the test accounts | 0 |
| Rows with the wrong `user_id` | 0 |
| Rows with a client-supplied `updated_at` | 0 |
| `sync_tombstones` entries recorded | 24 (accumulated across every run this session; inert, swept by the 90-day GC job) |
| Security advisors | 1 pre-existing, unrelated finding (`auth_leaked_password_protection` — project-wide auth hardening, not caused by or in scope for this work) |

Remaining: the three device-only steps above.

---

## Known limitations, deliberately not fixed

- **Account switch leaves local rows in place.** The outbox and cursors are
  cleared so nothing leaks *upward* into the wrong cloud account, but the
  previous user's rows stay in the local database and will be visible to the
  new user on that device. Full per-user isolation (wipe or partition local
  data on switch) is a larger change to app startup and the database
  lifecycle.
- **A device offline longer than 90 days** falls back to a full existence
  reconcile (`_fullReconcile`), which is correct but has only been exercised
  in tests, never against the real backend — it is impractical to test
  honestly without waiting out the window or hand-editing the cursor.
- **The ~500 ms Wear echo-suppression window** documented in
  `docs/wear-sync-remediation-progress.md` is unrelated to this workstream and
  unchanged.
