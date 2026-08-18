# Herculex Supabase migration workflow

Supersedes the "how do migrations reach the server" question left open by
`docs/rb02-sync-verification.md`. That document records that migrations
`0001`-`0010` were applied "via the Supabase MCP tools" against the **wrong**
project (`jioesomepkauponjrena`, which is SummitSki) and were re-applied to
the real Herculex project (`ldzgyzigvbwofbswitrv`) by hand on 2026-08-15, with
no reproducible command written down anywhere. This file is that reproducible
command sequence.

## 1. Install

The Supabase CLI is a `devDependency` pinned in `package.json` /
`package-lock.json` (added alongside the RB-01..05 sync work). Install it
like any other Node dependency:

```bash
npm install
```

This resolves the platform-specific `@supabase/cli-*` optional dependency at
the version pinned in `package-lock.json` (currently **2.114.0**) into
`node_modules/.bin/`. Invoke it as:

```bash
npx supabase --version
```

**Do not** run `npx --yes supabase@latest` anywhere, in a script or
otherwise — that fetches whatever the registry currently calls `latest` on
every invocation, bypassing the lockfile pin entirely (see the "Do not"
section below). Plain `npx supabase` resolves the local, pinned,
already-installed binary and does not touch the registry.

If `node_modules` is not present and you cannot run `npm install` for some
reason, the fallback install routes are, in preference order:
1. `winget install --id Supabase.CLI` — **not currently available**; no such
   winget package exists as of this writing (`winget search supabase`
   returns nothing).
2. `npm install -g supabase` — works, but produces an unpinned global binary
   that drifts from `package-lock.json`. Prefer the local devDependency route
   above.
3. Download a release archive from `github.com/supabase/cli/releases` into a
   directory already on `PATH`.

## 2. Auth

Mint a personal access token at
`https://supabase.com/dashboard/account/tokens`, then export it in the shell
that will run the commands below:

```bash
export SUPABASE_ACCESS_TOKEN=sbp_...
```

**Never commit this token to any file in the repo.** It is a bearer
credential with full project authority. `.gitignore` already covers the
places it could leak:

- `.env` / `.env.*`
- `supabase/.temp/` (where `supabase link` caches session state locally)
- `supabase/.branches/`

If you ever add a `.env` file for local convenience, confirm it still matches
one of the ignored patterns above before creating it.

## 3. Link

```bash
npx supabase link --project-ref ldzgyzigvbwofbswitrv
```

> **⚠️ `jioesomepkauponjrena` is the SummitSki project, not Herculex.** It was
> wrongly configured repo-wide until 2026-08-15 — see
> `docs/rb02-sync-verification.md` for the incident this corrected. If
> `supabase link` (or any other command) ever prints `jioesomepkauponjrena`,
> stop immediately; linking to it is the exact defect that document was
> written to fix.

On this CLI version (2.114.0), `supabase link` does **not** write a
`project_id` line into `supabase/config.toml` — link state is written only to
the gitignored `supabase/.temp/` directory (`project-ref`,
`linked-project.json`, etc.) and must be re-established on every machine /
fresh checkout that needs to run a server-affecting command. The
`project_id = "ldzgyzigvbwofbswitrv"` line that *is* present at the top of
`supabase/config.toml` is a different, CLI-documented field — "a string used
to distinguish different Supabase projects on the same host" — kept in sync
with the real project ref here purely as a human-visible marker, not as the
mechanism that performs the link. Always re-run `supabase link
--project-ref` rather than assuming a linked state persists in git.

## 4. Inspect

```bash
npx supabase migration list
```

Verified 2026-08-18: `0001` through `0010` all show **local == remote**
(fully in sync) against `ldzgyzigvbwofbswitrv`. No `migration repair` was
needed for the historical migrations on this pass — the earlier hand-applied
history from `docs/rb02-sync-verification.md` had already reconciled cleanly.

If a future `migration list` ever shows a migration present locally but with
an empty Remote column (because it was applied outside the CLI, e.g. via the
dashboard SQL editor or the Supabase MCP tools), reconcile the history
without re-running the SQL:

```bash
npx supabase migration repair --status applied <version> [<version> ...]
npx supabase migration list   # confirm the Remote column is now populated
```

## 5. Apply

```bash
npx supabase db push --yes
```

`db push` (like every subcommand on this CLI version) exposes a global
`--yes` flag ("answer yes to all prompts"), so it **can** be run
non-interactively — pass `--yes` to skip the confirmation prompt that would
otherwise block an automated or headless run. Omit `--yes` for a manual run
if you want to review the pending migration list before confirming.

## 6. Naming new migrations

New migration files follow the existing four-digit
`NNNN_snake_case_description.sql` scheme already used by `0001`-`0010`
(next one for this phase is `0011_buddy_sessions.sql`), **not** the CLI's
default timestamp-based scheme produced by `supabase migration new`. Hand-name
the file and drop it directly into `supabase/migrations/` — `db push` picks
up any file in that directory by lexical (filename) order, regardless of how
it was created.

## Do not

- **Do not edit an already-applied migration file.** Once a migration's
  filename appears in `migration list`'s local *and* remote columns, treat it
  as immutable. Write a new migration to change previously-applied behaviour.
- **Do not run `supabase db reset` against the linked remote.** `db reset` is
  a destructive local-development command; run it only against
  `--local`, never against `--linked` / the default linked target.
- **Do not run `supabase db pull` and commit its output.** Doing so would
  rewrite `0003_sync_rls.sql`, which is **frozen** and hash-pinned by
  `test/buddy/rls_frozen_test.dart` (see BUD-05 in
  `.planning/phases/11-gym-buddy-live-workout/`). None of the policies in
  `0003_sync_rls.sql` may be modified, widened or replaced — full stop.
- **Do not install the CLI via `npx --yes supabase@latest`** in any script,
  CI config, or ad hoc terminal command that gets copy-pasted into a repo
  file. Always use the pinned `npm install` / `npx supabase` route in §1, or
  a verified install from an official channel (winget, the official GitHub
  releases page, or the official scoop bucket) if the pinned route is
  unavailable.
