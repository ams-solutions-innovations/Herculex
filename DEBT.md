# Technical Debt

Last updated: 2026-08-17

Known shortcuts, deliberate non-fixes, and cleanup owed. Not blockers — the
app works with these in place — but worth knowing before building on top of
them.

---

## Auth & Security

- **Email verification is deferred to v2.** Supabase Auth currently creates active sessions upon signup without requiring an email confirmation round trip. Email verification workflow is planned for v2.
- **Leaked-password protection (HaveIBeenPwned)** is a Supabase feature gated
  on Pro plans and above. The setting cannot be toggled on the free tier. When
  the project is upgraded to Pro, toggle on in Authentication -> Password Security.
- **External Privacy Policy Web Hosting**: Privacy Policy and Terms of Service documents are finalized in `docs/` for in-app transparency; they must be deployed to the AMS Solutions Studio website (`amssolutions.studio/herculex/privacy`) prior to App Store Connect submission. Note: Tremble project is strictly separate and untouched.

## Sync layer

- **Account switch on a shared device leaves the previous user's local rows
  in place.** The outbox and cursors are cleared on uid change so nothing
  leaks *upward* into the wrong cloud account, but the prior user's rows
  stay in the local Drift database and are visible to whoever signs in next
  on that device. Full per-user isolation (wipe or partition local data on
  switch) is a real change to app startup and the database lifecycle, not
  a quick fix. Documented in `docs/rb02-sync-verification.md` and `docs/DATA_TRUTH_TABLE.md`.
- **The 90-day full-reconcile fallback (`_fullReconcile`) has only run in
  tests, never against the real backend.** Correct by inspection, but
  impractical to test honestly without either waiting out the retention
  window or hand-editing a device's tombstone cursor to fake staleness.
- **Outbox push order can still put an already-pending parent after its
  child**, if that parent gets re-edited while queued (the edit bumps its
  `created_at` past the child's, per the trigger's `ON CONFLICT ... SET
  created_at = excluded.created_at`). Self-heals through the normal retry
  path — the child's FK violation is just a push failure that clears on the
  next cycle — but it's a known soft spot, not a proven-impossible case.

## Housekeeping

- **Two accounts sit in the live project's `auth.users`** from RB-02
  verification: `martin.dumanic@gmail.com` (real account, currently holds a
  throwaway sync-test password — change it before using this account for
  real) and `aleksandar.bojic12@gmail.com` (fully throwaway, safe to delete
  whenever). Neither owns any data — cleanup confirmed 0 rows left behind
  after the verification runs.
- **`.secrets/live_sync.json`** holds both accounts' credentials in plain
  text, gitignored. Fine for a local dev machine; revisit if this ever needs
  to run in CI.

