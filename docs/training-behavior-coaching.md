# Exercise history corrections and training coaching

## User flows

Exercise details in the Exercise Library have a **Transfer history** toolbar
action. Select a destination and all history or individual completed entries,
review the counts and equipment, then confirm. This changes recorded exercise
identity without copying sets or changing the exercise catalogue, templates or
program. Incompatible metrics and bodyweight/assistance load accounting are
blocked. Undo is available from the completion screen or by reopening the
transfer sheet; it refuses subsequent edits, including attachment changes.

Training suggestions appear after a workout and on the dashboard. A significant
deviation can prompt one optional reason check-in. No push notifications are
added. All plan changes require an explicit, revalidated preview.

The deterministic engine examines up to 84 days and requires three occurrences
among four comparable exposures for a persistent habit. Equipment, gym, original
prescription and training phase separate comparisons. Unknown original plans,
history corrections, deloads and confirmed adaptations do not teach manual habits.
Recognized patterns include omitted sets, repeated comparable performance drops,
added muscle groups, late accessories, equipment substitutions and time limits.

Repeated added muscle work is connected to confirmed Dream Physique priorities.
The planner can reallocate optional sets while protecting main lifts, supersets
and other high priorities. Existing-session growth is capped at four working
sets and 20 percent. Reducing sets does not increase load or proximity to failure.

A trial changes the next two suitable occurrences for at most 28 days. Its
review distinguishes completed work, duration, comparable performance and missing
evidence. Optional fatigue/pain feedback stays in private local workout reports.
The user can review a permanent change, revise the trial or cancel it. Only one
trial in a program runs at a time. Permanent changes preserve unrelated inline
prescriptions and own copies of affected shared templates.

## Optional workouts

Only a confirmed time constraint enables catch-up. A safe fit in existing
workouts is tried first; the user can instead select a date, time and available
minutes for one optional workout. Names reflect the omitted work, such as
Optional arms or Optional pull. Entire unstarted supersets move together; a
partly performed group and Max Effort work are not reconstructed.

Safety checks include primary and secondary muscle work, recorded external
workouts, current joint flags and deload signals, projected recovery and the
following seven days across programs. Added work needs estimated readiness of
at least 70 for affected muscles and must fit volume bands; comparable sustained
history can personalize those bands. Untimed conflicting sessions need explicit
times. A seven-day window permits at most one optional workout, never more than
the omitted work. Skipping it does not generate another catch-up request.

Time budgets include working sets, known timed targets, rest, transitions and
warmups. Distance/calorie work needs a duration to fit a time budget. Structural
suggestions involving advanced set prescriptions defer to the program editor.
These are planning estimates, not physiological measurements or diagnoses.

## Data and synchronization

Drift schema **54** adds `workout_behavior_snapshots`,
`training_coaching_proposals`, `training_coaching_overrides` and
`exercise_history_transfers`. `scheduled_workouts.program_day_id` becomes nullable
for rows with `one_off_plan_json`; these rows survive recurring schedule
materialization and work with the calendar, preview and session launcher.

Stored plans and correction audit data use catalogue slugs or sync UUIDs, not
device-local IDs. Previews check evidence, current plans and safety again inside
the acceptance transaction. The newest confirmed applicable adaptation resolves
the occurrence, including existing weekly adaptations. A prior accepted
redistribution blocks duplicating the same omitted work.

Behavior snapshots contain portable workout facts and a conservative action
policy. Sleep data, detailed health explanations and trial health feedback remain
in local report tables. Account wipes and workout deletion remove associated
coaching/audit data, including when SQLite foreign-key enforcement is disabled.

## Rollout and verification

Applied `supabase/migrations/20261028071417_training_behavior_coaching.sql` to the
Herculex project (`ldzgyzigvbwofbswitrv`) on 2026-10-28, before shipping the
schema-54 client to cloud-sync users. It adds owner-scoped RLS,
parent-ownership checks, authenticated grants, clocks, tombstones and realtime
publication for the new tables. Verified all four tables, owner policies, sync triggers, realtime publication,
foreign-key indexes and the optional-workout constraint on the live database.
The local filename matches the version recorded by Supabase; unrelated pending
migrations were not included in this rollout.

Tests under `test/features/training_coaching/` cover detection, transfers and
cross-device undo, stale previews, explicit confirmation, trials and permanent
changes, optional workouts, indirect overlap, goal reorganization, privacy and
narrow/wide layouts. `test/migration_test.dart` replays supported schemas through
v54 and explicitly verifies v53 scheduled identities and sync triggers survive.
The sync parity tests verify the server wiring. Visual previews are available in
`outputs/training-coaching-360.png` and `outputs/training-coaching-1200.png`.
