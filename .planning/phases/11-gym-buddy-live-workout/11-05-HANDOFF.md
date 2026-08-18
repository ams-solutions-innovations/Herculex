# Handoff: Push migration 0011 to the live Herculex Supabase project

**For:** Aleksandar
**From:** Martin / Claude session, 2026-08-18
**Blocks:** Phase 11 (gym-buddy-live-workout), plan 11-05, and everything after it (waves 2-7)

## Why this needs a human

Claude Code's auto-mode safety classifier refuses to let an agent push schema changes to a live
production database on its own, and also refuses to let the agent grant itself permission to do
so (tried adding a Bash allow-rule to `.claude/settings.json` — that was blocked too). This is a
deliberate guardrail, not a bug. Applying this migration is a real, hard-to-reverse action against
`ldzgyzigvbwofbswitrv` (Herculex, region eu-west-3), so it needs a human at the keyboard.

Everything up to this point (waves 1) is done and merged into `master`:
- `11-01`: Supabase CLI installed and linked to `ldzgyzigvbwofbswitrv`
- `11-02`: buddy domain types + test seams
- `11-03`: local Drift schema v28 → v29 (buddy mirror tables)
- `11-04`: `supabase/migrations/0011_buddy_sessions.sql` authored and statically reviewed (RLS on
  every new table, all `SECURITY DEFINER` functions have pinned empty `search_path`, only additive
  touch to an existing table is a nullable column on `workout_sessions`)

The migration file has also been read in full by a human (Martin) this session and judged safe to
apply. Nothing below asks you to review SQL design — just to run it and report back what happened.

## What to run

```bash
cd "c:\Users\marti\AMS d.o.o\Herculex"

# 1. Confirm you're linked to the right project (not jioesomepkauponjrena / SummitSki)
npx supabase projects list
npx supabase link --project-ref ldzgyzigvbwofbswitrv

# 2. Confirm 0011 shows as local-only before pushing
npx supabase migration list

# 3. Apply it
npx supabase db push --yes
```

You'll need a Supabase personal access token if the CLI isn't already authenticated on your
machine — create one at https://supabase.com/dashboard/account/tokens and `export
SUPABASE_ACCESS_TOKEN=sbp_...` before step 1.

## Two possible outcomes

**Expected success:** the CLI reports `0011_buddy_sessions` applied, no errors, no `NOTICE` about
a skipped statement.

**Expected *informative* failure:** the migration has a preflight guard that raises a named
exception if `realtime.send`'s actual signature on this project doesn't match what was assumed
(`realtime.send(jsonb, text, text, boolean)`). If you see an error mentioning
`realtime.send` and "not found on this project", **do not try to patch the migration file
yourself** — that's a plan 11-04 fix, not something to work around live. Instead run this in the
Supabase dashboard SQL editor and send the output back:

```sql
select pg_get_functiondef('realtime.send'::regproc);
```

## After a successful push

```bash
# Confirm 0011 now shows in the Remote column
npx supabase migration list
```

Please send back:
1. The full `db push` output
2. The final `migration list` output
3. Confirmation it applied to `ldzgyzigvbwofbswitrv` (not the other project)

Once that's back, the session can resume: it'll write the "Applied migrations" line into
`docs/supabase-migrations.md`, add the live smoke-test suite
(`test/sync/live_buddy_test.dart`) that proves tokens are single-use and a departed participant
can't write, and continue on to waves 3-7 (client transport, choreography, session assembly, UI,
and the two-device data-isolation proof).

## Full plan reference

The complete task spec (acceptance criteria, threat model, the five smoke tests to be written
after the push) is in
`.planning/phases/11-gym-buddy-live-workout/11-05-PLAN.md` if you want the full detail.
