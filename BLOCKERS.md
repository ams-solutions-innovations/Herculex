# Blockers

Last updated: 2026-08-13

Scope: things that stop current app functionality from working, or that are an
active risk right now, not "should fix before a public release." The app is
still being built; longer-range/deferred items belong in `TASKS.md` or
`DEBT.md`, not here.

---

## Open

None.

*(Leaked-password protection via HaveIBeenPwned was evaluated and is gated on Supabase Pro plans; tracked in `DEBT.md` for when the project upgrades tiers).*

---

## Tracked elsewhere, still open

From the 2026-08-10 audit (`docs/app-audit-report-2026-08-10.md`), listed here
only so nothing gets lost:

- **RB-04**: database FKs; code complete and enforced (`PRAGMA foreign_keys = ON`, schema v23 repair), optional device delete pass in `docs/rb04-device-verification-plan.md`.

RB-05 (nutrition history immutability & catalog soft-deletes) is closed; verified with snapshots and `test/rb05_soft_delete_test.dart`.

RB-03 (health data fabricated when platform reads fail) is closed; see
`docs/rb03-health-read-state-plan.md`.

RB-02 (cloud sync reporting success without real sync) is closed; see
`docs/rb02-sync-verification.md`.

RB-01 (Gemini API key embedded in the client) is closed; see
`docs/rb01-gemini-secret-remediation.md`.
