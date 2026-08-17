# Phase 11: Gym Buddy — Live Shared Workout - Context

**Gathered:** 2026-08-17
**Status:** Ready for planning
**Source:** Interactive scope decisions (four locked architectural choices) plus a codebase audit of the Supabase sync/RLS layer, the Realtime backend service, the workout table chain and the shell `+` menu

<domain>
## Phase Boundary

Let two people train the same workout together in real time. One person shares their active workout; the other joins by scanning a QR code reached from an additional entry in the `+` button. From that moment the **exercise list** stays in step between them, while each person's **sets, reps, weights, RPE and measurements stay entirely their own**.

In scope: the share action and QR display, the QR scan-to-join entry in the `+` menu, short-lived single-session join tokens, the shared buddy-session model (new Supabase tables + new local tables), the Realtime broadcast channel carrying choreography events, the durable event log that lets a disconnected participant rejoin at the correct state, the "both of us / only me" scope choice on every exercise change, live presence of the partner in the active workout UI, and leave/end handling.

Out of scope, deliberately deferred to later phases:
- **VS comparison in workout history (BUD-07)** — the three comparison buttons, per-exercise winner, calisthenics counts, per-session volume. This phase must *store* `buddySessionId` so BUD-07 can compute it later, but must not build any comparison screen.
- **Persistent friends model (BUD-08)** — no friends list, no user search, no invite/accept/block. The QR token is a session token, not a relationship.
- **Challenges (BUD-09)** — no goals, no deadlines, no BF%/kg tracking.

Also out of scope: sharing nutrition, fasting or biometric data; more than two participants; any change to the assisted rep tracker from Phase 10; any change to how sets are computed in analytics.

**Depends on:** Nothing functionally. Takes local schema v29 and a new Supabase migration. Merge after Phase 10's v26–v28 chain has landed to avoid a schema-version race.
</domain>

<decisions>
## Implementation Decisions

### The non-negotiable: two sessions, never one

Each participant owns a separate `WorkoutSessions` row (`lib/data/local/tables.dart:144`), synced under their own `user_id` exactly as today. A shared `buddySessionId` links the two rows. What is shared is the **choreography** — which exercises, in what order — and nothing else.

Consequences that must hold:
- No partner-owned `SetEntries` row is ever written into the other participant's database.
- Buddy sessions never double-count in analytics. `trainingSnapshotProvider` and every downstream engine keep reading only rows the user owns; because partner rows never land locally, this requires *no* analytics change — and a test must prove that.
- Ownership is not a flag on a shared row that a refactor could flip. It is physical separation: the partner's data is not present.

The rejected alternative was one shared session row with per-set owner tagging. It makes BUD-07's comparison trivially easy but requires rewriting ownership assumptions across sync, RLS and analytics, and puts another user's rows inside your local database. Not worth it.

### Session identity: reuse `sessionUuid`

`WorkoutSessions.sessionUuid` (added v22 for the phone↔watch wire protocol) is already a stable, cross-device session identity. The buddy protocol keys on it rather than on the local autoincrement `id`, which is meaningless across devices. `buddySessionId` is a separate new UUID identifying the *pair*, not either session.

### Exercise references must travel as natural keys, not local ids

`WorkoutExercises.exerciseId` is a local int referencing `ExerciseCatalog` (`tables.dart:178`). Those ids differ per device. The existing sync layer already solved this: `CatalogueFk` in `lib/data/sync/sync_table_specs.dart` transmits catalogue refs as a **stable natural key** for seeded rows and a `sync_uuid` for custom rows, resolved by `SyncIdResolver.resolveCatalogueRefForPush`.

Every buddy choreography event must use that same representation. Broadcasting a raw `exerciseId` will silently attach the wrong exercise on the partner's phone. A **custom** exercise that exists only on one participant's device is an edge case the plan must handle explicitly — either transmit enough to materialise it, or refuse to share it with a clear message. Do not let it fail silently.

### Transport: Realtime broadcast for speed, durable log for truth

Live state travels over a Supabase Realtime **broadcast** channel scoped to the buddy session (the existing service already manages channels — `lib/data/sync/supabase_sync_backend_service.dart:92` — but those are per-user `postgres_changes` subscriptions; the buddy channel is a different, room-shaped thing and should not be bolted onto that class without thought).

Every choreography event is **also** appended to a durable `buddy_session_events` table. This is what makes disconnect survivable: a participant who loses signal, backgrounds the app or restarts the phone replays the log from their last seen sequence number and lands on the correct shared state instead of an empty one.

Events carry a monotonic per-session sequence number so replay is ordered and idempotent. Broadcast is an optimisation over the log, never the source of truth — if the two ever disagree, the log wins.

### Scope choice on every change: "both of us" or "only me"

Every choreography mutation (add, remove, reorder, replace) carries an explicit `scope` of `both` or `mine`.

- `scope: both` → applied on both devices, appended to the shared log.
- `scope: mine` → applied locally only, **never** broadcast and never appended to the shared log.

This is the property most likely to break under refactor and most user-visible when it does. It needs a test proving a `mine`-scoped change produces no broadcast and no log row.

The plan must decide how the scope is asked for — a default with an override is likely better UX than a modal on every single change — but must not make "both" implicit for destructive operations.

### Security: existing RLS policies are frozen

Every policy in `supabase/migrations/0003_sync_rls.sql` is `user_id = auth.uid()`. **None of them may be modified, widened or replaced by this phase.** Cross-user visibility is confined to the new buddy tables, whose policies grant access based on participation in a buddy session, plus a minimal participant display identity (name/avatar only).

No new policy may grant a partner read access to another user's training, nutrition, measurement or biometric tables. A test must assert the `0003` policies are unchanged.

### Join tokens are short-lived and single-session

The QR code encodes a join token that is scoped to one buddy session, expires quickly, and cannot be reused once the session ends. It does not create any lasting relationship. The plan must pick a concrete expiry and decide whether a token is single-use or joinable-once-per-participant.

### Leaving is always safe

Either participant can leave at any time. The other's workout continues uninterrupted and both sessions save normally. A partner disconnecting, leaving, or force-quitting can never complete, alter or discard the other's sets — this follows from the two-session model but deserves an explicit test.

### Resolving the BUD-03 × BUD-06 collision: data loss loses to nothing

Research found a real conflict, not a risk. `WorkoutsRepository.removeWorkoutExercise` (`lib/features/workouts/data/workouts_repository.dart:710-733`) hard-deletes every child `SetEntries` row in one transaction. A `scope: both` remove applied verbatim on the partner's device therefore destroys their logged sets — BUD-03 says remove propagates, BUD-06 says a partner can never discard your sets.

**Locked resolution — BUD-06 wins.** The receiving side's `remove` handler is asymmetric by design:

- Partner's slot has **no logged work** → remove normally.
- Partner's slot has **any logged set** → **unlink the slot from the buddy choreography and keep the local exercise in place**, surfacing a one-line note ("Your partner dropped Bench Press — yours is kept").

This is a documented plan decision with its own test, not an implementation detail. A plan task describing remove as "apply the same repository call on both devices" is wrong.

### Scope presentation: sticky defaults, visible override

The scope choice is not a modal on every change. Defaults are sticky per action kind:

- `add`, `reorder`, `replace` → default `both`
- `remove` → default `mine`

Every action shows a visible toggle to override for that one action. This satisfies "must not make 'both' implicit for destructive operations" without putting a dialog in the middle of a workout.

### Joining auto-starts the joiner's workout

Scanning the QR code when the joiner has no active workout **creates their own session and links it immediately**. One gesture from scan to training together. The joiner's session is theirs, owned and synced under their `user_id` exactly like any other — auto-creation changes nothing about ownership.

### Migrations are automated via the Supabase CLI

Neither the `supabase` CLI nor `psql` is currently installed, and how migrations `0001`–`0010` reached the server is undocumented. This phase **installs and wires up the Supabase CLI** and applies the new migration through `supabase db push` rather than a human paste into the SQL Editor.

This is a real prerequisite, not a footnote: every server-side requirement (BUD-04's log, BUD-05's policies, the join-token RPC) is unverifiable until migrations can be applied repeatably, and the live integration tests in `test/sync/live_round_trip_test.dart` need the schema present. The plan must sequence CLI setup and project linking before any task that depends on server-side behaviour, and must record the resulting workflow in the repo so it is no longer tribal knowledge.

### Claude's Discretion

- Exact local table shapes and the v29 migration contents.
- Where the share button lives in `active_workout_view.dart` and how the join entry is added to `lib/features/shell/quick_add_menu.dart`.
- How partner presence is surfaced in the active workout UI (and whether partner set-completion is shown live at all — the requirement does not demand it).
- QR generation package choice (`qr_flutter` is the obvious candidate; `mobile_scanner` ^7.4.0 already covers scanning).
- Conflict resolution when both participants mutate choreography simultaneously — sequence-number ordering is the mechanism, but the tie-break rule is open.
- Whether the buddy channel logic extends `SupabaseSyncBackendService` or lives in a new service.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Sync, identity and security
- `supabase/migrations/0003_sync_rls.sql` — the owner-only policy generator this phase must leave untouched
- `lib/data/sync/sync_table_specs.dart` — `CatalogueFk` / `SimpleFk` conventions; how catalogue refs cross devices
- `lib/data/sync/sync_id_resolver.dart` — `resolveCatalogueRefForPush`, the correct way to transmit an exercise reference
- `lib/data/sync/supabase_sync_backend_service.dart` — existing Realtime channel management (per-user `postgres_changes`; the buddy channel is a different shape)
- `lib/data/sync/sync_service.dart` — push/pull orchestration and table ordering

### Workout data model
- `lib/data/local/tables.dart:143-235` — `WorkoutSessions` (incl. `sessionUuid`), `WorkoutExercises`, `SetEntries`
- `lib/data/local/database.dart` — migration chain, currently `schemaVersion => 28`
- `lib/features/workouts/data/workouts_repository.dart` — the single set mutation path

### UI entry points
- `lib/features/workouts/presentation/active_workout_view.dart` — where sharing is initiated
- `lib/features/shell/quick_add_menu.dart` — the `+` button that gains the scan-to-join entry
- `lib/features/workouts/presentation/exercise_picker_sheet.dart` — where exercise changes originate

### Prior art in this repo
- `.planning/phases/10-assisted-rep-tracking/10-CONTEXT.md` — precedent for enforcing an architectural boundary with a static test rather than convention

</canonical_refs>

<specifics>
## Specific Ideas

From the user, verbatim in intent:

- Share button on an active workout; partner joins by **scanning a QR code via an extra button in the `+` menu**.
- "Workout together": when one adds a set or an exercise, it appears for the other — **except** where they have deliberately individual exercises.
- Sets and reps, and all measurement, are **completely individual**.
- When changing an exercise, the user decides: **change for both, or only for me**.
- The app should keep a VS record per workout somewhere in settings/history — *this phase only persists `buddySessionId` to make that possible later; the comparison UI is BUD-07.*

</specifics>

<deferred>
## Deferred Ideas

- **BUD-07 — Buddy VS comparison:** three buttons in workout history comparing per-exercise winner, calisthenics rep counts and per-session volume against the partner. Requires only `buddySessionId` from this phase.
- **BUD-08 — Persistent friends:** identity, search, invite, accept, block. Prerequisite for challenges.
- **BUD-09 — Challenges:** each participant sets a goal with a deadline (strength target, BF%, kg lost or gained), progress read from existing measurement and training data, resolved at the deadline.
- More than two participants in one buddy session.
- Sharing nutrition, fasting or biometric data with a buddy.

</deferred>

---

*Phase: 11-gym-buddy-live-workout*
*Context gathered: 2026-08-17 via /gsd-plan-phase interactive scope decisions*
