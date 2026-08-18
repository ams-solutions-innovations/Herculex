---
phase: 11-gym-buddy-live-workout
plan: 04
subsystem: database
tags: [postgres, supabase, rls, plpgsql, realtime, security-definer]

# Dependency graph
requires:
  - phase: 11-gym-buddy-live-workout (plan 01)
    provides: Supabase CLI install/link workflow used to apply this migration in plan 11-05
provides:
  - "supabase/migrations/0011_buddy_sessions.sql — four buddy tables, the plpgsql participation helper, RLS on the buddy tables and realtime.messages, three client RPCs, the broadcast trigger, the workout_sessions.buddy_session_id column, and the guarded token-cleanup job"
affects: [11-05 (apply migration), 11-06 (transport/publisher wiring), 11-07 (client appliers)]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Broadcast-from-the-database: AFTER INSERT trigger calls realtime.send(); clients never insert broadcast rows"
    - "Non-recursive RLS participation gate via a LANGUAGE plpgsql SECURITY DEFINER helper (LANGUAGE sql would be inlined and recurse)"
    - "Manual gapless sequence under SELECT ... FOR UPDATE, not bigserial/identity"
    - "One generic error message for every join-token failure cause (anti existence-oracle)"

key-files:
  created:
    - supabase/migrations/0011_buddy_sessions.sql
    - .planning/phases/11-gym-buddy-live-workout/deferred-items.md
  modified: []

key-decisions:
  - "realtime.messages policies join against a generated buddy_sessions.topic column instead of parsing realtime.topic() with a substring/cast, per the plan's explicit instruction (research's draft used substring; the plan overrode it)."
  - "Task 1 and Task 2 were committed as two separate atomic commits against the same file by writing the full migration once, verifying all gates, then splitting the file at the Task 1/Task 2 boundary (line 184) and staging/committing each half in turn."
  - "The Dart-level test/buddy/rls_frozen_test.dart gate specified in this plan's acceptance criteria could not be run — that file is plan 11-02's deliverable and is not present in this worktree. Logged as a deferred item rather than recreated out of scope; the plan's own Task 3 automated frozen-policy scan (which independently proves 0003_sync_rls.sql was not touched) passed instead."

patterns-established:
  - "Every SECURITY DEFINER function in this file uses fully-qualified names and set search_path = '' (verified: exactly 5 occurrences, one per function)."

requirements-completed: [BUD-01, BUD-04, BUD-05, BUD-06]

# Metrics
duration: 26min
completed: 2026-08-18
---

# Phase 11 Plan 04: Buddy Sessions Migration Summary

**Self-contained `0011_buddy_sessions.sql` migration authoring the full server-side buddy surface — four tables, a non-recursive plpgsql RLS helper, three client RPCs, a broadcast-from-the-database trigger, and realtime.messages policies — with zero changes to any policy `0003_sync_rls.sql` created.**

## Performance

- **Duration:** 26 min
- **Started:** 2026-08-18T14:03:00Z
- **Completed:** 2026-08-18T14:29:35Z
- **Tasks:** 3 completed
- **Files modified:** 2 (1 SQL migration, 1 new deferred-items log)

## Accomplishments
- Authored the four buddy tables (`buddy_sessions`, `buddy_participants`, `buddy_session_events`, `buddy_join_tokens`) exactly per `11-RESEARCH.md`'s schema, including the generated `topic` column and the five-value `kind` check constraint.
- Wrote `public.is_buddy_participant()` as a `language plpgsql` (never-inlined) `SECURITY DEFINER` helper, breaking the RLS recursion trap the research flagged as Pitfall 1.
- Wrote all three client RPCs (`buddy_create_session`, `buddy_join_session`, `buddy_append_event`), the `buddy_broadcast_event` trigger, and the `realtime.messages` policies, using an `exists`-join against the generated `topic` column instead of a `substring(...)::uuid` parse.
- Ran a full static review (Task 3) against every table name `0003_sync_rls.sql` iterates over — zero matches — and confirmed every other structural must-have (no `language sql`, no `bigserial`/identity `seq`, 5/5 definer functions with a pinned empty `search_path`, `buddy_join_tokens` RLS-on with zero policies, `session_ended` permitted by the check constraint).

## Task Commits

Each task was committed atomically:

1. **Task 1: Tables, the plpgsql participation helper, and the buddy-table policies** - `fc9be26` (feat)
2. **Task 2: The three client RPCs, the broadcast trigger, and the realtime.messages policies** - `237395a` (feat)
3. **Task 3: A static review pass over the migration against the frozen-policy and pitfall list** - `0285e81` (docs)

**Plan metadata:** committed separately as part of this SUMMARY (worktree mode — orchestrator handles the shared STATE.md/ROADMAP.md commit after merge).

## Files Created/Modified
- `supabase/migrations/0011_buddy_sessions.sql` - the complete buddy-session server-side surface (468 lines): 4 tables, 1 helper function, 4 RPCs/triggers, 6 RLS policies on buddy tables, 2 RLS policies on `realtime.messages`, 1 additive column on `workout_sessions`, 1 guarded `pg_cron` cleanup job.
- `.planning/phases/11-gym-buddy-live-workout/deferred-items.md` - new file logging the missing `test/buddy/rls_frozen_test.dart` dependency gap (see Deviations below).

## Decisions Made
- **Task-boundary commit strategy:** wrote the complete migration file in one pass (Tasks 1 and 2 are additive to the same file and were easiest to author with full context of both in view simultaneously), then verified all of Task 1's and Task 2's automated gates against the full file, then split the file at its Task 1/Task 2 boundary and staged/committed each half separately so the git history still reflects one commit per task. No content differs between what was verified and what was committed.
- **Realtime topic matching:** followed the plan's explicit instruction over the research doc's own draft — the plan overrides the research's `substring(realtime.topic() from 7)::uuid` sketch and mandates the `exists`-join against the generated `topic` column, which is what's in the final file. `grep -c "substring(realtime.topic()"` returns 0.
- **Trigger statement on one line:** `create trigger t_buddy_broadcast_event after insert on public.buddy_session_events` had to be kept on a single physical line (rather than wrapped, which was my first draft) because the plan's acceptance criteria greps for that exact contiguous string. Caught and fixed during Task 2's own verification pass before committing.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Multi-line trigger statement failed its own acceptance grep**
- **Found during:** Task 2 (self-verification before commit)
- **Issue:** First draft wrote `create trigger t_buddy_broadcast_event\n  after insert on public.buddy_session_events\n  for each row execute function public.buddy_broadcast_event();` across three lines for readability. The plan's acceptance criteria requires the literal substring `create trigger t_buddy_broadcast_event after insert on public.buddy_session_events` to be present, which a line-broken statement doesn't satisfy under a plain (non-multiline) grep.
- **Fix:** Joined the trigger name and `after insert on ...` clause onto one line, keeping only the `for each row execute function ...` clause on its own continuation line.
- **Files modified:** `supabase/migrations/0011_buddy_sessions.sql`
- **Verification:** `grep -c "create trigger t_buddy_broadcast_event after insert on public.buddy_session_events"` returns 1; re-ran every other Task 1/Task 2 gate to confirm no regression.
- **Committed in:** `237395a` (Task 2 commit — fixed before first commit of this content, so no separate fix commit was needed)

---

**Total deviations:** 1 auto-fixed (1 bug, caught by self-verification, zero user-visible impact since it was fixed before any commit)
**Impact on plan:** No scope creep. The SQL semantics are unchanged; only line-wrapping was adjusted.

## Issues Encountered

**`test/buddy/rls_frozen_test.dart` does not exist in this worktree.** This plan's own acceptance criteria for all three tasks reference `flutter test test/buddy/rls_frozen_test.dart` as a secondary verification signal. That file is plan 11-02's deliverable (wave 1) and its artifacts are not present in this worktree/branch — `git log` here shows only the phase's planning-doc commits before this plan's own three commits, and `lib/features/buddy/` and `test/buddy/` do not exist anywhere in the tree. This could not be run.

This was **not** treated as a blocker for 11-04's own deliverable, for three reasons: (1) `files_modified` in this plan's frontmatter names only `supabase/migrations/0011_buddy_sessions.sql` — creating `test/buddy/rls_frozen_test.dart` (with its specific pinned SHA-256 hash and several sibling files that belong entirely to 11-02: `buddy_event.dart`, `buddy_scope.dart`, `buddy_event_publisher.dart`, `test/support/two_device.dart`, `test/buddy/fake_buddy_publisher.dart`, `test/buddy/buddy_scope_boundary_test.dart`) is out of this plan's scope per the executor's scope-boundary rule; (2) this plan's own Task 3 automated check — a `bash` loop grepping `0011_buddy_sessions.sql` for `create|alter|drop policy` against every one of `0003_sync_rls.sql`'s table names — independently proves the same claim the Dart test would have proven (`0003_sync_rls.sql` was not touched), and it passed (`NO_FROZEN_POLICY_TOUCHED`); (3) recreating that test file here with a guessed structure risks conflicting with 11-02's real commit when it lands, since 11-02's own `must_haves.artifacts` pins an exact SHA-256 hash of `0003_sync_rls.sql`'s LF-normalised bytes that this plan has no reason to compute independently.

Logged to `.planning/phases/11-gym-buddy-live-workout/deferred-items.md` for whoever merges this wave: confirm plan 11-02 has landed (or lands before 11-05, which applies this migration to the live project) so the Dart-level frozen-hash gate is exercised at least once.

## User Setup Required

None - no external service configuration required. (Applying this migration to the live Supabase project is explicitly plan 11-05's job, not this plan's.)

## Next Phase Readiness

- `supabase/migrations/0011_buddy_sessions.sql` is complete, self-contained, and passes every automated gate this plan specifies (Task 1's table/helper/policy gate, Task 2's RPC/trigger/realtime-policy gate, Task 3's frozen-policy scan across all 35 of `0003_sync_rls.sql`'s tables).
- Plan 11-05 can proceed to install/link the Supabase CLI (built by 11-01) and run `supabase db push` against this file — it has not been applied to any database, local or remote, by this plan.
- **Blocker/concern for the wave merge:** confirm plan 11-02 (wave 1, `test/buddy/rls_frozen_test.dart` and the buddy client-side contracts) has actually landed in whatever branch these wave-2 worktrees merge into. Its absence here suggests either a wave-sequencing gap or a not-yet-merged sibling worktree — worth checking before 11-05 pushes to the live project, since 11-06/11-07 depend on 11-02's `BuddyEvent`/`BuddyEventPublisher` contracts existing.

---
*Phase: 11-gym-buddy-live-workout*
*Completed: 2026-08-18*
