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

- [x] **REP-01**: Rep tracking is off until the user completes a dedicated consent screen, and then off per exercise until separately enabled. It is offered only for the enumerated eligible slugs.
- [x] **REP-02**: The user chooses the sensor source. The phone accelerometer is used only when a placement is explicitly selected.
- [x] **REP-03**: The tracker never completes, saves or alters a set. Every rep count and RPE reaches the database only through a user confirmation, and the tracker feature directory contains no reference to the set write path.
- [x] **REP-04**: Raw accelerometer samples are processed on the user's devices and discarded at set end. Only derived features and confirmed outcomes persist, and none of it syncs.
- [x] **REP-05**: An RPE suggestion appears only after ≥ 10 confirmed sets across ≥ 3 sessions for that exercise/device/placement, and only when leave-one-out error is within 1.0 RPE point. Low confidence, changed placement or unsupported movement yields a count-only state.
- [ ] **REP-06**: Recorded motion traces for pull-ups and dips verify counting accuracy, missed-rep handling, false-positive resistance, source and placement changes, and the never-auto-complete guarantee.

## v2 Requirements

- **PLAN-01**: Recipe URL import with user review/matching.
- **PLAN-02**: Meal planner, grocery list and dietary-preference/allergen planning.
- **SOC-01**: Sharing/copying diaries across users after an account and sync model exist.
- **VOICE-01**: Voice food entry when a supported, privacy-reviewed recogniser is selected.

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
