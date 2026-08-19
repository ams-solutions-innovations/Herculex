# Requirements: Herculex Nutrition completion

**Defined:** 2026-07-30
**Core Value:** Find or capture the correct food, choose a realistic portion, and log it with trustworthy nutrient totals in seconds.

## v1 Requirements

### Catalogue and search

- [ ] **CAT-01**: App contains an export of all source workbook food rows with source, basis, nutrient, allergen and quality metadata preserved.
- [ ] **CAT-02**: Exact barcode lookup treats barcode identifiers as strings and works offline.
- [ ] **CAT-03**: Search ranks exact barcode/name/brand matches ahead of partial matches and supports brand/category/country filters.
- [ ] **CAT-04**: User can inspect source basis, completeness and nutrients before logging.

### Diary and portions

- [ ] **DIA-01**: User can log a food by grams, millilitres where applicable, or an available labelled serving.
- [ ] **DIA-02**: User can add, rename, reorder, duplicate and delete meal slots under Edit nutrients; default slots remain Breakfast, Lunch, Dinner and Snacks.
- [ ] **DIA-03**: Diary supports recent, frequent, favourite, quick-add, copy-meal/day, timestamps, notes, saved meals, recipes and edits/deletes.

### Nutrients and goals

- [x] **NUT-01**: Each food preserves all supplied macro/micronutrients with canonical units and an explicit reference basis.
- [x] **NUT-02**: User can select nutrients shown in the diary and choose per-day/week views and targets where data exists.
- [x] **NUT-03**: Totals never imply zero when a selected nutrient is unavailable; UI displays availability/completeness.

### Capture

- [x] **CAP-01**: Barcode scan validates/normalizes EAN-8, UPC-A, EAN-13 and GTIN-14 and offers manual entry on a miss.
- [x] **CAP-02**: A label-photo OCR flow maps nutrition-label values into an editable draft before saving/logging.
- [x] **CAP-03**: Food-photo analysis is opt-in, shows confidence and proposed foods/portions, and requires review; internet lookup is an explicit secondary mode.

### Ongoing workout surface

- [x] **NOWBAR-01**: The ongoing workout is published as an Android 16 promotable Live Update — `requestPromotedOngoing(true)`, `ProgressStyle` and short critical text via the real platform API, so `hasPromotableCharacteristics()` reports true on a supporting device.
- [x] **NOWBAR-02**: Exactly one code path owns the ongoing workout notification id. The Flutter and native renderers never post to the same id, and the surface is not rebuilt once per second.
- [x] **NOWBAR-03**: The surface is cleared when the workout ends and when the app widget is disposed, and an action declaring `requiresUnlock` is not executed silently from the lock screen.

### Analytics correctness

- [x] **ANLY-01**: All recovery, CNS, balance and correlation providers read from the shared `trainingSnapshotProvider` effective-load snapshot instead of independent unfiltered table scans.
- [x] **ANLY-02**: The legacy coarse recovery engine (`muscle_recovery.dart`, `cnsFatigueProvider`) and the duplicate recovery card in Insights are removed; exactly one recovery model is shown.
- [x] **ANLY-03**: Every analytics query excludes soft-deleted (`deletedAt`) sets, sessions and exercises, so a cross-device sync delete cannot inflate tonnage, CNS load or recovery fatigue on another device.
- [x] **ANLY-04**: Push/pull balance and biometric-correlation cards compute from effective load (bands, chains, bodyweight) rather than raw weight/reps.

### Assisted rep tracking

- [x] **REP-01**: Rep tracking is off until the user completes a dedicated consent screen, and then off until a single global switch is turned on. Which exercises it applies to is derived from per-exercise capability profiles covering the whole catalogue, not from a per-exercise opt-in; the per-exercise control is an override that can only ever exclude. *(Revised in the catalogue-wide rework: the original wording required a per-exercise opt-in against an enumerated slug list, which asked the user to re-derive, exercise by exercise, a fact about sensor placement the app already knows.)*
- [x] **REP-02**: The sensor site is derived from the exercise, never chosen: exercises whose hands are anchored are sensed from a pocketed phone and the rest from the watch, and the requirement is stated before the set rather than discovered after it. The phone source still requires an explicitly selected placement. *(Revised: the original "the user chooses the sensor source" offered a choice with one correct answer per exercise, where a wrong answer presents as the tracker being broken.)*
- [x] **REP-03**: The tracker never completes, saves or alters a set. Nothing under `lib/features/reps/` references the set write path. A confidently detected count prefills the editable reps field and is written only when the user completes the set; a low-confidence, count-only or unmeasured result opens the review sheet instead. *(Revised: "reaches the database only through a user confirmation" is unchanged in substance — the write still happens on the user's own tap — but the confirmation is now completing the set rather than a second dialog per set, which at twenty sets was worse than typing the number.)*
- [x] **REP-04**: Raw accelerometer samples are processed on the user's devices and discarded at set end. Only derived features and confirmed outcomes persist, and none of it syncs.
- [x] **REP-05**: An RPE suggestion appears only after ≥ 10 confirmed sets across ≥ 3 sessions for that exercise/device/placement, and only when leave-one-out error is within 1.0 RPE point. Low confidence, changed placement or unsupported movement yields a count-only state.
- [ ] **REP-06**: Recorded motion traces verify counting accuracy, missed-rep handling, false-positive resistance, source and placement changes, and the never-auto-complete guarantee. **Scope grew with coverage**: one trace family per detection family per sensor site, not just pull-ups and dips. Still the phase's real gate, and still a human task in a gym.

### Gym Buddy — live shared workout

- [ ] **BUD-01**: Sharing an active workout is an explicit user action. A partner joins by scanning a short-lived, single-session QR code reached from an additional entry in the `+` button; the token cannot be reused after the session ends.
- [ ] **BUD-02**: Each participant keeps their own `WorkoutSessions` row, owned by them and synced under their own `user_id`. A shared `buddySessionId` links the two. No participant's sets, reps, weight, RPE or measurements are ever written into another participant's tables, and buddy sessions never double-count in analytics.
- [ ] **BUD-03**: Exercise choreography — add, remove, reorder and replace — propagates live between participants. Every change offers a scope choice of "both of us" or "only me"; "only me" never mutates the partner's exercise list.
- [ ] **BUD-04**: Live state travels over Supabase Realtime broadcast, and every choreography event is also appended to a durable event log, so a participant who loses connection, backgrounds the app or restarts the phone rejoins at the correct shared state rather than an empty one.
- [ ] **BUD-05**: The existing owner-only RLS policies in `0003_sync_rls.sql` are left unchanged. Cross-user visibility is confined to the new buddy tables and to a minimal participant display identity; no policy grants a partner read access to another user's training, nutrition or biometric tables.
- [ ] **BUD-06**: Either participant can leave a buddy session at any time. The other's workout continues uninterrupted, both sessions save normally, and a partner disconnecting is never able to complete, alter or discard the other's sets.

## v2 Requirements

- **BUD-07**: Buddy VS comparison in workout history — per-exercise winner, calisthenics rep counts and per-session volume, computed after the fact from both participants' sessions via the shared `buddySessionId`.
- **BUD-08**: Persistent friends model — user identity, search/invite, accept/block, so a relationship outlives a single scanned session.
- **BUD-09**: Friend challenges — each participant sets a goal with a deadline (strength target, body-fat %, kg lost or gained), progress is tracked from existing measurement and training data, and the challenge resolves at the deadline.
- **PLAN-01**: Recipe URL import with user review/matching.
- **PLAN-02**: Meal planner, grocery list and dietary-preference/allergen planning.
- **SOC-01**: Sharing/copying diaries across users after an account and sync model exist.
- **VOICE-01**: Voice food entry when a supported, privacy-reviewed recogniser is selected.

### Exercise catalogue (Phase 12)

- [x] **EXR-01**: Equipment variants of one movement collapse to a single picker entry; the plain version of a movement is the one a bare-name search lands on.
- [x] **EXR-02**: Grip, attachment and start-position variants collapse into their movement rather than occupying separate top-level rows.
- [x] **EXR-03**: Every category the app offers as a filter has exercises in it — including cardio, CrossFit and mobility.
- [x] **EXR-04**: `loggingMetric` is a single typed registry; the catalogue asset, the custom-exercise builder and the logger all read the same vocabulary.
- [x] **EXR-05**: A set is stored and displayed in its exercise's own units — duration, distance or calories where reps and kilos do not apply — without distorting tonnage or volume analytics.

### Hercul coaching layer (Phase 13)

- [ ] **HRC-01**: A dashboard card surfaces ranked observations derived from the user's own training, nutrition and bodyweight data.
- [ ] **HRC-02**: Observations come from an authored rule corpus stored as a JSON asset and imported locally, replaceable from the cloud later without changing the engine.
- [ ] **HRC-03**: Rule evaluation is a pure function; a rule with missing signals is skipped, and a fired rule is suppressed for its cooldown.
- [ ] **HRC-04**: The user chooses between two voices; the blunt voice is opt-in, gated on a stated age of 18 or over, and never targets the user's body or sex.
- [ ] **HRC-05**: No message asserts anything the app cannot show the underlying numbers for, and none constitutes medical advice.

### Anthropometric ergonomics (Phase 14)

- [ ] **ERG-01**: Profile height, plus optional inseam, arm span and torso measurements, yield proportion ratios.
- [ ] **ERG-02**: Movements carry variant guidance keyed to those proportions, with sources recorded.
- [ ] **ERG-03**: Guidance appears on the exercise and through Hercul, is absent when measurements are unknown, and is phrased as a trade-off rather than a correction.

## Out of Scope

| Feature | Reason |
|---|---|
| MyFitnessPal subscription/paywall model | Product decision unrelated to nutrition correctness. |
| Automatic camera diagnosis/logging | Insufficiently reliable without confirmation. |
| Public food-catalogue server | User asked for a JSON export first; server contract follows. |

## Traceability

| Requirement | Phase | Status |
|---|---:|---|
| CAT-01 | 1 | Complete |
| CAT-02–04 | 2 | Complete |
| DIA-01–03 | 3 | Complete |
| NUT-01–03 | 4 | Complete |
| CAP-01 | 5 | Complete |
| CAP-02–03 | 6 | Complete |
| NOWBAR-01–03 | 8 | Pending |
| ANLY-01–04 | 9 | Complete |
| REP-01–06 | 10 | In Progress |
| BUD-01–06 | 11 | Pending |
| EXR-01–05 | 12 | Complete |
| HRC-01–05 | 13 | Pending |
| ERG-01–03 | 14 | Pending |
