# Tasks

Last updated: 2026-08-17

Split by whether it's needed for current app functionality (**Now**) or can
wait (**Later**); see `CONTEXT.md`'s working agreement. Security/active-risk
items live in `BLOCKERS.md`, not here.

---

## Now

- [x] **Registration Input Minimization & Whitelisting**: `AuthValidator` enforcing RFC 5322 email regex, 2-30 character display name whitelist, 8-72 character password bounds to prevent hashing DoS.
- [x] **Anti-Spam, Anti-Bot & In-Flight Debounce**: `AuthRateLimiter` with 30s lockout after 5 consecutive failures, and `_authBusy` double-tap prevention in onboarding and profile auth sheets.
- [x] **Legal & App Store Compliance Docs**:
  - `docs/DATA_TRUTH_TABLE.md` (audit of local vs cloud data boundaries)
  - `docs/PRIVACY_POLICY.md` (GDPR & App Store Guideline 5.1.1 compliant)
  - `docs/TERMS_OF_SERVICE.md` (Health & medical liability disclaimers)
  - `docs/GDPR_ARTICLE_9_COMPLIANCE.md` (Legal & technical protection memo)
- [ ] **Deploy Privacy Policy & ToS to AMS Solutions Studio Website**: Publish static pages on `amssolutions.studio/herculex/privacy` and `amssolutions.studio/herculex/terms` for App Store Connect submission (strictly separate from Tremble).
- [ ] **App Store Connect Setup & Metadata**: Prepare screenshots, app description, and provide test account credentials.

---

## Later

### v2 Enhancements

- [ ] **Email Verification Flow ("Verify Email Thingy")**: Add mandatory confirmation loop via email before session generation (deferred to v2 per user decision).
- [ ] **Pro-tier Security**: Enable HaveIBeenPwned leaked password protection in Supabase once upgraded to Pro tier.

### Sync & Account Lifecycle

- [ ] Decide fate of the two live test accounts (`DEBT.md` -> Housekeeping).
      At minimum, change `martin.dumanic@gmail.com`'s password before real use.
- [ ] Account switch local database isolation / partitioning.

### Feature Roadmap (from `HANDOFF.md`)

- [x] Phase 4 (Fasting Timer): Full repository, custom plans, start-time editing, completion notifications.
- [x] Phase 5 (Programs & Training Blocks): Periodization models, split generator, marketplace presets, week & month calendar views, day detail sheets, drag-reschedule.
- [x] Phase 6 (Health Integrations): Apple Health, Health Connect, Samsung Health adapter layer, daily rollups, activity volume adjusters.
- [x] Phase 7 (Cycle Syncing): Pure domain cycle predictor, physiological volume adjuster, Flo & HealthKit period sync.
- [ ] Phases 8-9: Advanced recovery analytics, smart substitution, calendar export.
- [ ] Samsung Now Bar (Phase 08) deferred to January.

