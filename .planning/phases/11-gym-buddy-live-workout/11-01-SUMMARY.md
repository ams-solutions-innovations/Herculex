---
phase: 11-gym-buddy-live-workout
plan: 01
subsystem: infra
tags: [supabase, supabase-cli, migrations, npm, devops]

# Dependency graph
requires: []
provides:
  - "Supabase CLI available via `npm install` + `npx supabase` (pinned 2.114.0, no `npx --yes @latest`)"
  - "Repo linked to project ref ldzgyzigvbwofbswitrv (Herculex), confirmed not jioesomepkauponjrena (SummitSki)"
  - "supabase migration list confirms 0001-0010 local == remote, no repair needed"
  - "docs/supabase-migrations.md — the reproducible install/auth/link/inspect/apply workflow"
affects: [11-02, 11-03, 11-04, 11-05, 11-06, 11-07, 11-08, 11-09, 11-10, 11-11]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Supabase CLI invoked as `npx supabase` (pinned via package.json/package-lock.json devDependency), never `npx --yes supabase@latest`"
    - "supabase/config.toml `project_id` field kept as a human-visible project marker; actual link state lives in gitignored supabase/.temp/, re-established per machine via `supabase link --project-ref`"

key-files:
  created:
    - docs/supabase-migrations.md
  modified:
    - supabase/config.toml
    - docs/rb02-sync-verification.md

key-decisions:
  - "Used the repo's pre-existing pinned npm devDependency (package.json ^2.114.0 + package-lock.json) via `npm install` + `npx supabase`, instead of the plan's anticipated winget/global-npm fallback route — winget has no Supabase.CLI package on this machine, and the repo already had a better, version-pinned route committed from prior work."
  - "Added `project_id = \"ldzgyzigvbwofbswitrv\"` to supabase/config.toml even though this CLI version (2.114.0) does not write it via `supabase link` — the field is a local Docker-namespace marker per the CLI's own docs, not the actual link mechanism, but setting it to the real project ref satisfies the plan's artifact gate and gives a correct, non-misleading human-visible signal. The doc explains the real mechanism lives in supabase/.temp/."
  - "The blocking human-action checkpoint (Task 2: obtaining a personal access token, running `supabase link`) was resolved by the orchestrator running the link directly with an already-authenticated CLI session, rather than by this agent — the resulting state (ref ldzgyzigvbwofbswitrv, migrations 0001-0010 local==remote) was independently re-verified from within the worktree (supabase/.temp/linked-project.json, git status --porcelain clean of any sbp_ token) before proceeding to Task 3."

requirements-completed: [BUD-04, BUD-05]

# Metrics
duration: ~35min (spans a checkpoint pause between two agent invocations)
completed: 2026-08-18
---

# Phase 11 Plan 01: Supabase CLI install and migration workflow Summary

**Supabase CLI wired up via a pinned npm devDependency (`npx supabase`, 2.114.0), repo linked to Herculex's real project (ldzgyzigvbwofbswitrv), and the full install/auth/link/apply workflow documented in `docs/supabase-migrations.md` so `0011_buddy_sessions.sql` can be pushed by command instead of pasted into the SQL Editor.**

## Performance

- **Duration:** ~35 min of agent-active work, spanning a blocking human-action checkpoint between two agent invocations
- **Started:** 2026-08-18T12:13:17Z (worktree base commit)
- **Completed:** 2026-08-18T12:46:42Z (final task commit)
- **Tasks:** 3/3 complete
- **Files modified:** 3 (`supabase/config.toml`, `docs/rb02-sync-verification.md`, `docs/supabase-migrations.md` created)

## Accomplishments

- Supabase CLI is installed, reproducibly, via the repo's own pinned devDependency (`npm install` + `npx supabase`) — no `npx --yes supabase@latest` anywhere.
- Repo is linked to the correct Herculex project (`ldzgyzigvbwofbswitrv`), independently re-verified from `supabase/.temp/linked-project.json` rather than taken on trust — confirmed it is not the SummitSki project (`jioesomepkauponjrena`).
- `supabase migration list` confirms `0001`-`0010` are `local == remote`; no `migration repair` was necessary.
- `docs/supabase-migrations.md` gives a future developer (or plan 11-05) copy-pasteable commands for install, auth, link, inspect, apply, migration naming convention, and an explicit "Do not" list (no editing applied migrations, no `db reset` against the linked remote, no `db pull` + commit because it would rewrite the frozen `0003_sync_rls.sql`).
- `db push --yes` is confirmed to run non-interactively — informs how plan 11-05 should sequence its push step.

## Task Commits

Each task was committed atomically:

1. **Task 1: Install the Supabase CLI and record its version** — no commit (no tracked files changed; CLI resolved via the repo's existing pinned devDependency and `node_modules/` is gitignored). Findings folded into Task 3's doc and this Summary.
2. **Task 2: [BLOCKING] Authenticate and link the repo** — `035c99c` (feat) — link performed by the orchestrator with an already-authenticated session; this agent added `project_id` to `supabase/config.toml` and independently re-verified the link state.
3. **Task 3: Write docs/supabase-migrations.md** — `8bae166` (docs)

## Files Created/Modified

- `docs/supabase-migrations.md` — new: the full install/auth/link/inspect/apply workflow, migration naming convention, and "Do not" list
- `supabase/config.toml` — added `project_id = "ldzgyzigvbwofbswitrv"` with a comment explaining its real (limited) meaning and pointing at the doc for the actual link mechanism
- `docs/rb02-sync-verification.md` — added a one-line pointer at the top to `docs/supabase-migrations.md`

## Decisions Made

- **Install route:** `winget install --id Supabase.CLI` fails (no such package on this machine — confirmed via `winget search supabase` returning nothing). Used the repo's already-pinned `npm install` + `npx supabase` route instead of the plan's `npm install -g supabase` fallback, since `package.json`/`package-lock.json` already declared this dependency from a prior commit (`c27867d`) — a better, version-pinned answer than either winget or a global install.
- **`project_id` in config.toml:** the plan's frontmatter assumed `supabase link` writes `project_id` into `supabase/config.toml`. On this CLI version (2.114.0) it does not — link state is written only to the gitignored `supabase/.temp/` directory. Verified this directly by running `supabase init --yes` in a scratch directory and reading the generated config.toml's own comment: `project_id` is "a string used to distinguish different Supabase projects on the same host," defaulting to the working-directory name — not a remote link. Set it to the real project ref anyway as a low-risk, additive, human-visible marker, and documented the real mechanism (`supabase/.temp/`, re-linked per machine) in `docs/supabase-migrations.md` so nobody is misled.
- **Checkpoint resolution:** Task 2 required a personal Supabase access token and interactive dashboard login that this agent could not obtain. Per this plan's non-autonomous marking, the agent stopped and returned a `CHECKPOINT REACHED` message. The orchestrator resolved it by running `supabase link --project-ref ldzgyzigvbwofbswitrv` and `supabase migration list` directly in this worktree with an already-authenticated CLI session, then reported the results back. Rather than taking that report on trust, this agent independently re-verified: `supabase/.temp/linked-project.json` shows `{"ref":"ldzgyzigvbwofbswitrv","name":"Herculex",...}`, and `grep -c sbp_` across the tree returns only the plan document's own literal example text (not a real token) — no credential leaked into any tracked file.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Reverted an unintended package-lock.json mutation from `npm install`**
- **Found during:** Task 1
- **Issue:** Running `npm install` inside this worktree rewrote `package-lock.json`'s top-level `"name"` field from `"Herculex"` to the worktree directory's basename (`agent-a45de3b9c800cc472`), because `package.json` has no `"name"` field and npm derives one from the cwd.
- **Fix:** `git checkout -- package-lock.json` before staging anything, restoring the original `"name": "Herculex"`.
- **Files modified:** none (reverted before commit)
- **Verification:** `git status --short` clean immediately after; `grep '"name"' package-lock.json` shows `"Herculex"`.
- **Committed in:** n/a — reverted, never committed.

**2. [Rule 1 - Bug, plan-assumption mismatch] `supabase/config.toml` does not receive `project_id` from `supabase link` on this CLI version**
- **Found during:** Task 2 (verifying the orchestrator's linking report)
- **Issue:** The plan's `must_haves.artifacts` and `key_links` both assert `supabase link --project-ref` writes `project_id` into `supabase/config.toml`. On CLI 2.114.0 it does not — confirmed by inspecting a freshly-`init`'d config.toml in a scratch directory, whose own comment defines `project_id` as a local same-host namespace string, not a remote link.
- **Fix:** Added `project_id = "ldzgyzigvbwofbswitrv"` to `supabase/config.toml` manually, with an explanatory comment, to satisfy the plan's acceptance gate (`grep project_id supabase/config.toml` → `ldzgyzigvbwofbswitrv`) without misrepresenting what the field actually does. Documented the real link mechanism (`supabase/.temp/`, gitignored, re-established via `supabase link --project-ref` per machine) in `docs/supabase-migrations.md`.
- **Files modified:** `supabase/config.toml`
- **Verification:** `grep project_id supabase/config.toml` prints `ldzgyzigvbwofbswitrv`; plan's `<verification>` gate passes.
- **Committed in:** `035c99c`

---

**Total deviations:** 2 auto-fixed (1 bug/caught-side-effect, 1 bug/plan-assumption correction)
**Impact on plan:** Both were necessary to keep the working tree clean and to satisfy the plan's literal acceptance gates given the real behavior of the installed CLI version. No scope creep — no architectural changes, no new dependencies beyond what the plan and the repo's existing devDependency already specified.

## Issues Encountered

- `npx supabase migration list` was blocked by this session's tool-use auto-mode classifier when I attempted to independently re-run it after the orchestrator's report (network call against a live project). Independent verification was instead performed by reading `supabase/.temp/linked-project.json` and `supabase/.temp/project-ref` directly (both written by the orchestrator's `supabase link` run) and confirming they show `ldzgyzigvbwofbswitrv`, plus a repo-wide `grep -c sbp_` to confirm no token leaked. This is a weaker verification than re-running `migration list` myself, but the orchestrator's reported output (all of `0001`-`0010` local==remote) is consistent with the `.temp/` cache state and with `docs/rb02-sync-verification.md`'s account that historical migrations were already reconciled by 2026-08-15.

## User Setup Required

None for this plan — the CLI is installed and linked. Future work in this phase (plan 11-05, applying `0011_buddy_sessions.sql`) will need `SUPABASE_ACCESS_TOKEN` exported in whatever shell runs `supabase db push`, per `docs/supabase-migrations.md` §2.

## Next Phase Readiness

- The Supabase CLI is installed, reproducible, and documented — `docs/supabase-migrations.md` is the canonical reference for every subsequent plan in this phase that needs to apply or inspect migrations.
- The repo is linked to the correct project and migration history is confirmed in sync, so `0011_buddy_sessions.sql` (built in plan 11-03/11-04) can be pushed with `npx supabase db push --yes` in plan 11-05 without any further linking ceremony, modulo re-running `supabase link` on whatever machine/session actually performs that push (link state is per-machine, not committed).
- No blockers for downstream plans in this phase.

## Self-Check: PASSED

- FOUND: `docs/supabase-migrations.md`
- FOUND: `supabase/config.toml` contains `project_id = "ldzgyzigvbwofbswitrv"`
- FOUND: commit `035c99c` (feat: link repo to Herculex Supabase project)
- FOUND: commit `8bae166` (docs: add docs/supabase-migrations.md workflow)

---
*Phase: 11-gym-buddy-live-workout*
*Completed: 2026-08-18*
