# Phase 11: Gym Buddy — Live Shared Workout - Research

**Researched:** 2026-08-17
**Domain:** Real-time multi-user session choreography over Supabase Realtime broadcast + Postgres RLS, on a Flutter/Drift local-first client
**Confidence:** HIGH for the Supabase Realtime API surface and the codebase facts; MEDIUM for the join-token and conflict-resolution designs (these are design recommendations, not verified facts); LOW on nothing material.

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**The non-negotiable: two sessions, never one.** Each participant owns a separate `WorkoutSessions` row (`lib/data/local/tables.dart:144`), synced under their own `user_id` exactly as today. A shared `buddySessionId` links the two rows. What is shared is the **choreography** — which exercises, in what order — and nothing else.

Consequences that must hold:
- No partner-owned `SetEntries` row is ever written into the other participant's database.
- Buddy sessions never double-count in analytics. `trainingSnapshotProvider` and every downstream engine keep reading only rows the user owns; because partner rows never land locally, this requires *no* analytics change — and a test must prove that.
- Ownership is not a flag on a shared row that a refactor could flip. It is physical separation: the partner's data is not present.

**Session identity: reuse `sessionUuid`.** `WorkoutSessions.sessionUuid` (added v22 for the phone↔watch wire protocol) is already a stable, cross-device session identity. The buddy protocol keys on it rather than on the local autoincrement `id`. `buddySessionId` is a separate new UUID identifying the *pair*, not either session.

**Exercise references must travel as natural keys, not local ids.** Every buddy choreography event must use the same representation as `CatalogueFk` / `SyncIdResolver.resolveCatalogueRefForPush`. Broadcasting a raw `exerciseId` will silently attach the wrong exercise on the partner's phone. A **custom** exercise that exists only on one participant's device is an edge case the plan must handle explicitly — either transmit enough to materialise it, or refuse to share it with a clear message. Do not let it fail silently.

**Transport: Realtime broadcast for speed, durable log for truth.** Live state travels over a Supabase Realtime **broadcast** channel scoped to the buddy session. Every choreography event is **also** appended to a durable `buddy_session_events` table. Events carry a monotonic per-session sequence number so replay is ordered and idempotent. Broadcast is an optimisation over the log, never the source of truth — if the two ever disagree, the log wins.

**Scope choice on every change: "both of us" or "only me".** Every choreography mutation (add, remove, reorder, replace) carries an explicit `scope` of `both` or `mine`. `scope: both` → applied on both devices, appended to the shared log. `scope: mine` → applied locally only, **never** broadcast and never appended to the shared log. It needs a test proving a `mine`-scoped change produces no broadcast and no log row. The plan must decide how the scope is asked for, but must not make "both" implicit for destructive operations.

**Security: existing RLS policies are frozen.** Every policy in `supabase/migrations/0003_sync_rls.sql` is `user_id = auth.uid()`. **None of them may be modified, widened or replaced by this phase.** Cross-user visibility is confined to the new buddy tables, whose policies grant access based on participation in a buddy session, plus a minimal participant display identity (name/avatar only). No new policy may grant a partner read access to another user's training, nutrition, measurement or biometric tables. A test must assert the `0003` policies are unchanged.

**Join tokens are short-lived and single-session.** The QR code encodes a join token scoped to one buddy session, expires quickly, and cannot be reused once the session ends. It does not create any lasting relationship. The plan must pick a concrete expiry and decide whether a token is single-use or joinable-once-per-participant.

**Leaving is always safe.** Either participant can leave at any time. The other's workout continues uninterrupted and both sessions save normally. A partner disconnecting, leaving, or force-quitting can never complete, alter or discard the other's sets.

### Claude's Discretion

- Exact local table shapes and the v29 migration contents.
- Where the share button lives in `active_workout_view.dart` and how the join entry is added to `lib/features/shell/quick_add_menu.dart`.
- How partner presence is surfaced in the active workout UI (and whether partner set-completion is shown live at all — the requirement does not demand it).
- QR generation package choice (`qr_flutter` is the obvious candidate; `mobile_scanner` ^7.4.0 already covers scanning).
- Conflict resolution when both participants mutate choreography simultaneously — sequence-number ordering is the mechanism, but the tie-break rule is open.
- Whether the buddy channel logic extends `SupabaseSyncBackendService` or lives in a new service.

### Deferred Ideas (OUT OF SCOPE)

- **BUD-07 — Buddy VS comparison:** three buttons in workout history comparing per-exercise winner, calisthenics rep counts and per-session volume against the partner. Requires only `buddySessionId` from this phase.
- **BUD-08 — Persistent friends:** identity, search, invite, accept, block. Prerequisite for challenges.
- **BUD-09 — Challenges:** each participant sets a goal with a deadline (strength target, BF%, kg lost or gained), progress read from existing measurement and training data, resolved at the deadline.
- More than two participants in one buddy session.
- Sharing nutrition, fasting or biometric data with a buddy.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| **BUD-01** | Sharing is an explicit action; partner joins by scanning a short-lived, single-session QR code from the `+` button; the token cannot be reused after the session ends. | § Join Token Design (mint/validate RPCs, `gen_random_uuid()` + core `sha256()`, 10-minute expiry, `consumed_at` under `FOR UPDATE`, end-of-session invalidation); § Standard Stack (QR generation package); `lib/features/nutrition/presentation/barcode_scanner_view.dart` is the existing `mobile_scanner` precedent to clone. |
| **BUD-02** | Each participant keeps their own `WorkoutSessions` row under their own `user_id`; shared `buddySessionId` links them; no cross-write of sets/reps/weight/RPE/measurements; no analytics double-count. | § Architectural Responsibility Map (buddy tier owns choreography only); § Drift v29 (`WorkoutSessions.buddySessionId` is the *only* change to a synced table); § Validation Architecture (two-device Drift test asserting zero foreign `set_entries` rows; the existing `analytics_soft_delete_test.dart` idiom). |
| **BUD-03** | Add/remove/reorder/replace propagate live; every change offers "both of us" / "only me"; "only me" never mutates the partner's list. | § Event Schema and Ordering (slot-id addressing, full-list reorder, LWW-by-seq); § Pitfall 5 (`scope` must be structural, not a boolean on the wire); § Pitfall 6 (`removeWorkoutExercise` hard-deletes the partner's sets — a BUD-03 × BUD-06 conflict with a concrete resolution). |
| **BUD-04** | Live state over Realtime broadcast; every event also appended to a durable log; reconnect/restart rejoins at the correct shared state. | § Recommended Transport (broadcast-from-database makes log-then-broadcast atomic); § Sequence Numbering (per-session counter under row lock); § Reconnect and Replay Protocol (subscribe-then-backfill-then-drain, dedupe by seq); § Broadcast Replay (`ReplayOption`, why it is not a substitute). |
| **BUD-05** | `0003_sync_rls.sql` unchanged; cross-user visibility confined to new buddy tables + minimal participant display identity; no partner read access to training/nutrition/biometric tables. | § RLS Design for the Buddy Tables (non-recursive `plpgsql SECURITY DEFINER` helper, revoke-and-RPC-only writes); § Minimal Participant Display Identity (denormalise at join — the repo has no server-side profiles table at all); § Validation Architecture (sha256 pin on `0003`, live cross-user negative test). |
| **BUD-06** | Either participant can leave at any time; the other's workout continues; both save normally; a disconnect never completes/alters/discards the other's sets. | § Leave, End and Revocation (server-side participation check on every append; the Realtime policy-cache limitation and its mitigation); § Pitfall 6 (remove-with-logged-sets must unlink, not delete). |
</phase_requirements>

---

## Summary

The four locked decisions are all achievable on the current stack, but the single highest-leverage finding is that **`supabase_flutter` 2.17.1 supports Broadcast-from-the-Database**, which collapses the "broadcast plus durable log" pair into one atomic write. Rather than the client sending a websocket broadcast *and* inserting a log row (two operations that can disagree), the client calls one `SECURITY DEFINER` RPC that appends to `buddy_session_events`; an `AFTER INSERT` trigger on that table calls `realtime.send(...)`, and the Realtime server fans the message out by reading its own WAL after the transaction commits. The CONTEXT's rule "if the two ever disagree, the log wins" then becomes structurally unfalsifiable rather than a convention a refactor could break. It also means clients never need an `INSERT` policy on `realtime.messages` for broadcast at all — only `SELECT` (plus a narrow `INSERT` scoped to `extension = 'presence'` if presence is used), which is the tightest possible security surface and directly serves BUD-05.

The second finding worth planning around is a Postgres trap: **a `LANGUAGE sql` `SECURITY DEFINER` helper is inlined by the planner and loses its definer context, restoring the RLS recursion it was written to break.** The buddy tables have exactly the mutual-reference shape that triggers this (`buddy_participants` policies must ask "is this user a participant?", which queries `buddy_participants`). The helper must be `LANGUAGE plpgsql`. The repo already has a correct `SECURITY DEFINER` + `SET search_path = ''` precedent in `supabase/migrations/0005_sync_tombstones.sql:48-61`, and one important difference to note: `record_sync_tombstone()` has `EXECUTE` revoked from `authenticated` because it is trigger-only, whereas the buddy participation helper is called from inside a policy evaluated *as* `authenticated` and therefore **must** keep `EXECUTE`.

Third: sequence numbering. A `bigserial` on `buddy_session_events` is *not* monotonic in commit order — Postgres allocates sequence values before commit and never rolls them back, so a consumer polling `where seq > last_seen` can permanently skip an event. At two writers, the correct and cheap answer is a per-session counter incremented under a `SELECT ... FOR UPDATE` row lock on `buddy_sessions` inside the append RPC. This is the "manual gapless sequence" that is rejected for high-throughput outboxes and is exactly right here: the lock is held until commit, so the second transaction cannot obtain a number until the first is visible. Gapless and commit-ordered, with zero contention at n=2.

Fourth, and the most likely thing to be missed: `WorkoutsRepository.removeWorkoutExercise` (`lib/features/workouts/data/workouts_repository.dart:710`) performs a **hard delete** of every `SetEntries` row under the exercise. A `scope: both` remove event applied verbatim on the partner's device therefore discards the partner's logged sets — a direct violation of BUD-06 ("a partner … can never complete, alter or discard the other's sets") arising straight out of BUD-03 ("remove … propagates live"). These two requirements collide and the plan must resolve the collision deliberately.

**Primary recommendation:** Build one append path — a `plpgsql SECURITY DEFINER` RPC (`buddy_append_event`) that checks participation, takes the per-session sequence under a row lock, inserts the event, and lets an `AFTER INSERT` trigger `realtime.send()` it to the private channel `buddy:<buddySessionId>`. Clients subscribe with `RealtimeChannelConfig(private: true)`, dedupe strictly by `seq`, and never call `sendBroadcastMessage` for choreography.

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Mint / validate / consume join token | Database (Postgres `SECURITY DEFINER` RPC) | — | The token table must be invisible to clients; validation must be atomic (`FOR UPDATE`) and must not leak an existence oracle. A client-side table read cannot do any of that. |
| Buddy session + participant records | Database (new `buddy_*` tables + RLS) | Local Drift mirror (read cache) | Cross-user by definition; the only place cross-user visibility is permitted (BUD-05). |
| Choreography event durability + total order | Database (`buddy_session_events` + per-session counter) | — | Ordering under concurrency is a transaction-boundary problem; only the DB can serialise it. |
| Live fan-out of choreography events | Realtime server (broadcast-from-database via `realtime.send` trigger) | — | Makes "log first, then broadcast" atomic instead of two client operations that can diverge. |
| Applying a choreography event to local rows | Flutter client (`WorkoutsRepository` + a new buddy applier) | — | Local `WorkoutExercises.id` values are device-local; only the client can resolve a natural key to a local int id. |
| Partner liveness / "is my buddy still here" | Realtime presence (`track`/`onPresenceSync`) | Durable `buddy_participants.left_at` | Presence is ephemeral and correct for "connected right now"; the durable column is what survives a crash. |
| Sets / reps / weight / RPE / measurements | Existing owner-only sync (`SyncService` + `0003` policies) | — | **Never** touched by the buddy tier. This is BUD-02's physical separation. |
| Cross-device exercise identity | Flutter client (`SyncIdResolver.resolveCatalogueRefFor{Push,Pull}`) | — | The natural-key ↔ uuid representation already exists and is proven by `test/sync/sync_payload_test.dart`. |
| QR encode / decode | Flutter client (`qr_flutter` / existing `mobile_scanner`) | — | Pure presentation over an opaque token string. |

---

## Standard Stack

### Core (already present — verified in `pubspec.lock`)

| Library | Resolved version | Purpose | Why standard |
|---------|------------------|---------|--------------|
| `supabase_flutter` | **2.17.1** (declared `^2.8.0`) | Auth, Postgres, Realtime | Already the app's backend. `pubspec.lock:1616-1623` `[VERIFIED: pubspec.lock]` |
| `supabase` | 2.16.0 (transitive) | `SupabaseClient.channel` / `.rpc` | `pubspec.lock:1600-1607` `[VERIFIED: pubspec.lock]` |
| `realtime_client` | **2.13.0** (transitive) | `RealtimeChannel`, `RealtimeChannelConfig`, broadcast + presence | `pubspec.lock:1275-1282` `[VERIFIED: pubspec.lock]` |
| `mobile_scanner` | 7.4.0 | QR **scanning** for the join flow | `pubspec.lock:1003-1010`; existing usage at `lib/features/nutrition/presentation/barcode_scanner_view.dart:38-49` `[VERIFIED: codebase]` |
| `drift` / `drift_flutter` | 2.21.x | Local schema v28 → v29 | `pubspec.yaml` `[VERIFIED: pubspec.yaml]` |
| `uuid` | 4.5.3 | `buddySessionId`, slot ids | Already used for `sessionUuid` at `workouts_repository.dart:436` `[VERIFIED: codebase]` |
| `flutter_riverpod` | 2.6.1 | Providers for the buddy session state | `lib/app/providers.dart` `[VERIFIED: codebase]` |

> **Correction to the brief:** the phase brief states `supabase_flutter: ^2.8.0`. That is the *declared constraint*; the *resolved* version is **2.17.1** with `realtime_client` **2.13.0**. Several APIs this phase needs — `RealtimeChannelConfig.private`, `ReplayOption`, `httpSend` — do not exist in 2.8.x. Plan against 2.17.1 and pin the lockfile.

### Supporting (one new dependency)

| Library | Version | Purpose | When to use |
|---------|---------|---------|-------------|
| `qr_flutter` | `^4.1.0` | Renders the join token as a QR widget | The share sheet in `active_workout_view.dart`. `[ASSUMED — see Package Legitimacy Audit]` |

### Alternatives Considered

| Instead of | Could use | Tradeoff |
|------------|-----------|----------|
| `qr_flutter` 4.1.0 | `pretty_qr_code` 3.6.0 | `pretty_qr_code` is actively maintained (published 2026-01-31 vs `qr_flutter`'s 2023-05-14) and MIT-licensed, but has ~10× fewer downloads (154k/mo vs 1.67M/mo) and scores 130/160 vs 150/160 on pub.dev. `qr_flutter`'s 150/160 means it still analyses clean against the current Dart/Flutter toolchain despite its age. Both wrap the same `qr` package (`qr ^3.0.1` → resolves 3.0.2, SDK `^3.4.0`, compatible with this repo's `sdk: ^3.11.5`). **Low-stakes, one-widget decision, trivially reversible.** `[VERIFIED: pub.dev API]` |
| A QR widget package at all | `qr` 4.0.0 + a hand-written `CustomPainter` | Zero *new* transitive surface and `qr` is the actively-maintained engine (published 2026-05-16, requires SDK `^3.11.0` — compatible). But hand-painting a QR module matrix, quiet zone and error-correction rendering is exactly the kind of thing the Don't-Hand-Roll table exists to prevent. Rejected. |
| Broadcast-from-database | Client-side `channel.sendBroadcastMessage` | Requires the client to do two operations (insert log row, send broadcast) that can diverge, and requires an `INSERT` policy on `realtime.messages` for `extension = 'broadcast'`, widening the cross-user surface for no benefit. Rejected — see § Recommended Transport. |
| A durable `buddy_session_events` table | Realtime **Broadcast Replay** (`ReplayOption`) | Replay is capped at **25 messages** and **72 hours**, and only replays messages published *via* broadcast-from-database. It cannot restore a 40-exercise session or one resumed after three days. It is a useful *fast path* on top of the log, never a substitute. Also: the durable log is a locked CONTEXT decision. `[CITED: supabase.com/docs/guides/realtime/limits]` |
| A per-session counter under a row lock | `bigserial` / `GENERATED ALWAYS AS IDENTITY` | Sequence values are allocated pre-commit and never rolled back, so commit order ≠ numeric order and a `where seq > last_seen` consumer can permanently skip events. Correct for high throughput, wrong here. `[CITED: event-driven.io/en/ordering_in_postgres_outbox/]` |
| A per-session counter under a row lock | `xid8` + `pg_snapshot_xmin(pg_current_snapshot())` | The rigorous general solution, but it is complexity priced for thousands of writers/sec. At two writers a row lock is simpler, gapless, and has no visibility-gap window. |

**Installation:**
```bash
flutter pub add qr_flutter
```

**Version verification performed:**
```bash
curl -s https://pub.dev/api/packages/qr_flutter        # latest 4.1.0, published 2023-05-14
curl -s https://pub.dev/api/packages/qr_flutter/score  # 2336 likes, 150/160 points, 1,666,499 downloads/30d, BSD-3-Clause
curl -s https://pub.dev/api/packages/pretty_qr_code    # latest 3.6.0, published 2026-01-31, MIT, 130/160, 153,770/30d
```

---

## Package Legitimacy Audit

**slopcheck status:** installed (`slopcheck 0.6.1`, invoked as `python -m slopcheck`) but **it has no `pub.dev` / Dart ecosystem** — supported ecosystems are `pypi, npm, crates.io, go, rubygems, maven, packagist` only. Per protocol this means the Dart package below is graded `[ASSUMED]` and the planner **must** gate its install behind a `checkpoint:human-verify` task.

Compensating verification was performed directly against **pub.dev's own API** (the authoritative registry for this ecosystem), which yields the same signals slopcheck would look for — age, download volume, source repository, licence.

| Package | Registry | Age | Downloads | Source repo | slopcheck | Disposition |
|---------|----------|-----|-----------|-------------|-----------|-------------|
| `qr_flutter` 4.1.0 | pub.dev | 3 yrs 3 mo (2023-05-14) | 1,666,499 / 30d | github.com/theyakka/qr.flutter | n/a (no Dart support) | **Approved — planner adds `checkpoint:human-verify`**. Licence BSD-3-Clause (OSI/FSF). 2336 likes, 150/160 pub points. Age is a *staleness* signal, not a slop signal — slop packages are new, not old. |
| `pretty_qr_code` 3.6.0 | pub.dev | 6 mo (2026-01-31) | 153,770 / 30d | (no `repository:` field in pubspec) | n/a | Fallback only. Licence MIT. Note the missing `repository` field — verify the GitHub source before adopting. |
| `qr` 3.0.2 (transitive) | pub.dev | 2 yrs (2024-07-16) | 2,787,114 / 30d | (BSD-3-Clause) | n/a | Pulled in transitively by either widget package. Very high volume, long history. |

**Packages removed due to slopcheck [SLOP] verdict:** none (slopcheck could not run on this ecosystem).
**Packages flagged as suspicious [SUS]:** none.

**Every other dependency this phase needs is already in `pubspec.lock` and already ships in production** — no new install risk.

---

## Recommended Transport

### The one-write-path pattern

```
                     ┌──────────────────────────────────────────┐
  Device A           │              Supabase                    │           Device B
  (sharer)           │                                          │           (joiner)
                     │                                          │
 choreography        │   ┌────────────────────────────────┐     │
 mutation, scope:both│   │ rpc buddy_append_event()        │    │
      │              │   │  plpgsql SECURITY DEFINER       │    │
      ├─ .rpc(...) ──┼──▶│  1. is_buddy_participant()?     │    │
      │              │   │  2. SELECT next_seq FOR UPDATE  │    │
      │              │   │  3. INSERT buddy_session_events │    │
      │ ◀── seq ─────┼───┤  4. UPDATE next_seq             │    │
      │              │   └──────────────┬─────────────────┘     │
      │              │        AFTER INSERT trigger              │
      │              │                  │                       │
      │              │        realtime.send(payload,            │
      │              │          'buddy_event',                  │
      │              │          'buddy:<id>', true)             │
      │              │                  │                       │
      │              │           INSERT realtime.messages       │
      │              │                  │  (committed)          │
      │              │                  ▼                       │
      │              │        ┌──────────────────┐              │
      │              │        │ Realtime server  │              │
      │              │        │ reads its WAL    │              │
      │              │        └────────┬─────────┘              │
      │              │                 │ fan-out                │
      │ ◀── echo ────┼─────────────────┼──────────────────────┬─┼──▶ onBroadcast
      │  (dedupe by  │                 │                      │ │      │
      │   seq)       │                 │                      │ │      ▼
      │              │                 │                      │ │  apply(event)
      │              │                 │                      │ │  in seq order,
      │              │                 │                      │ │  idempotent
      │              │                                          │      │
      │              │   ┌────────────────────────────────┐     │      │
      │              │   │ buddy_session_events (durable) │◀────┼──────┤ on reconnect:
      │              │   └────────────────────────────────┘     │      │ select where
      │              │                                          │      │ seq > lastSeen
      ▼              │                                          │      ▼
 local Drift write   │                                          │  local Drift write
 (own rows only)     │                                          │  (own rows only)
                     └──────────────────────────────────────────┘

  ═══ never crosses this boundary ═══
  SetEntries, reps, weightKg, rpeX10, bodyweightKg, measurements
```

Why this shape:

1. **Atomicity for free.** `realtime.send` inserts into `realtime.messages`; the Realtime server reads that insert from the WAL. A message therefore cannot be delivered for an event that did not commit. "Broadcast is an optimisation over the log, never the source of truth" stops being a convention. `[CITED: supabase.com/blog/realtime-broadcast-from-database]`
2. **Minimal Realtime policy surface.** Clients never insert broadcast messages, so `realtime.messages` needs only a `SELECT` policy for `extension = 'broadcast'`. This is a direct BUD-05 win.
3. **Forgery becomes impossible.** The client cannot choose its own `seq` and cannot write to `buddy_session_events` at all (`INSERT` revoked). A malicious client cannot forge an event for a session it left.
4. **Ordering is decided in one place.** No client-side clock, no tie-break heuristics.

### Verified Dart API (realtime_client 2.13.0, read from the local pub cache)

```dart
// SupabaseClient.channel — supabase-2.16.0/lib/src/supabase_client.dart:251-256
RealtimeChannel channel(
  String name, {
  RealtimeChannelConfig opts = const RealtimeChannelConfig(),
});

// realtime_client-2.13.0/lib/src/types.dart:196-204
const RealtimeChannelConfig({
  bool ack = false,               // server ACKs the broadcast
  bool self = false,              // receive your own client-sent broadcasts
  ReplayOption? replay,           // private channels only; DB-published messages only
  String key = '',                // presence key
  bool enabled = false,           // presence without presence bindings
  bool private = false,           // ← RLS on realtime.messages is consulted
  bool replicationReady = false,
});

// realtime_client-2.13.0/lib/src/types.dart:146-156
const ReplayOption({ required int since /* unix ms */, int? limit /* max 25 */ });

// realtime_client-2.13.0/lib/src/realtime_channel.dart:445-454
RealtimeChannel onBroadcast({
  required String event,
  required void Function(Map<String, dynamic> payload) callback,
});

// realtime_client-2.13.0/lib/src/realtime_channel.dart:768-777
Future<ChannelResponse> sendBroadcastMessage({
  required String event,
  required Map<String, dynamic> payload,
});

// realtime_client-2.13.0/lib/src/realtime_channel.dart:141-144
RealtimeChannel subscribe([
  void Function(RealtimeSubscribeStatus status, Object? error)? callback,
  Duration? timeout,
]);

// realtime_client-2.13.0/lib/src/types.dart:133
enum RealtimeSubscribeStatus { subscribed, channelError, closed, timedOut }

// Presence — realtime_client-2.13.0/lib/src/realtime_channel.dart:312-346, 467-506
List<SinglePresenceState> presenceState();
Future<ChannelResponse> track(Map<String, dynamic> payload, [Map<String, dynamic> opts = const {}]);
Future<ChannelResponse> untrack([Map<String, dynamic> opts = const {}]);
RealtimeChannel onPresenceSync(void Function(RealtimePresenceSyncPayload payload) callback);
RealtimeChannel onPresenceJoin(void Function(RealtimePresenceJoinPayload payload) callback);
RealtimeChannel onPresenceLeave(void Function(RealtimePresenceLeavePayload payload) callback);

// SupabaseClient.rpc — supabase-2.16.0/lib/src/supabase_client.dart:241-248
PostgrestFilterBuilder<T> rpc<T>(String fn, {Map<String, dynamic>? params, get = false});
```
`[VERIFIED: local pub cache source, C:\Users\marti\AppData\Local\Pub\Cache\hosted\pub.dev\]`

**`setAuth` is automatic — do not call it manually.** `SupabaseClient._handleTokenChanged` (`supabase-2.16.0/lib/src/supabase_client.dart:411-429`) subscribes to `auth.onAuthStateChangeSync` and calls `realtime.setAuth(token)` on `initialSession`, `tokenRefreshed` and `signedIn`, and `realtime.setAuth(_supabaseKey)` on `signedOut`. `[VERIFIED: local pub cache source]`

The consequence is a **cold-start race**: a private channel subscribed before `AuthChangeEvent.initialSession` has fired will join with the anon key and be rejected by the `realtime.messages` policies. Gate the buddy channel subscription on `authSessionProvider` having a non-null value (`lib/app/providers.dart:100-103`), exactly as `syncServiceProvider` already does at `lib/app/providers.dart:48-57`.

---

## Proposed Supabase Schema (migration `0011_buddy_sessions.sql`)

Follow the shape of `supabase/migrations/0009_fasting_schedules.sql` — a self-contained migration that spells out its own RLS, triggers and publication wiring rather than editing the `0003`/`0004`/`0005` DO-block loops that already ran.

```sql
-- ── Tables ───────────────────────────────────────────────────────────────

create table public.buddy_sessions (
  id          uuid primary key default gen_random_uuid(),
  created_by  uuid not null references auth.users(id) on delete cascade,
  created_at  timestamptz not null default now(),
  ended_at    timestamptz,
  -- The per-session monotonic counter. Never a sequence: see § Sequence
  -- Numbering. Only buddy_append_event() ever advances it, under FOR UPDATE.
  next_seq    bigint not null default 1
);

create table public.buddy_participants (
  buddy_session_id     uuid not null references public.buddy_sessions(id) on delete cascade,
  user_id              uuid not null references auth.users(id) on delete cascade,
  -- Links to WorkoutSessions.sessionUuid on that participant's device. This is
  -- the ONLY reference to the partner's workout, and it is a bare identifier —
  -- it grants no read access to workout_sessions (0003 still gates that).
  workout_session_uuid uuid not null,
  -- Minimal display identity, denormalised at join time by the joining user
  -- themselves. See § Minimal Participant Display Identity.
  display_name         text,
  avatar_url           text,
  joined_at            timestamptz not null default now(),
  left_at              timestamptz,
  primary key (buddy_session_id, user_id)
);

create table public.buddy_session_events (
  buddy_session_id uuid   not null references public.buddy_sessions(id) on delete cascade,
  seq              bigint not null,
  actor_user_id    uuid   not null,
  kind             text   not null,   -- add | remove | reorder | replace | session_ended
  payload          jsonb  not null,
  created_at       timestamptz not null default now(),
  primary key (buddy_session_id, seq)
);

-- Invisible to every client. No RLS policy is created for this table at all,
-- and all DML privileges are revoked — same "only a SECURITY DEFINER routine
-- writes here" idiom as public.sync_tombstones in 0005.
create table public.buddy_join_tokens (
  token_hash       bytea primary key,          -- sha256(token) — core PG, no pgcrypto
  buddy_session_id uuid not null references public.buddy_sessions(id) on delete cascade,
  created_by       uuid not null,
  expires_at       timestamptz not null,
  consumed_at      timestamptz,
  consumed_by      uuid
);
```

### The non-recursive participation helper

```sql
-- LANGUAGE plpgsql is load-bearing, not stylistic. A LANGUAGE sql function is
-- inlined by the planner; inlining discards the SECURITY DEFINER context, the
-- inner select is re-subjected to RLS on buddy_participants, and the policy
-- that called this helper recurses into itself. plpgsql is never inlined.
--
-- `set search_path = ''` + fully qualified names for the same reason 0005
-- documents: a definer function with a mutable search_path is a privilege
-- escalation vector.
create function public.is_buddy_participant(p_session uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return exists (
    select 1
    from public.buddy_participants
    where buddy_session_id = p_session
      and user_id = (select auth.uid())
      and left_at is null
  );
end;
$$;

-- Unlike 0005's record_sync_tombstone(), EXECUTE is NOT revoked here: policies
-- are evaluated as the querying role, so `authenticated` must be able to call
-- this or every buddy select fails.
grant execute on function public.is_buddy_participant(uuid) to authenticated;
```
`[CITED: dev.to/bairescodeai/infinite-recursion-in-postgres-rls-a-security-definer-gotcha-1916]` `[CITED: github.com/orgs/supabase/discussions/47525]`

### Policies

```sql
alter table public.buddy_sessions      enable row level security;
alter table public.buddy_participants  enable row level security;
alter table public.buddy_session_events enable row level security;
alter table public.buddy_join_tokens   enable row level security;

-- buddy_sessions: readable by participants, created by yourself, never
-- client-updated (next_seq must only move inside buddy_append_event).
create policy buddy_sessions_select_participant
  on public.buddy_sessions for select
  using (public.is_buddy_participant(id) or created_by = (select auth.uid()));
create policy buddy_sessions_insert_own
  on public.buddy_sessions for insert
  with check (created_by = (select auth.uid()));
revoke update, delete on public.buddy_sessions from anon, authenticated;

-- buddy_participants: readable by participants. Writes go through the join
-- RPC only, so no insert policy exists and DML is revoked — a client cannot
-- add itself to someone else's session.
create policy buddy_participants_select_participant
  on public.buddy_participants for select
  using (public.is_buddy_participant(buddy_session_id));
-- The one client-writable field: your own left_at (the "leave" action).
create policy buddy_participants_update_self
  on public.buddy_participants for update
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
revoke insert, delete on public.buddy_participants from anon, authenticated;

-- buddy_session_events: readable by participants, written only by the RPC.
create policy buddy_session_events_select_participant
  on public.buddy_session_events for select
  using (public.is_buddy_participant(buddy_session_id));
revoke insert, update, delete on public.buddy_session_events from anon, authenticated;

-- buddy_join_tokens: no policy at all. RLS on + zero policies = deny all.
revoke all on public.buddy_join_tokens from anon, authenticated;
```

**Why this is non-recursive:** every policy's predicate goes through `is_buddy_participant`, which runs as the function owner and therefore bypasses RLS on `buddy_participants`. `buddy_participants_select_participant` referencing a helper that reads `buddy_participants` would be a textbook recursion — the `plpgsql SECURITY DEFINER` boundary is what breaks it. `[CITED: dev.to/bairescodeai/...]`

### RLS on `realtime.messages`

```sql
-- Receiving broadcast on the buddy topic. topic() returns the channel name the
-- client is joining, i.e. 'buddy:<uuid>'.
create policy buddy_can_receive_broadcast
  on realtime.messages for select
  to authenticated
  using (
    realtime.messages.extension = 'broadcast'
    and realtime.topic() like 'buddy:%'
    and public.is_buddy_participant(substring(realtime.topic() from 7)::uuid)
  );

-- ONLY needed if presence is used. Clients never insert 'broadcast' rows —
-- all broadcast originates from the buddy_session_events trigger.
create policy buddy_can_send_presence
  on realtime.messages for insert
  to authenticated
  with check (
    realtime.messages.extension = 'presence'
    and realtime.topic() like 'buddy:%'
    and public.is_buddy_participant(substring(realtime.topic() from 7)::uuid)
  );
```
`[CITED: supabase.com/docs/guides/realtime/authorization]` — RLS is enabled by default on `realtime.messages`; `realtime.topic()` returns the topic being joined; `SELECT` governs receiving, `INSERT` governs sending; `extension` is `'broadcast'` or `'presence'`.

> The docs' own example uses `exists (select user_id from rooms_users where … and room_topic = (select realtime.topic()))`. Storing a `topic` column on `buddy_sessions` and comparing directly is a viable alternative to the `substring(...)::uuid` parse and is arguably more robust (no cast failure on a malformed topic). **Recommended:** add `topic text generated always as ('buddy:' || id::text) stored` to `buddy_sessions` and write the policy as an `exists` join, matching the documented pattern exactly. Guard the cast either way — a client can join any topic string it likes.

### The append RPC and its broadcast trigger

```sql
create function public.buddy_append_event(
  p_buddy_session_id uuid,
  p_kind             text,
  p_payload          jsonb
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid  uuid := (select auth.uid());
  v_seq  bigint;
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  -- Participation is re-checked on EVERY append. This is what makes BUD-06
  -- hold: a partner who has left (left_at set) or whose session ended cannot
  -- write, even if their websocket is still open (see § Pitfall 3).
  if not exists (
    select 1 from public.buddy_participants p
    join public.buddy_sessions s on s.id = p.buddy_session_id
    where p.buddy_session_id = p_buddy_session_id
      and p.user_id = v_uid
      and p.left_at is null
      and s.ended_at is null
  ) then
    raise exception 'not a participant' using errcode = '42501';
  end if;

  -- Per-session counter under a row lock. The lock is held to commit, so the
  -- second writer cannot obtain a number until the first is visible: gapless
  -- AND commit-ordered. Trivial at two participants.
  select next_seq into v_seq
    from public.buddy_sessions
   where id = p_buddy_session_id
     for update;

  insert into public.buddy_session_events
    (buddy_session_id, seq, actor_user_id, kind, payload)
  values (p_buddy_session_id, v_seq, v_uid, p_kind, p_payload);

  update public.buddy_sessions set next_seq = v_seq + 1 where id = p_buddy_session_id;

  return v_seq;
end;
$$;

grant execute on function public.buddy_append_event(uuid, text, jsonb) to authenticated;

-- Broadcast is derived from the durable row, not sent alongside it.
create function public.buddy_broadcast_event()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform realtime.send(
    jsonb_build_object(
      'seq',   new.seq,
      'kind',  new.kind,
      'actor', new.actor_user_id,
      'payload', new.payload
    ),
    'buddy_event',                              -- event name
    'buddy:' || new.buddy_session_id::text,     -- topic
    true                                         -- private
  );
  return null;
end;
$$;

revoke execute on function public.buddy_broadcast_event() from public, anon, authenticated;

create trigger t_buddy_broadcast_event
  after insert on public.buddy_session_events
  for each row execute function public.buddy_broadcast_event();
```

> **Verify before writing the migration:** the exact argument order and types of `realtime.send`. The Supabase docs describe it as `realtime.send(payload, event, topic, is_private)` and the last argument as the private flag `[CITED: supabase.com/docs/guides/realtime/broadcast]`, but no page in the docs prints the full `create function` signature. Run `\df+ realtime.send` (or `select pg_get_functiondef('realtime.send'::regproc)`) against the live project and pin the real signature. This is `[ASSUMED]` until then. `realtime.broadcast_changes(topic, event, operation, table, schema, NEW, OLD)` is the alternative, but it produces a Postgres-Changes-shaped payload and is a poor fit for a hand-built event envelope.

**Do NOT add these tables to `supabase_realtime` publication.** Unlike `0009_fasting_schedules.sql:40`, the buddy tables are not consumed via `postgres_changes` — they are consumed via broadcast. Adding them to the publication would create a second, unauthorised delivery path.

---

## Sequence Numbering

**The problem, stated precisely:** `bigserial` / `GENERATED ALWAYS AS IDENTITY` allocates its value *before* commit and `nextval` is never rolled back. Transaction B can therefore take `seq = 13`, commit, and be read by a consumer that advances `lastSeen = 13`, while transaction A — holding `seq = 12` — commits afterwards and is permanently skipped. `[CITED: event-driven.io/en/ordering_in_postgres_outbox/]` `[CITED: cybertec-postgresql.com/en/gaps-in-sequences-postgresql/]`

**The chosen fix:** `SELECT next_seq FROM buddy_sessions WHERE id = ? FOR UPDATE` inside `buddy_append_event`. The row lock is held until commit, so writer B blocks until A's row is visible. This produces a gapless, commit-ordered sequence per session.

The standard objection — "manual gapless sequences serialise all writes and are an unacceptable bottleneck" — is a throughput argument that does not apply: this session has exactly **two** writers making at most a handful of choreography changes per minute, and the lock is scoped to a single `buddy_sessions` row (not global).

**Rejected alternative:** `xid8` + `pg_snapshot_xmin(pg_current_snapshot())` filtering. Rigorous and correct for high-throughput outboxes, but it forces every client query to carry a compound cursor `(transaction_id, position)` and does not give a human-readable "event #7 of this session". Not worth the complexity at n=2. `[CITED: event-driven.io/en/ordering_in_postgres_outbox/]`

---

## Event Schema and Ordering

### Address slots by stable id, never by index

The single most common way a real-time reorder protocol breaks is index-based addressing: "remove item 3" is not idempotent, is not commutative, and means different things after any other event lands. Mint a `slotId` (uuid) for every shared choreography slot at the moment it is added, and address every subsequent event by `slotId`.

```jsonc
// kind: "add"
{ "slotId": "…uuid…",
  "exerciseRef": { "uuid": null, "slug": "barbell-back-squat" },
  "afterSlotId": "…uuid…" | null,        // null = prepend
  "equipmentVariant": "barbell" }

// kind: "remove"
{ "slotId": "…uuid…" }

// kind: "reorder"                        // full ordering, LWW on the whole list
{ "order": ["slot-a", "slot-b", "slot-c"] }

// kind: "replace"
{ "slotId": "…uuid…",
  "exerciseRef": { "uuid": null, "slug": "front-squat" } }

// kind: "session_ended"
{ "endedBy": "…user uuid…" }
```

`reorder` carrying the **full** ordering rather than an `(oldIndex, newIndex)` delta makes it idempotent and makes simultaneous reorders resolve cleanly: the higher `seq` simply wins the whole list. This maps directly onto the existing `WorkoutsRepository.reorderWorkoutExercises` (`workouts_repository.dart:735-762`), which already rewrites every `orderIndex` in one transaction rather than swapping two rows.

### Conflict resolution / tie-break

**There are no ties.** The server assigns `seq` under a row lock, so a total order exists before any client sees anything. The tie-break rule the CONTEXT left open is therefore: **strict `seq` order, last-writer-wins per `slotId`, whole-list-wins for `reorder`.**

Practical consequences the plan must handle:
- **Optimistic local application.** The initiating client applies the change locally, then calls the RPC and learns its `seq`. When the broadcast echo arrives, dedupe by `(buddySessionId, seq)` and skip. If the RPC *fails*, roll back the optimistic change.
- **Interleaving.** If A's optimistic reorder is superseded by B's reorder at a higher `seq`, A's list visibly snaps to B's. That is correct and should be a designed animation, not a bug report.
- **Does the sender get its own broadcast?** With broadcast-from-database the fan-out is server-side from the WAL — there is no originating socket to exclude, so both clients should receive it. `RealtimeChannelConfig.self` only governs *client-sent* websocket broadcasts. Because the RPC returns the assigned `seq` and the client dedupes on it, the answer does not actually matter — **design so that it doesn't**. `[ASSUMED — verify on the live project]`

### Reconnect and replay protocol

Order matters, and the naive order loses events:

```
WRONG:  fetch backlog (seq > lastSeen)  →  subscribe
        ↳ any event committed in the gap between the two is lost forever

RIGHT:  1. subscribe to buddy:<id>, buffering every inbound event
        2. select * from buddy_session_events
             where buddy_session_id = ? and seq > lastSeen order by seq
        3. apply the backlog in seq order
        4. drain the buffer, dropping anything with seq <= the highest applied
        5. from here on, apply live events in seq order; if a seq gap appears,
           re-run step 2 rather than applying out of order
```

`lastSeen` lives in a local Drift table (see § Drift v29) and must be advanced **only after** the event has been applied and committed locally, so a crash mid-apply replays rather than skips.

**Idempotency requirements for `apply(event)`** — every handler must tolerate being run twice:
- `add`: no-op if a local `WorkoutExercises` row is already mapped to that `slotId`.
- `remove`: no-op if the `slotId` has no local mapping.
- `reorder`: naturally idempotent (it writes an absolute ordering).
- `replace`: no-op if the slot already points at the resolved exercise.

### Broadcast Replay as a fast path (optional)

`RealtimeChannelConfig(private: true, replay: ReplayOption(since: …, limit: 25))` will re-deliver up to 25 DB-published messages from the last 72 hours on subscribe. `realtime.messages` is stored in daily partitions and partitions older than 72 hours are dropped, so a message survives **at least 72 hours and at most 4 days**. `[CITED: supabase.com/docs/guides/realtime/limits]` `[CITED: supabase.com/blog/realtime-broadcast-replay]`

This can shave a round trip off the common "backgrounded for two minutes" reconnect, but it cannot replace the durable log (25-message cap, 72-hour window). If used, replayed messages carry `meta.replayed` so they can be distinguished — but since the client dedupes by `seq` anyway, they need no special handling. **Recommendation: skip it in the MVP.** It is a pure optimisation on a path that is already correct, and it adds a second code path to test.

---

## Join Token Design

### Minting (`buddy_create_session` RPC)

```sql
create function public.buddy_create_session(
  p_workout_session_uuid uuid,
  p_display_name         text,
  p_avatar_url           text
)
returns table (buddy_session_id uuid, join_token text)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid     uuid := (select auth.uid());
  v_session uuid;
  v_token   text;
begin
  if v_uid is null then raise exception 'not authenticated' using errcode = '42501'; end if;

  -- gen_random_uuid() is core Postgres (13+) and is CSPRNG-backed: ~122 bits
  -- of entropy. No pgcrypto dependency, no schema-qualification question.
  v_token := gen_random_uuid()::text;

  insert into public.buddy_sessions (created_by) values (v_uid) returning id into v_session;

  insert into public.buddy_participants
    (buddy_session_id, user_id, workout_session_uuid, display_name, avatar_url)
  values (v_session, v_uid, p_workout_session_uuid, p_display_name, p_avatar_url);

  -- Only the hash is stored. sha256(bytea) is CORE Postgres (no pgcrypto).
  insert into public.buddy_join_tokens (token_hash, buddy_session_id, created_by, expires_at)
  values (sha256(convert_to(v_token, 'UTF8')), v_session, v_uid, now() + interval '10 minutes');

  return query select v_session, v_token;
end;
$$;
```
`sha256(bytea) → bytea` is a core PostgreSQL binary-string function, not pgcrypto. `[CITED: postgresql.org/docs/17/functions-binarystring.html, Table 9.12]` This removes an entire class of "is pgcrypto installed, and in which schema?" failure from the migration.

### Redeeming (`buddy_join_session` RPC)

```sql
create function public.buddy_join_session(
  p_token                text,
  p_workout_session_uuid uuid,
  p_display_name         text,
  p_avatar_url           text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_tok public.buddy_join_tokens;
begin
  if v_uid is null then raise exception 'invalid or expired join code' using errcode = '42501'; end if;

  -- FOR UPDATE makes check-then-consume atomic: two simultaneous scans of the
  -- same QR cannot both succeed.
  select * into v_tok
    from public.buddy_join_tokens
   where token_hash = sha256(convert_to(p_token, 'UTF8'))
     for update;

  -- ONE generic failure for every reason: not found, expired, already
  -- consumed, session ended, session full. Never leak which — that is an
  -- existence oracle.
  if v_tok.token_hash is null
     or v_tok.expires_at <= now()
     or v_tok.consumed_at is not null
     or v_tok.created_by = v_uid
     or exists (select 1 from public.buddy_sessions
                 where id = v_tok.buddy_session_id and ended_at is not null)
     or (select count(*) from public.buddy_participants
          where buddy_session_id = v_tok.buddy_session_id and left_at is null) >= 2
  then
    raise exception 'invalid or expired join code' using errcode = '42501';
  end if;

  update public.buddy_join_tokens
     set consumed_at = now(), consumed_by = v_uid
   where token_hash = v_tok.token_hash;

  insert into public.buddy_participants
    (buddy_session_id, user_id, workout_session_uuid, display_name, avatar_url)
  values (v_tok.buddy_session_id, v_uid, p_workout_session_uuid, p_display_name, p_avatar_url);

  return v_tok.buddy_session_id;
end;
$$;

grant execute on function public.buddy_create_session(uuid, text, text) to authenticated;
grant execute on function public.buddy_join_session(text, uuid, text, text) to authenticated;
```

### Answering the CONTEXT's open questions

| Question | Recommendation | Rationale |
|----------|----------------|-----------|
| RPC or Edge Function? | **RPC (`plpgsql SECURITY DEFINER`).** | The validation is entirely a database transaction: read + expiry check + atomic consume + participant insert. An Edge Function would add a second deployment artefact, a cold-start, and a network hop, and would still call into Postgres to do the work. The repo has exactly one Edge Function (`supabase/functions/gemini-analyze`) and it exists to hold an *external* API secret — not this shape. |
| Client-side table read? | **No, never.** | `buddy_join_tokens` has RLS on and zero policies plus revoked DML — invisible to every client. A client-side read would require a policy that lets an unauthenticated-for-that-session user read the token row, which is the exact leak the token is meant to prevent. |
| Expiry? | **10 minutes.** | Matches the real use case ("show your phone across the gym floor, right now") and the widely-used `nonces` default. `[CITED: makerkit.dev/blog/tutorials/one-time-tokens-supabase-postgres]` Put the interval in one named SQL constant so it is a one-line change. |
| Single-use or once-per-participant? | **Single-use.** | This phase caps a session at two participants, so "once per participant" and "single-use" are the same thing minus a counter. Single-use is simpler and has a clearly stated invariant. |
| Preventing a leaked QR screenshot from granting access after the session ends? | **Four independent gates in `buddy_join_session`:** `expires_at <= now()`, `consumed_at is not null`, `buddy_sessions.ended_at is not null`, and the participant cap. Each alone would be sufficient; together the token is inert the instant *any* of them trips. | Defence in depth. Note that a screenshot taken and redeemed *within* the 10-minute window by a third party is a real (if narrow) risk — the QR is a bearer token. Displaying it full-screen with a visible countdown and dismissing it as soon as a partner joins is the mitigation. |
| Brute force? | Not a practical concern. | 122 bits of CSPRNG entropy, single-use, 10-minute window. Do add an index on `token_hash` (it is the primary key, so this is free) and keep the failure message generic. |
| Cleanup? | A daily `pg_cron` job deleting `expires_at < now() - interval '1 day'`. | Matches `0006_sync_tombstone_retention.sql`'s existing retention idiom — read that file for the repo's scheduling convention before writing it. |

### QR payload

Recommend `herculex://buddy/join?t=<uuid>` — ~40 characters, so the QR stays at a low version (large modules, fast scan in poor gym lighting), and the custom scheme leaves room for a deep link later without a format change. The MVP scanner just parses the `t=` parameter. Do **not** embed the `buddySessionId` in the QR — the token alone must be sufficient, otherwise the QR carries information a leak could use.

`mobile_scanner`'s `MobileScannerController` needs `formats: const [BarcodeFormat.qrCode]` (the existing `barcode_scanner_view.dart:41-48` lists only 1D retail formats and would never fire on a QR). Clone that file rather than parameterising it — the two flows have different formats, different result types and different error copy.

---

## Minimal Participant Display Identity

**There is no server-side profile table.** `0003_sync_rls.sql:9-21` lists all 35 synced tables and contains no `profiles`; `lib/features/profile/data/local_profile_repository.dart:1-16` stores the profile in `SharedPreferences` under `herculex.profile` and never syncs it. `[VERIFIED: codebase]`

So the question "which policy grants a partner read access to the other's name and avatar?" has a clean answer: **none — because there is nothing to grant access to.** The joining user writes their own `display_name` and `avatar_url` into `buddy_participants` at join time, and the partner reads that row via the existing participation policy. This is both the minimal surface BUD-05 asks for and the only option that does not require inventing a cross-user-readable profile table.

Store nothing else. A denormalised snapshot going stale is the correct trade for a session that lasts an hour.

---

## Drift Migration to v29

**Current state:** `schemaVersion => 28` at `lib/data/local/database.dart:81`. `[VERIFIED: codebase]` Note `lib/data/local/database.dart` is currently **modified in the working tree** — read the real file before editing.

### New local tables — all local-only, following the Phase 10 precedent

Phase 10 established that tables which duplicate state owned elsewhere should carry **no** `SyncColumns`/`SyncTombstone`, appear in **neither** `syncedTableNames` nor `syncTableSpecs`, and get **no** outbox trigger (`database.dart:644-652`, `test/rep_local_only_test.dart`). The buddy mirror tables fit exactly: the authoritative copy is in Postgres and reaches the device via the buddy channel, not via `SyncService`. Pushing them through the outbox would create a second, conflicting delivery path for the same rows.

```dart
/// Local mirror of the buddy sessions this device participates in. Local-only:
/// the authoritative rows live in public.buddy_sessions / buddy_participants
/// and arrive over the buddy channel, never through SyncService.
class BuddySessionsLocal extends Table {
  TextColumn get buddySessionId => text()();           // uuid, from the server
  IntColumn  get workoutSessionId => integer()
      .references(WorkoutSessions, #id, onDelete: KeyAction.cascade)();
  TextColumn get role => text()();                     // 'host' | 'guest'
  TextColumn get partnerDisplayName => text().nullable()();
  TextColumn get partnerAvatarUrl => text().nullable()();
  /// Highest applied event seq. Advanced only after the event has been
  /// applied and committed, so a crash mid-apply replays rather than skips.
  IntColumn  get lastSeenSeq => integer().withDefault(const Constant(0))();
  DateTimeColumn get joinedAt => dateTime()();
  DateTimeColumn get endedAt => dateTime().nullable()();
  @override Set<Column> get primaryKey => {buddySessionId};
}

/// slotId -> local workoutExerciseId. This is what makes remove/reorder/replace
/// addressable across two devices whose WorkoutExercises.id values differ.
class BuddyChoreographySlots extends Table {
  TextColumn get buddySessionId => text()();
  TextColumn get slotId => text()();                   // uuid, minted by the adder
  IntColumn  get workoutExerciseId => integer()
      .references(WorkoutExercises, #id, onDelete: KeyAction.cascade)();
  @override Set<Column> get primaryKey => {buddySessionId, slotId};
}
```

### The one change to a synced table

```dart
// WorkoutSessions (tables.dart:144) gains:
/// Links this session to its partner's session for BUD-07's later VS
/// comparison. Nullable; null for every solo workout.
TextColumn get buddySessionId => text().nullable()();
```

This column **must** sync (BUD-07 depends on it existing on both devices' rows). Two things follow:

1. **`sync_table_specs.dart` needs no change.** `SyncService._buildRemotePayload` derives the remote payload generically from whatever local columns exist beyond the registered FK / local-only / dateTime ones (`lib/data/sync/sync_service.dart:455-520`, and the v28 migration comment at `database.dart:667-676` states this explicitly). `[VERIFIED: codebase]`
2. **The Supabase side needs `alter table public.workout_sessions add column buddy_session_id uuid;`** in the same migration. This adds a column; it does **not** touch any policy, so `0003` stays frozen.

### Migration block — reuse the v28 `to >=` guard idiom

```dart
if (from < 29) {
  await m.createTable(buddySessionsLocal);
  await m.createTable(buddyChoreographySlots);
  // No sync_uuid index and no installSyncTriggers() call: these are
  // local-only, same as the v26 rep-tracking block.
}
if (from < 29 && to >= 29) {
  // addColumn has no IF NOT EXISTS guard and SchemaVerifier.migrateAndValidate
  // fakes intermediate target versions, so this needs the `to` half of the
  // guard AND the try/catch-per-column idiom — exactly as the v28 block at
  // database.dart:667-700 documents.
  await tryAddColumn(workoutSessions, workoutSessions.buddySessionId);
}
```

### Migration test chores (non-optional, and easy to forget)

Per `test/migration_test.dart:1-9`:

```bash
dart run drift_dev schema dump lib/data/local/database.dart drift_schemas/
dart run drift_dev schema generate drift_schemas/ test/generated_migrations/
```

Then:
- bump the expected version in `test/migration_test.dart` from 28 to 29 (three call sites: the current-schema test plus every `startAt(n)` replay's `migrateAndValidate(db, 28)`);
- add a `startAt(28)` replay test following the v23/v24/v25/v26 pattern;
- add `test/schema_v29_test.dart` following `test/schema_v28_test.dart`;
- confirm `test/generated_migrations/schema_v29.dart` was generated.

---

## Runtime State Inventory

> This is not a rename/refactor phase, but it *does* introduce durable state outside git, so the categories are answered explicitly.

| Category | Items found | Action required |
|----------|-------------|------------------|
| Stored data | New Postgres tables `buddy_sessions`, `buddy_participants`, `buddy_session_events`, `buddy_join_tokens` in the **live** Supabase project (`ldzgyzigvbwofbswitrv` — the Herculex project; note the memory record that `jioesomepkauponjrena` is SummitSki and was wrongly configured repo-wide until 2026-08-15). New local Drift tables at v29. New nullable column on the existing `workout_sessions` (both local and remote). | Ship `supabase/migrations/0011_buddy_sessions.sql` **and apply it to the live project** — the repo has no Supabase CLI installed, so this is a manual/dashboard step the plan must name as a checkpoint. |
| Live service config | RLS policies on `realtime.messages` are Supabase-managed schema, applied by migration but **not** visible in any local schema dump. `pg_cron` job for token cleanup (if added) lives in `cron.job`, not in git. | Both must be in the migration file so they are reproducible; add a verification query to the plan (`select policyname from pg_policies where schemaname='realtime'`). |
| OS-registered state | None — no notification channels, task scheduler entries, pm2 processes or launchd plists are involved. Verified: this phase adds no native/Kotlin code and no new foreground service. | None. |
| Secrets / env vars | The live integration test needs `SUPABASE_TEST_EMAIL`/`_PASSWORD` **and** `SUPABASE_TEST_EMAIL_2`/`_PASSWORD_2`, which **already exist** in `.secrets/live_sync.json` (`test/sync/live_round_trip_test.dart:45-48`). No new secret. | None — reuse the existing two-account fixture. |
| Build artifacts | `test/generated_migrations/schema_v29.dart` and `drift_schemas/drift_schema_v29.json` are generated, not hand-written, and will be stale until `drift_dev schema dump`/`generate` are re-run. `*.g.dart` for the new Drift tables likewise. | Re-run `build_runner` and both `drift_dev schema` commands; commit the outputs. |

---

## Don't Hand-Roll

| Problem | Don't build | Use instead | Why |
|---------|-------------|-------------|-----|
| Total ordering of concurrent events | A client timestamp + tie-break on user id | `buddy_append_event`'s `SELECT … FOR UPDATE` counter | Client clocks drift; two phones in a gym can be minutes apart. The DB already has a serialisation point. |
| Delivering the log alongside the broadcast | Client sends broadcast, then inserts the log row (or vice versa) | `realtime.send()` from an `AFTER INSERT` trigger | Two client operations can diverge (network drop between them). One transaction cannot. |
| Cross-device exercise identity | A new "exercise fingerprint" or name-matching scheme | `SyncIdResolver.resolveCatalogueRefForPush` / `…ForPull` (`lib/data/sync/sync_id_resolver.dart:56-96`) | The problem is already solved, already tested (`test/sync/sync_payload_test.dart`), and Postgres already enforces exactly-one-of via a check constraint on the sync tables. |
| RLS participation check | Inlining an `exists (select … from buddy_participants …)` into each policy | One `plpgsql SECURITY DEFINER` helper | The inline version recurses; the `LANGUAGE sql` version *also* recurses after inlining. Only `plpgsql` works. |
| One-time token consume | `select` then `update` in two statements from the client | One `SECURITY DEFINER` RPC with `FOR UPDATE` | Two simultaneous scans of the same QR both succeed in the two-statement version. |
| Token secrecy | An obfuscated/encoded session id | `gen_random_uuid()` + `sha256()` at rest + RLS-deny table | An id derived from the session id is guessable from any leaked session id. |
| QR rendering | A `CustomPainter` over the `qr` matrix | `qr_flutter` (or `pretty_qr_code`) | Quiet zone, module rounding, error-correction level and finder-pattern rendering are all places to get scanning reliability subtly wrong. |
| Reordering a shared list | `(oldIndex, newIndex)` deltas | Full absolute ordering per event | Deltas are neither idempotent nor commutative; absolute orderings are both. |
| Presence / "is my buddy online" | A heartbeat table with a polling timer | Realtime presence (`track`/`onPresenceSync`) | Presence already handles the disconnect detection, the state CRDT and the join/leave diffing. |

**Key insight:** every "hard" part of this phase — ordering, atomicity, identity, secrecy — has an existing solution *inside the two systems the app already uses*. The failure mode for this phase is not missing capability, it is reaching for a client-side approximation of something Postgres or the Realtime server already guarantees.

---

## Common Pitfalls

### Pitfall 1: `LANGUAGE sql` SECURITY DEFINER helper still recurses
**What goes wrong:** The migration applies cleanly, then every read of `buddy_participants` fails at runtime with `infinite recursion detected in policy for relation "buddy_participants"`.
**Why it happens:** Postgres inlines simple SQL functions during planning. Inlining discards the `SECURITY DEFINER` context, so the inner `select` is re-subjected to the very policy that called it.
**How to avoid:** `LANGUAGE plpgsql` — plpgsql functions are never inlined. Add `STABLE`, `SET search_path = ''`, and fully-qualified names.
**Warning signs:** The helper is written as `RETURNS boolean AS $$ SELECT EXISTS(...) $$ LANGUAGE sql`. If you can read the body as a single `SELECT`, it will be inlined.
`[CITED: dev.to/bairescodeai/infinite-recursion-in-postgres-rls-a-security-definer-gotcha-1916]`

### Pitfall 2: Subscribing to a private channel before auth has propagated
**What goes wrong:** The channel subscription fails with a `channelError` and the buddy session silently never goes live, usually only on cold start or after a long background.
**Why it happens:** `realtime.setAuth()` is driven by `auth.onAuthStateChangeSync` (`supabase-2.16.0/lib/src/supabase_client.dart:399-429`). Before `AuthChangeEvent.initialSession` fires, the socket still carries the anon key, and the `realtime.messages` policies are `to authenticated`.
**How to avoid:** Gate the buddy channel on `authSessionProvider` resolving non-null, mirroring `syncServiceProvider` (`lib/app/providers.dart:48-57`). Always pass the `subscribe` status callback and surface `channelError` — never fire-and-forget.
**Warning signs:** `channel.subscribe()` called with no callback argument.
`[VERIFIED: local pub cache source]`

### Pitfall 3: Realtime authorization is cached for the connection's lifetime
**What goes wrong:** A partner who leaves (or whose session ends) keeps receiving broadcast events until they reconnect. The UI on their device continues to update from a session they are no longer in.
**Why it happens:** "Client access policies are cached for the duration of the connection. Your database is not queried for every Channel message." The cache refreshes only on connect/subscribe or when a new JWT is pushed via the `access_token` message. `[CITED: supabase.com/docs/guides/realtime/authorization]`
**How to avoid:** Two layers. (a) **Writes are always safe** — `buddy_append_event` re-checks participation and `ended_at` on every call, so a stale subscriber can listen but can never write. This is what makes BUD-06 hold. (b) Broadcast an explicit `session_ended` / `participant_left` event; clients act on it by calling `removeChannel` and tearing down their local buddy state. Do not rely on the policy to do the eviction.
**Warning signs:** A plan task that says "revoke access by setting `left_at`" with no accompanying broadcast event.
**Be honest about it:** this is a platform limitation, not something the plan can fully close. Documenting it is better than pretending otherwise.

### Pitfall 4: `bigserial` on the event log
**What goes wrong:** Under simultaneous changes from both participants, one event is silently and permanently skipped on the other device. Rare, non-reproducible, and looks like a network glitch.
**Why it happens:** See § Sequence Numbering — sequence values are allocated pre-commit and never rolled back.
**How to avoid:** The per-session `FOR UPDATE` counter.
**Warning signs:** `seq bigint generated always as identity` or `bigserial` anywhere in the migration.
`[CITED: event-driven.io/en/ordering_in_postgres_outbox/]`

### Pitfall 5: `scope` travelling on the wire
**What goes wrong:** Someone adds `"scope": "mine"` to the event payload "for completeness". A later refactor reads it on the receiving side. Now a `mine` change *is* in the durable log, and a single bug in one `if` makes it visible to the partner. The requirement most likely to break under refactor breaks under refactor.
**Why it happens:** Modelling scope as data rather than as control flow.
**How to avoid:** **`scope` must never be serialised.** The buddy event publisher's public API should have no `scope` parameter at all. The branch lives entirely in the caller: `if (scope == BuddyScope.both) await publisher.append(...)`. A `mine` change simply never reaches the publisher. This is the exact structural pattern Phase 10 used for REP-03 (`test/rep_tracker_write_boundary_test.dart`) — enforce the boundary with a static test rather than a convention.
**Warning signs:** the string `'mine'` appearing anywhere under the buddy transport module, or a `scope` field in the event JSON schema.

### Pitfall 6: `remove` propagating a hard delete of the partner's sets — BUD-03 × BUD-06 collision
**What goes wrong:** A shares a workout, both log three sets of bench press, A removes bench press with scope "both", and B's three logged sets are gone. BUD-06 says a partner "can never … discard the other's sets"; BUD-03 says remove propagates. Both cannot be literally true.
**Why it happens:** `WorkoutsRepository.removeWorkoutExercise` (`workouts_repository.dart:710-733`) hard-deletes `set_accessories`, `set_bands`, `set_entries` and then the `workout_exercises` row, in one transaction. `[VERIFIED: codebase]`
**How to avoid — recommended resolution:** the receiving side's `remove` handler is asymmetric by design:
- If the local exercise has **no** completed/non-empty sets → delete it (matches the initiator's intent, no data lost).
- If it has **any** logged work → **unlink the slot from the buddy choreography and leave the local exercise in place**, with a one-line note in the UI ("Your partner dropped Bench Press — yours is kept"). BUD-06 wins over BUD-03 when they conflict, because BUD-06 is about data loss and BUD-03 is about convenience.

This must be an explicit, documented plan decision with its own test, not an implementation detail. It is also the strongest argument for the CONTEXT's own instruction that scope "must not make 'both' implicit for destructive operations" — consider defaulting `remove` to `mine`.
**Warning signs:** a plan task that describes remove as "apply the same repository call on both devices".

### Pitfall 7: Bolting the buddy channel onto `SupabaseSyncBackendService`
**What goes wrong:** Signing out, or any `SyncService.stop()`, silently kills the live buddy session mid-workout.
**Why it happens:** `SupabaseSyncBackendService` keeps `final Map<String, RealtimeChannel> _channels = {}` keyed by *table name*, and both `dispose()` and the `realtimeHints` stream's `onCancel` iterate the whole map calling `_client.removeChannel` (`lib/data/sync/supabase_sync_backend_service.dart:15, 143-162, 175-181`). A buddy channel stored there is torn down by an unrelated lifecycle. `[VERIFIED: codebase]`
**How to avoid:** A **new** `BuddyChannelService` with its own lifecycle (scoped to the buddy session, not to auth). This answers the CONTEXT's open discretion item with concrete evidence rather than taste. The interface shapes match anyway: the existing class does `postgres_changes` filtered by `user_id`; the buddy channel is a private broadcast room. Different concerns.
**Warning signs:** any diff that adds a method to `SupabaseSyncBackendService`.

### Pitfall 8: A choreography event referencing an exercise the partner does not have
**What goes wrong:** `resolveCatalogueRefForPull` returns `null` and the `add` handler either throws or silently no-ops, so the two exercise lists diverge with no user-visible explanation.
**Why it happens:** Two independent causes, and the plan must handle **both**:
1. **Custom exercise.** `resolveCatalogueRefForPush` returns `(sync_uuid, null)` for `is_custom = true` rows (`sync_id_resolver.dart:70-74`). That uuid exists only in the owner's `exercise_catalog` and, crucially, only in *their* Supabase rows — `0003`'s `exercise_catalog_select_own` policy means the partner literally cannot read it.
2. **Catalogue drift.** A *seeded* slug is missing if the partner is on an older build with an older `assets/data/exercises.json`. This is not hypothetical — `assets/data/exercises.json` is modified in the current working tree.
**How to avoid:**
- **Sender side (primary):** before offering scope "both", check `ExerciseCatalog.isCustom`. If custom, force `mine` and say why ("Custom exercises stay on your device"). No data crosses users, nothing to leak, nothing to reconcile.
- **Receiver side (safety net, required regardless):** an unresolvable `exerciseRef` creates the slot as a visible placeholder — "Partner's exercise (not in your catalogue)" — that participates in ordering and can be replaced locally, rather than being dropped. Silent divergence is the failure mode to avoid.
- **Rejected: materialising the custom exercise on the partner's device.** A locally-inserted `ExerciseCatalog` row carries `SyncColumns`/`SyncTombstone` and an outbox trigger, so it would immediately push to Supabase **under the partner's own `user_id`** — permanently copying one user's authored content into another's account, surviving the session, and appearing in their exercise picker forever. That is a BUD-05-adjacent content leak with no clean undo. If a future phase wants this, it needs its own consent flow and a `local_only` catalogue flag.
**Warning signs:** an `add` handler with `if (localId == null) return;`.

### Pitfall 9: Forgetting the drift schema regeneration chores
**What goes wrong:** `test/migration_test.dart` fails with a schema mismatch that reads like a migration bug but is actually a stale dump.
**Why it happens:** `drift_dev schema dump` only captures the *current* version, so the snapshot and the generated fixtures must be regenerated on every `schemaVersion` bump. The header comment at `test/migration_test.dart:1-9` says so explicitly.
**How to avoid:** Make the two `drift_dev` commands and the three `migration_test.dart` version-literal updates explicit numbered steps in the plan, not a "and update the tests" bullet.

---

## Code Examples

### Subscribing to the buddy channel

```dart
// Verified against realtime_client 2.13.0 source + supabase.com/docs/guides/realtime/authorization
final channel = client.channel(
  'buddy:$buddySessionId',
  opts: const RealtimeChannelConfig(private: true),
);

channel
    .onBroadcast(
      event: 'buddy_event',
      callback: (payload) => _enqueue(BuddyEvent.fromJson(payload)),
    )
    .onPresenceSync((_) => _onPresence(channel.presenceState()))
    .subscribe((status, error) async {
      if (status == RealtimeSubscribeStatus.subscribed) {
        await channel.track({'user_id': userId, 'display_name': displayName});
        await _backfillFrom(lastSeenSeq);   // step 2-4 of the replay protocol
      } else {
        _onChannelProblem(status, error);   // never swallow this
      }
    });
```

### Appending an event (the only write path)

```dart
Future<int> append({
  required String buddySessionId,
  required String kind,
  required Map<String, dynamic> payload,
}) async {
  // Returns the server-assigned seq. Dedupe the broadcast echo against it.
  final seq = await client.rpc<int>(
    'buddy_append_event',
    params: {
      'p_buddy_session_id': buddySessionId,
      'p_kind': kind,
      'p_payload': payload,
    },
  );
  return seq;
}
```

### Building an exercise reference the partner can resolve

```dart
// Mirrors SyncService._buildRemotePayload's CatalogueFk branch
// (lib/data/sync/sync_service.dart:485-503) exactly.
final (uuid, slug) = await resolver.resolveCatalogueRefForPush(
  localTable: 'exercise_catalog',
  localId: exerciseId,
  naturalKeyColumn: 'slug',      // _exerciseCatalogFk, sync_table_specs.dart:95-100
  isCustomColumn: 'is_custom',
);
// Exactly one of the two is non-null. uuid != null means custom → do not share.
final ref = {'uuid': uuid, 'slug': slug};
```

### Resolving one on the receiving device

```dart
final localExerciseId = await resolver.resolveCatalogueRefForPull(
  localTable: 'exercise_catalog',
  naturalKeyColumn: 'slug',
  uuid: ref['uuid'] as String?,
  naturalKey: ref['slug'] as String?,
);
if (localExerciseId == null) {
  // Placeholder slot — never a silent return. See Pitfall 8.
  await _addUnresolvableSlot(slotId: slotId, ref: ref);
  return;
}
```

---

## State of the Art

| Old approach | Current approach | When changed | Impact |
|--------------|------------------|--------------|--------|
| `postgres_changes` subscriptions for every real-time need | **Broadcast from the Database** (`realtime.send` / `realtime.broadcast_changes` from a trigger) | Supabase Realtime, 2024–2025 | Scales without a replication slot per table, gives an application-shaped payload instead of a row diff, and makes "durable row then broadcast" atomic. `[CITED: supabase.com/blog/realtime-broadcast-from-database]` |
| Public channels with RLS applied only to the underlying tables | **Realtime Authorization** — RLS policies on `realtime.messages`, `private: true` on the channel | Supabase Realtime 2024 | "Realtime Authorization is required and enabled by default" for DB-published broadcast. A non-private channel simply will not receive them. `[CITED: supabase.com/docs/guides/realtime/broadcast]` |
| Nothing — reconnecting clients started empty | **Broadcast Replay** (`ReplayOption(since:, limit:)`), 72h / 25 messages | `realtime_client` ≥ 2.x, present in 2.13.0 | A cheap fast path for short disconnects. Not a durable log. |
| `supabase_flutter` 2.8.x | **2.17.1** (this repo's resolved version) | — | `RealtimeChannelConfig.private`, `ReplayOption`, `httpSend` and `replicationReady` do not exist in 2.8.x. Plan against the lockfile, not the constraint. |

**Deprecated / outdated:**
- Hand-rolled `SECURITY DEFINER` helpers in `LANGUAGE sql` — still all over the internet, still broken by inlining.
- `alter table realtime.messages enable row level security` — unnecessary; "RLS is enabled by default on table `realtime.messages`". `[CITED: supabase.com/docs/guides/realtime/authorization]`

---

## Assumptions Log

| # | Claim | Section | Risk if wrong |
|---|-------|---------|---------------|
| A1 | `realtime.send(payload jsonb, event text, topic text, private boolean)` — this exact argument order/arity. | Recommended Transport, migration SQL | Migration fails to apply. **Cheap to verify:** `select pg_get_functiondef('realtime.send'::regproc);` on the live project. Docs describe the arguments but never print the signature. |
| A2 | The originating client also receives its own DB-published broadcast (no sender exclusion in WAL fan-out). | Conflict resolution | Low — the design deliberately dedupes by server-assigned `seq`, so it works either way. Verify with a two-client scratch test. |
| A3 | `qr_flutter` 4.1.0 resolves and renders correctly on Flutter 3.44.8 / Dart 3.12.2 despite its 2023 release. | Standard Stack | Medium — pub.dev's 150/160 score implies it analyses clean on current toolchains, but that is not a runtime guarantee. **Mitigation:** `flutter pub add qr_flutter && flutter analyze` as the first task; `pretty_qr_code` 3.6.0 is the drop-in fallback. Planner must gate with `checkpoint:human-verify` (slopcheck cannot cover pub.dev). |
| A4 | 10 minutes is the right token expiry. | Join Token Design | Low — a product judgement, trivially tunable. Worth confirming with the user; a shorter window is safer, a longer one is friendlier across a busy gym. |
| A5 | Single-use (rather than once-per-participant) token semantics. | Join Token Design | Low — equivalent at the two-participant cap this phase enforces. Would need revisiting for BUD-08's >2 participants. |
| A6 | BUD-06 outranks BUD-03 when a `remove` would destroy logged sets. | Pitfall 6 | **High if wrong** — this changes user-visible behaviour and is a genuine requirements conflict, not a technical detail. **This one needs explicit user confirmation before it becomes a locked decision.** |
| A7 | `pg_cron` is available on this Supabase project for token cleanup. | Join Token Design | Low — read `supabase/migrations/0006_sync_tombstone_retention.sql` first; it already solved retention scheduling and whatever mechanism it used will work here. |
| A8 | Adding `buddy_session_id` to `workout_sessions` needs no `sync_table_specs.dart` change. | Drift v29 | Low — asserted directly by `database.dart:667-676` for the v28 columns and confirmed by reading `_buildRemotePayload`. Covered by an existing test path (`test/sync/sync_payload_test.dart`). |
| A9 | Presence is worth using at all for partner liveness. | Architectural map | Low — CONTEXT explicitly leaves "whether partner set-completion is shown live" to discretion. If presence is dropped, the `realtime.messages` INSERT policy can be dropped too, tightening the surface further. |

---

## Open Questions

1. **Does a `remove` with scope "both" delete the partner's logged sets?**
   - What we know: `removeWorkoutExercise` hard-deletes every child `SetEntries` row (`workouts_repository.dart:710-733`). BUD-03 requires remove to propagate; BUD-06 forbids a partner from discarding the other's sets.
   - What's unclear: which requirement the user wants to win. They are genuinely in conflict.
   - Recommendation: BUD-06 wins — a propagated remove unlinks rather than deletes when local sets exist (Pitfall 6). **Raise with the user before planning; this is a product decision, not an implementation one.**

2. **How is the scope choice presented?**
   - What we know: CONTEXT rules out a modal on every change and forbids "both" being implicit for destructive operations.
   - What's unclear: the concrete UX. A segmented default at the top of `ExercisePickerSheet` with a per-action override? A sticky "sharing changes: ON" toggle in the active-workout header with a long-press override?
   - Recommendation: sticky default of `both` for `add`/`reorder`/`replace`, sticky default of `mine` for `remove`, with a visible per-action override. This satisfies "not implicit for destructive operations" without a modal. Needs a UI decision before planning the presentation tasks.

3. **Is a workout-in-progress required on both sides before joining?**
   - What we know: `buddy_participants.workout_session_uuid` is `not null` in the proposed schema, which forces the joiner to have (or start) a session at join time.
   - What's unclear: whether the joiner should be auto-started into a session (via `WorkoutsRepository.startSession`, `workouts_repository.dart:424-439`) or be required to start one first.
   - Recommendation: auto-start on join — it is one call, it matches the "Quick workout" flow already in `quick_add_menu.dart:85-100`, and requiring a manual pre-step before scanning is friction at exactly the wrong moment.

4. **How is the Supabase migration actually applied?**
   - What we know: `supabase` CLI is **not installed** (verified), `psql` is **not installed**, and `docs/rb02-sync-verification.md` records that migrations `0001`–`0007` "are applied" without documenting the mechanism.
   - What's unclear: dashboard SQL editor vs. some other path.
   - Recommendation: read `docs/rb02-sync-verification.md` and treat migration application as an explicit human checkpoint task in the plan, not an assumed step.

---

## Environment Availability

| Dependency | Required by | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Flutter SDK | Everything | ✓ | 3.44.8 stable (2026-07-23) | — |
| Dart SDK | Everything | ✓ | 3.12.2 (repo constraint `^3.11.5`) | — |
| `supabase_flutter` | Realtime broadcast, RPC | ✓ | 2.17.1 resolved | — |
| `realtime_client` | `RealtimeChannelConfig.private`, presence | ✓ | 2.13.0 resolved | — |
| `mobile_scanner` | QR scan-to-join | ✓ | 7.4.0 resolved | — |
| `drift_dev` | v29 schema dump + generated migrations | ✓ | ^2.21.0 (dev dep) | — |
| Two live Supabase test accounts | BUD-05 cross-user RLS test | ✓ | `.secrets/live_sync.json`, used by `test/sync/live_round_trip_test.dart:45-48` | — |
| **Supabase CLI** | Applying `0011_buddy_sessions.sql`; local `supabase start` | ✗ | — | Dashboard SQL editor (this is how `0001`–`0010` appear to have been applied) |
| **`psql`** | Verifying `\df realtime.send`, `pg_policies` inspection | ✗ | — | Supabase dashboard SQL editor |
| `docker` | Local Supabase stack for offline RLS testing | ✗ (not detected) | — | Test against the live project, as `live_round_trip_test.dart` already does |
| `slopcheck` | Package legitimacy gate | ✓ (0.6.1) but **no pub.dev ecosystem** | 0.6.1 | Direct pub.dev API verification (performed — see Package Legitimacy Audit) |
| `ctx7` / Context7 MCP | Library docs | ✗ | — | WebFetch against official docs + reading the local pub cache source (used throughout; the pub cache is *more* authoritative than Context7 for exact signatures) |

**Missing dependencies with no fallback:** none.

**Missing dependencies with fallback:**
- Supabase CLI and `psql` — the migration and its verification queries must go through the dashboard SQL editor. **The plan must make this an explicit human checkpoint**, because every server-side requirement (BUD-04's durability, BUD-05's policies, BUD-01's token RPCs) is unverifiable until the migration is actually applied.
- Docker — no local Supabase stack, so RLS behaviour can only be proven against the live project. This is already the repo's established pattern.

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | `flutter_test` (Flutter SDK 3.44.8) + `drift_dev`'s `SchemaVerifier` for migrations |
| Config file | none — `pubspec.yaml` `dev_dependencies` only; `analysis_options.yaml` for lints |
| Quick run command | `flutter test test/buddy/ test/migration_test.dart` |
| Full suite command | `flutter test` (currently 538 passing / 4 skipped per STATE.md 2026-08-14) |
| Live/integration command | `flutter test test/sync/live_buddy_test.dart --dart-define-from-file=.secrets/live_sync.json` (self-skips without credentials, mirroring `test/sync/live_round_trip_test.dart:36-48`) |

### Phase Requirements → Test Map

| Req | Behaviour | Test type | Automated command | File exists? |
|-----|-----------|-----------|-------------------|-------------|
| BUD-01 | A join token is single-use: the second redemption of the same token fails | integration (live) | `flutter test test/sync/live_buddy_test.dart -N "token is single use" --dart-define-from-file=.secrets/live_sync.json` | ❌ Wave 0 |
| BUD-01 | An expired token fails; an ended session's token fails; all failures share one generic message | integration (live) | same file, `-N "token gates"` | ❌ Wave 0 |
| BUD-01 | The QR payload round-trips: encode → decode → same token, and a malformed payload is rejected | unit | `flutter test test/buddy/buddy_join_payload_test.dart` | ❌ Wave 0 |
| BUD-02 | **Two-device Drift test:** after a full buddy session with sets logged on both sides, device B's `set_entries` contains zero rows traceable to device A | unit (two in-memory DBs) | `flutter test test/buddy/buddy_two_device_test.dart -N "no partner set rows"` | ❌ Wave 0 — clone the two-database idiom from `test/sync/sync_payload_test.dart:22-26` |
| BUD-02 | Analytics is unchanged by a buddy session: `trainingSnapshotProvider` totals for device B equal the totals from B's own sets alone | unit | `flutter test test/buddy/buddy_analytics_isolation_test.dart` | ❌ Wave 0 — follow `test/analytics_soft_delete_test.dart` |
| BUD-02 | `WorkoutSessions.buddySessionId` survives a push/pull round trip (BUD-07's only dependency on this phase) | unit | `flutter test test/sync/sync_payload_test.dart -N "buddy_session_id"` | ⚠️ extend existing file |
| BUD-03 | Each of add / remove / reorder / replace with scope `both` produces exactly one publisher call with the expected payload | unit (fake publisher) | `flutter test test/buddy/buddy_publisher_test.dart` | ❌ Wave 0 |
| BUD-03 | **The scope gate:** every mutation driven with scope `mine` produces **zero** publisher calls | unit (fake publisher) | `flutter test test/buddy/buddy_publisher_test.dart -N "scope mine never publishes"` | ❌ Wave 0 |
| BUD-03 | **Static boundary:** no file in the buddy transport module serialises a `scope` field or contains the literal `'mine'` | static source | `flutter test test/buddy/buddy_scope_boundary_test.dart` | ❌ Wave 0 — direct clone of `test/rep_tracker_write_boundary_test.dart` (which is *verified to fail* on a deliberately introduced violation — do the same here) |
| BUD-03 | `scope: mine` writes **no row** to `buddy_session_events` | integration (live) | `flutter test test/sync/live_buddy_test.dart -N "scope mine writes no log row"` | ❌ Wave 0 |
| BUD-03 | An unresolvable `exerciseRef` produces a placeholder slot, never a silent drop | unit | `flutter test test/buddy/buddy_apply_test.dart -N "unresolvable ref"` | ❌ Wave 0 |
| BUD-04 | Replaying the same event twice produces the same local state (idempotence) for all four kinds | unit | `flutter test test/buddy/buddy_apply_test.dart -N "idempotent"` | ❌ Wave 0 |
| BUD-04 | Out-of-order arrival is buffered and applied in `seq` order; a gap triggers a backlog refetch rather than an out-of-order apply | unit | `flutter test test/buddy/buddy_event_stream_test.dart` | ❌ Wave 0 |
| BUD-04 | **Cold restart:** a device with `lastSeenSeq = 0` and an empty local session reconstructs the full exercise list from the log | unit + live | `flutter test test/buddy/buddy_replay_test.dart` | ❌ Wave 0 |
| BUD-04 | Concurrent appends from two live clients receive strictly increasing, gapless `seq` values | integration (live) | `flutter test test/sync/live_buddy_test.dart -N "sequence is gapless and ordered"` | ❌ Wave 0 |
| BUD-05 | **`0003_sync_rls.sql` is byte-identical to its pinned hash** | static source | `flutter test test/buddy/rls_frozen_test.dart` | ❌ Wave 0 — pin `f50be2f89c775245e2700c2e532065c7d89ea240da0ef5ed77ff14bb25697530` (LF-normalised; on-disk and normalised hashes are currently identical, `git ls-files --eol` reports `w/lf`, but normalise `\r\n → \n` before hashing anyway so a Windows checkout with different `core.autocrlf` cannot false-fail). Assert the file exists and is non-empty first so the test cannot pass vacuously. |
| BUD-05 | **Live cross-user negative:** a buddy participant selecting `set_entries` / `body_measurements` / `food_entries` filtered to the partner's `user_id` returns zero rows | integration (live) | `flutter test test/sync/live_buddy_test.dart -N "buddy cannot read partner tables"` | ❌ Wave 0 — extend the existing outsider-account pattern at `test/sync/live_round_trip_test.dart:398-425` |
| BUD-05 | A non-participant cannot read `buddy_session_events` for a session they are not in | integration (live) | same file, `-N "non-participant sees no events"` | ❌ Wave 0 |
| BUD-05 | `buddy_join_tokens` returns zero rows to any authenticated client | integration (live) | same file, `-N "join tokens are invisible"` | ❌ Wave 0 |
| BUD-05 | No new policy names appear on any table listed in `0003_sync_rls.sql` | integration (live) | same file, query `pg_policies` and diff against a pinned list | ❌ Wave 0 |
| BUD-06 | A partner's `leave` leaves the other's session live; both sessions end and save normally | unit (two DBs) | `flutter test test/buddy/buddy_two_device_test.dart -N "leave is safe"` | ❌ Wave 0 |
| BUD-06 | A `remove` event never deletes a local `WorkoutExercises` row that has completed sets | unit | `flutter test test/buddy/buddy_apply_test.dart -N "remove never discards logged sets"` | ❌ Wave 0 — the Pitfall 6 gate |
| BUD-06 | After `left_at` is set, `buddy_append_event` rejects that user's writes | integration (live) | `flutter test test/sync/live_buddy_test.dart -N "a departed participant cannot write"` | ❌ Wave 0 |
| — | Local schema migrates cleanly 28 → 29 and matches the v29 dump | unit | `flutter test test/migration_test.dart` | ⚠️ extend existing (bump version literals, add `startAt(28)`) |
| — | The two new local tables have no outbox trigger and appear in neither sync list | unit | `flutter test test/buddy/buddy_local_only_test.dart` | ❌ Wave 0 — direct clone of `test/rep_local_only_test.dart` |

### Sampling Rate

- **Per task commit:** `flutter test test/buddy/ test/migration_test.dart` (fast, no network)
- **Per wave merge:** `flutter test` (full offline suite; live tests self-skip)
- **Phase gate:** full suite green **and** `flutter test test/sync/live_buddy_test.dart --dart-define-from-file=.secrets/live_sync.json` green twice in a row, matching the bar `docs/rb02-sync-verification.md` set for RB-02, before `/gsd:verify-work`

### Wave 0 Gaps

- [ ] `test/buddy/` directory — does not exist
- [ ] `test/buddy/buddy_scope_boundary_test.dart` — BUD-03's structural gate; must be verified to fail on a deliberately introduced violation before it counts
- [ ] `test/buddy/rls_frozen_test.dart` — BUD-05's pinned-hash gate
- [ ] `test/buddy/buddy_local_only_test.dart` — clone of `test/rep_local_only_test.dart`
- [ ] `test/buddy/buddy_two_device_test.dart` — needs a shared two-Drift-database harness; the closest existing precedent is `test/sync/sync_payload_test.dart:22-26`. Consider extracting it into `test/support/two_device.dart` rather than copy-pasting.
- [ ] `test/buddy/fake_buddy_publisher.dart` — the seam every scope test drives; follow `test/sync/fake_sync_backend_service.dart`'s "fake only the network-facing seam, run the real logic against it" doctrine
- [ ] `test/sync/live_buddy_test.dart` — new live integration file; reuse the `_email`/`_email2` fixture and `outsiderSkip()` idiom from `test/sync/live_round_trip_test.dart:445-456`
- [ ] `test/generated_migrations/schema_v29.dart` + `drift_schemas/drift_schema_v29.json` — generated, not hand-written
- [ ] `test/schema_v29_test.dart` — follow `test/schema_v28_test.dart`
- [ ] Framework install: none needed

---

## Security Domain

### Applicable ASVS Categories

| ASVS category | Applies | Standard control |
|---------------|---------|-----------------|
| V2 Authentication | yes | Supabase Auth (existing). No new auth surface. The join token is an **authorisation grant to an existing authenticated user**, never an authentication credential — `buddy_join_session` raises immediately if `auth.uid()` is null. |
| V3 Session Management | yes | Supabase-managed JWT. New consideration: Realtime authorisation is cached for the connection's lifetime, so JWT expiry (not policy revocation) is the eviction mechanism — see Pitfall 3. |
| V4 Access Control | **yes — the core of this phase** | Postgres RLS. Cross-user access confined to four new tables, each gated by one `plpgsql SECURITY DEFINER` participation helper. All privileged writes (`buddy_participants` insert, `buddy_session_events` insert, `buddy_join_tokens` anything) are `REVOKE`d and reachable only through `SECURITY DEFINER` RPCs. `0003_sync_rls.sql` frozen and hash-pinned. |
| V5 Input Validation | yes | Server-side: every RPC validates participation and session state; the topic-to-uuid cast in the `realtime.messages` policy must not throw on a hostile topic string (prefer the `exists`-join form over `substring(...)::uuid`). Client-side: reject a QR payload that is not the expected scheme+shape before it reaches the RPC. |
| V6 Cryptography | yes | `gen_random_uuid()` (core PG, CSPRNG) for the token; `sha256()` (core PG) for at-rest hashing. **Nothing hand-rolled.** No pgcrypto dependency. |
| V7 Error Handling / Logging | yes | `buddy_join_session` must return **one** generic failure for not-found / expired / consumed / ended / full. Distinguishing them is an existence oracle. |
| V13 API | yes | Every new RPC is `SECURITY DEFINER` + `SET search_path = ''` + fully-qualified names — the repo's own rule, documented at `0005_sync_tombstones.sql:46-47`. `buddy_broadcast_event()` has `EXECUTE` revoked from `public, anon, authenticated` (trigger-only), matching `0005:69`; `is_buddy_participant` and the three client RPCs keep it (they are called by clients or by policies evaluated as `authenticated`). |

### Known Threat Patterns

| Pattern | STRIDE | Standard mitigation |
|---------|--------|---------------------|
| Leaked QR screenshot redeemed by a third party | Spoofing | 10-minute expiry + single-use `consumed_at` + `ended_at` check + participant cap; dismiss the QR as soon as a partner joins |
| Token brute force / enumeration | Spoofing, Information disclosure | 122-bit CSPRNG token; single generic error for every failure reason; `buddy_join_tokens` invisible to clients |
| Forged event with a chosen `seq` | Tampering | Client cannot `INSERT` into `buddy_session_events` at all; `seq` is assigned server-side under a row lock |
| A departed participant continuing to mutate the shared list | Tampering | `buddy_append_event` re-checks `left_at is null` and `ended_at is null` on **every** call |
| A stale subscriber continuing to *receive* after leaving | Information disclosure | Partially unmitigable (policy cache). Mitigated by an explicit `session_ended` broadcast that triggers client-side `removeChannel`, and by the fact that the only data on the channel is choreography the user already saw. Documented honestly rather than papered over. |
| Recursive RLS policy taking the buddy feature down | Denial of service | `plpgsql` (never `sql`) `SECURITY DEFINER` helper; a live test that actually selects from all four tables as both participants |
| `search_path` hijack of a definer function | Elevation of privilege | `SET search_path = ''` + fully-qualified names on all five new functions — the repo's stated rule at `0005:46-47` |
| Partner's custom exercise silently copied into the other user's synced catalogue | Information disclosure | Custom exercises are never shared (sender-side gate); materialisation explicitly rejected — see Pitfall 8 |
| Widening `0003` policies by accident during this phase | Elevation of privilege | Pinned-hash static test + a live `pg_policies` diff against a frozen list |
| Realtime message-rate exhaustion | Denial of service | Free tier: 100 msg/s, 100 channels/connection, 256 KB payload. `SyncService.start()` already opens ~37 channels (`live_round_trip_test.dart:52-55` notes 37); one buddy channel is well inside the cap. Choreography events are small (a few hundred bytes). Not a practical concern, but keep event payloads to references — never embed a full exercise record. `[CITED: supabase.com/docs/guides/realtime/limits]` |

---

## Sources

### Primary (HIGH confidence)

- **Local pub cache source** — `C:\Users\marti\AppData\Local\Pub\Cache\hosted\pub.dev\realtime_client-2.13.0\lib\src\{types,realtime_channel,realtime_client}.dart` and `supabase-2.16.0\lib\src\supabase_client.dart`. Every Dart signature in this document was read from the exact resolved source, not from documentation. More authoritative than any docs page.
- **Codebase** — `lib/data/local/{database,tables}.dart`, `lib/data/sync/{sync_service,sync_table_specs,sync_id_resolver,supabase_sync_backend_service}.dart`, `lib/features/workouts/data/workouts_repository.dart`, `lib/features/workouts/presentation/active_workout_view.dart`, `lib/features/shell/quick_add_menu.dart`, `lib/features/nutrition/presentation/{quick_scan_food,barcode_scanner_view}.dart`, `lib/app/providers.dart`, `lib/features/profile/data/local_profile_repository.dart`, `supabase/migrations/{0003,0005,0006,0009}*.sql`, `test/{migration_test,rep_local_only_test,rep_tracker_write_boundary_test,wear_sync_contract_test}.dart`, `test/sync/*`, `pubspec.{yaml,lock}`.
- [supabase.com/docs/guides/realtime/authorization](https://supabase.com/docs/guides/realtime/authorization) — `realtime.messages` RLS, `realtime.topic()`, `extension` values, SELECT-vs-INSERT semantics, the policy cache, the Dart private-channel sample.
- [supabase.com/docs/guides/realtime/broadcast](https://supabase.com/docs/guides/realtime/broadcast) — private channels, `sendBroadcastMessage`, `onBroadcast`, the trigger example, `realtime.broadcast_changes`.
- [supabase.com/docs/guides/realtime/limits](https://supabase.com/docs/guides/realtime/limits) — message/s, connection, channel, payload and presence quotas; 72-hour replay retention.
- [postgresql.org/docs/17/functions-binarystring.html](https://www.postgresql.org/docs/17/functions-binarystring.html) — `sha256(bytea) → bytea` is core, Table 9.12.
- **pub.dev API** — `/api/packages/{qr_flutter,pretty_qr_code,barcode_widget,qr}` and `/score` — versions, publish dates, download counts, licences, SDK constraints.

### Secondary (MEDIUM confidence)

- [supabase.com/blog/realtime-broadcast-from-database](https://supabase.com/blog/realtime-broadcast-from-database) — the WAL/replication-slot mechanism behind `realtime.send`.
- [supabase.com/blog/realtime-broadcast-replay](https://supabase.com/blog/realtime-broadcast-replay) — `replay` config, `since`/`limit`, `meta.replayed`, private-channel-only requirement.
- [event-driven.io/en/ordering_in_postgres_outbox/](https://event-driven.io/en/ordering_in_postgres_outbox/) — pre-commit sequence allocation, the visibility gap, the `xid8` alternative.
- [cybertec-postgresql.com/en/gaps-in-sequences-postgresql/](https://www.cybertec-postgresql.com/en/gaps-in-sequences-postgresql/) — sequence gap causes; `nextval` is never rolled back.
- [dev.to/bairescodeai/infinite-recursion-in-postgres-rls-a-security-definer-gotcha-1916](https://dev.to/bairescodeai/infinite-recursion-in-postgres-rls-a-security-definer-gotcha-1916) — the `LANGUAGE sql` inlining gotcha and the `plpgsql` fix, with before/after SQL.
- [github.com/orgs/supabase/discussions/47525](https://github.com/orgs/supabase/discussions/47525) — corroborating report of RLS recursion and the three remedies.
- [makerkit.dev/blog/tutorials/one-time-tokens-supabase-postgres](https://makerkit.dev/blog/tutorials/one-time-tokens-supabase-postgres) — one-time token schema, `FOR UPDATE` check-and-consume, 10-minute default, cron cleanup.
- [deepwiki.com/supabase/realtime/7.3-migrations-and-schema-management](https://deepwiki.com/supabase/realtime/7.3-migrations-and-schema-management) — `realtime.messages` column list, daily partitioning, 72-hour partition drop.

### Tertiary (LOW confidence — flagged for validation)

- The exact `realtime.send` signature (A1). Every source describes the four arguments; none prints the `create function`. **Verify on the live project before writing the migration.**
- Whether the originating client receives its own DB-published broadcast (A2). The design is built not to depend on the answer.

---

## Metadata

**Confidence breakdown:**
- **Standard stack: HIGH** — every version read from `pubspec.lock` and every Dart signature read from the resolved source in the local pub cache. The one new package was verified against pub.dev's own API.
- **Supabase Realtime API: HIGH** — official docs cross-checked against the actual `realtime_client` 2.13.0 source. The one gap (`realtime.send`'s literal signature) is called out explicitly rather than guessed.
- **RLS design: HIGH on the mechanism, MEDIUM on the exact SQL** — the recursion trap and its `plpgsql` fix are corroborated by three independent sources and match the repo's own `0005` precedent. The specific policy text is a recommendation that has not been executed against a live Postgres.
- **Sequence numbering: HIGH** — the failure mode is well documented; the chosen remedy is the textbook one, applied where its usual objection (throughput) does not bind.
- **Join token design: MEDIUM** — cryptographic primitives verified against core Postgres docs; the expiry value and single-use semantics are product judgements (A4, A5).
- **Codebase claims: HIGH** — every one is cited to a file and line read in this session.
- **Pitfalls: HIGH** — Pitfalls 1, 3, 4 are externally cited; 2, 6, 7, 8, 9 were found by reading this repo's source directly.
- **BUD-03 × BUD-06 conflict (Pitfall 6 / A6): the resolution is a recommendation, not a finding.** It changes user-visible behaviour and should be confirmed with the user before it is locked.

**Research date:** 2026-08-17
**Valid until:** 2026-09-16 (30 days). Supabase Realtime's authorization and broadcast-from-database surface is still evolving — re-check `realtime.send` and the `realtime.messages` policy shape if planning slips past that.
