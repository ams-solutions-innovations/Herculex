# Tasks

Last updated: 2026-08-13

Split by whether it's needed for current app functionality (**Now**) or can
wait (**Later**); see `CONTEXT.md`'s working agreement. Security/active-risk
items live in `BLOCKERS.md`, not here.

---

## Now

Nothing outstanding from RB-02. The sync engine is functionally complete and
proven against the live backend; nothing here is stopping current development.

RB-01 is closed: client-side Gemini key paths are removed, `GEMINI_API_KEY` is
set as a Supabase Function secret, and `gemini-analyze` is deployed.

---

## Later

### RB-02 close-out — COMPLETE

- [x] Manual device pass on Samsung Galaxy S25 Ultra: sign-in starts sync,
      Profile badge transitions ("Syncing…" -> "Synced"), offline queueing
      ("5 pending"), and automatic reconnect push. Verified live.
- [ ] Decide fate of the two live test accounts (`DEBT.md` -> Housekeeping).
      At minimum, change `martin.dumanic@gmail.com`'s password before real use.

### Sync follow-ups

- [x] Fix `FakeSyncBackendService.pull`'s inclusive cursor comparison to match
      Postgres's exclusive `gt()`.
- [ ] Consider whether the outbox re-edit-reorders-parent-after-child edge case
      (`DEBT.md` -> Sync layer) is worth a real fix or stays as a documented
      self-healing gap.

### Documentation

- [x] Rewrite `HANDOFF.md`'s Phase 10 section (Supabase sync complete and verified).
- [x] Add a Supabase setup section to `RELEASE.md`.

### Everything else

- [x] Phase 4 (Fasting Timer): Full repository, custom plans, start-time editing, completion notifications, and unit test suite verified.
- [x] Phase 5 (Programs & Training Blocks): Periodization models, split generator, marketplace presets, week & month calendar views, day detail sheets, drag-reschedule, muscle conflict detection, and smart workout pre-population. 29 tests passing.
- [ ] RB-04 optional device pass (`docs/rb04-device-verification-plan.md`).
- RB-01, RB-02, RB-03, and RB-05 are all closed and verified.
- [x] Phase 6 (Health Integrations): Apple Health, Health Connect, Samsung Health adapter layer, daily rollups, activity volume adjusters, and CNS load mapping.
- [x] Phase 7 (Cycle Syncing): Pure domain cycle predictor, physiological volume adjuster, Flo & HealthKit period sync, manual daily overrides, dynamic dashboard focus card, and cycle tracking sheet. 12 tests passing.
- [ ] Phases 8-9 of the feature roadmap (`HANDOFF.md`):
      analytics/recovery, smart substitution + calendar export.
- Samsung Now Bar (Phase 08) deferred to January.
