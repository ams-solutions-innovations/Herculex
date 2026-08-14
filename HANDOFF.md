# Herculex — Handoff

This document describes the project state at the end of **Phase 3** and what's left to build in **Phases 4–9** to reach the original vision (MyFitnessPal + Hevy + cycle/recovery intelligence).

---

## Current state (end of Phase 3)

### What's working

- **Local-first foundation** (Supabase auth wired; cloud sync not yet built). Profile + display name stored in `SharedPreferences`. Auth guard via go_router redirects between `/landing → /login → /onboarding → /app`.
- **Workout logger** (Hevy core, Phase 2): start empty workouts, log sets with weight/reps/RPE, auto rest timer, last-time hint, swipe-to-delete, supersets schema present (UI not yet wired), workout history, Insights tab with weekly tonnage chart + top-5 1RM projections.
- **Nutrition logger** (MFP core, Phase 3): daily diary with meal sections, food picker with Search/Recent/Recipes/Custom tabs, barcode scanner, OpenFoodFacts lookup with local caching, custom food creation, recipe builder, macro targets calculated from profile (Mifflin-St Jeor), live macro rings on the dashboard.
- **Five-tab shell**: Dashboard · Nutrition · Workout · Programs · Insights. Each tab is now backed by real data except Programs (still the Phase-1 visual mock).

### Tech stack

- **State**: Riverpod 2.x (no codegen — manual providers)
- **Routing**: go_router 14 with auth guard
- **DB**: Drift 2.x (codegen needed via `build_runner`)
- **HTTP**: `http` package
- **Camera**: `mobile_scanner`
- **Charts**: `fl_chart`

### File layout

```
lib/
├── app/                  app.dart, router.dart, providers.dart
├── core/                 clock, result, failures
├── data/local/           tables.dart, database.dart, seed_data.dart
├── features/
│   ├── auth/             Supabase auth + local session cache
│   ├── profile/          on-device profile
│   ├── onboarding/       3-step wizard
│   ├── dashboard/        live macros, fasting placeholder, today's plan placeholder
│   ├── nutrition/        daily diary, food picker, barcode scanner, recipes
│   ├── workouts/         active workout, exercise picker, rest timer, history
│   ├── programs/         placeholder + Phase-1 training-blocks mock
│   ├── health/           Phase-1 mock (apple/google/samsung toggles)
│   ├── analytics/        tonnage chart + 1RM projections
│   ├── admin/            admin dashboard, exercise/recipe forms
│   └── shell/            main bottom-nav scaffold
├── widgets/              floating nav bar, glass container, premium button/field
└── theme/                colors, app_theme
```

### How to run

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs    # required after every Drift table change
flutter run
```

Or use `tool/codegen.ps1` (Windows) / `./tool/codegen.sh` (Unix). Use `--watch` to rebuild on save.

**Until codegen runs**, IDE will show errors about `FoodData`, `RecipeData`, `WorkoutSessionData`, `_$AppDatabase`, etc. — all come from `lib/data/local/database.g.dart`. After codegen these vanish.

### Known minor cleanups deferred

- `Switch.activeColor` / `Slider.activeColor` deprecation warnings (Flutter 3.31+ → `activeThumbColor`). Cosmetic.
- `ColorScheme.background` / `onBackground` deprecated in `app_theme.dart`. Cosmetic.
- A few `// ignore: unused_*` markers in dashboard for the legacy macro card kept for visual reference.
- `_buildImageBanner` on dashboard still points at a hard-coded "Core & Flow" mobility routine — wire to a real program once Phase 5 lands.
- Dashboard "Today's Plan" section is hardcoded — needs to read from program engine (Phase 5).
- Dashboard "Luteal Phase Focus" card is hardcoded — driven by Phase 7 (cycle sync).
- Fasting widget on dashboard is hardcoded `14:20 remaining` — driven by Phase 4.

---

## Phase 4 — Intermittent Fasting Timer

**Why now**: small, self-contained, replaces the most visible hardcoded element on the dashboard.

### Data

- New Drift table `fasting_sessions(id, startedAt, endedAt, targetSeconds, completed)`.
- Bump `schemaVersion` to 3; add `onUpgrade` branch.

### Domain / repo

- `FastingPlan` enum: `h12`, `h14`, `h16`, `h18`, `h20`, `custom`
- `FastingRepository.startSession(target)`, `endSession()`, `watchActiveSession()`, `watchHistory()`, `currentStreak()`, `averageEatingWindow(days)`

### UI

- Replace `_buildFastingWidget` on dashboard with a real consumer of `activeFastingProvider`.
- Tap → opens fasting controls bottom sheet (start/stop, pick plan, see streak & average eating window).
- Optional: separate full-screen fasting view at `/fasting`.

### Acceptance

- Start a 16h fast → ring fills proportionally → kicks notification at end (defer notifications to Phase 6 platform integration phase).
- Streak counter increments after a completed fast; resets after a missed day.

**Estimated effort**: 1 day.

---

## Phase 5 — Programs & Training Blocks (DONE)

Full periodized program builder, split generation, marketplace preset templates, week/month calendar timelines, drag-to-move rescheduling, muscle conflict detection, day inspection sheets, and pre-populated smart workout launching. 29 automated tests passing.

### Data

```
programs              # id, name, description, weeks, created_by_user, archived
program_weeks         # program_id, week_index
program_days          # program_week_id, day_of_week (1-7), name
program_day_exercises # program_day_id, exercise_id, target_sets, target_reps_min, target_reps_max, target_rpe, order_index
scheduled_workouts    # date_iso, program_day_id, completed_session_id (nullable), status (planned|done|missed|moved)
external_events       # date_from_iso, date_to_iso, type (vacation|illness|travel|high_activity), notes
```

### Domain / repo

- `Program` builder API (create from scratch or clone a template)
- `Scheduler`:
  - `materializeProgram(programId, startDate)` — writes `scheduled_workouts` for each program day across `weeks × 7` days
  - `moveWorkout(scheduleId, newDate)` — handles conflicts (auto-shift downstream)
  - `addEvent(event)` — when a multi-day event lands, scheduler defers / volume-reduces overlapping workouts (see Phase 6 for the activity-based volume reduction logic — Phase 5 leaves the hook, Phase 6 fills the body)
  - `recoveryConflict(scheduleId)` — flags too-close hits to same muscle group

### UI

- Rewrite `training_blocks_view.dart` (currently the Phase-1 mock):
  - Segmented control: 1 / 3 / 6 month view (already in the mock)
  - Horizontal or vertical timeline with `Draggable` week cards (already mocked; needs to bind to real data + drag-handler that calls `Scheduler.moveWorkout`)
  - Conflict cards driven by `recoveryConflict()` output
- New view: `program_editor_view.dart` — build a program week-by-week
- New view: `program_library_view.dart` — pick a template or your own
- New view: `program_day_workout_view.dart` — when starting a scheduled workout, the active workout screen pre-populates with `program_day_exercises` (replaces the current "empty workout" flow when launched from a scheduled day)

### Hooks for later phases (leave stubs)

- `Scheduler.adjustForActivity(date, externalEventType)` → Phase 6 fills this when health-plugin data is wired
- `Scheduler.adjustForCyclePhase(date)` → Phase 7 fills this

### Acceptance

- Build a 4-week PPL program → place start date → calendar populates
- Drag Wednesday's "Push" to Thursday → Thursday's "Pull" auto-shifts to Friday with a "moved" badge
- Add a vacation event Nov 12-15 → those days marked "skipped"; downstream workouts compress or skip per a rule the user picks

**Estimated effort**: 4-6 days.

---

## Phase 6 — Health Integrations

Wires Apple Health, Google Health Connect (Android), and pedometer data so the program adjuster can react to outside activity.

### Dependencies

- `health: ^11.x` — single Flutter plugin covering both Apple Health and Health Connect
- `pedometer: ^4.x` — fallback raw step counter if user denies Health permissions

### Data

- New Drift table `health_samples(date_iso, kind, value)` — daily rollup of steps, active calories, sleep hours, resting HR
- Sync job: `HealthSyncService.runDailySync()` — pull last 24h from the plugin, upsert into `health_samples`

### Domain

- `ActivityBasedAdjuster.suggest(date)` — given today's steps + active kcal vs. user's baseline, returns a recommendation: `{noChange | reduceVolume(pct) | skip}`. Plugs into Phase 5's `Scheduler.adjustForActivity`.

### UI

- Replace `health_integrations_view.dart` Phase-1 mock with a real connection flow:
  - "Connect Apple Health" / "Connect Health Connect" buttons → permission dialog → status badge
  - List of pulled data points
  - Toggle: "Auto-adjust gym volume on high-activity days"

### Platform setup

- iOS: HealthKit entitlement, `NSHealthShareUsageDescription` in Info.plist
- Android: Health Connect requires API 26+ and the Health Connect app on the device; permission rationale activity in manifest

### Acceptance

- Connect Health Connect → see today's steps appear in the integrations view
- Walk 18,000 steps → next scheduled workout shows "Volume reduced 20% due to high activity"

**Estimated effort**: 2-3 days.

---

## Phase 7 — Cycle Syncing

### Data

- `cycle_logs(date_iso, phase, intensity, manual_override)` where `phase ∈ {menstrual, follicular, ovulatory, luteal}` and `intensity ∈ 1..5`
- Optional: `cycle_settings(avg_cycle_days, avg_period_days, last_period_start)` — single-row settings for cycle prediction

### Domain

- `CyclePredictor.phaseFor(date)` — given last period + average length, computes the phase
- `CycleAwareAdjuster.suggest(date)` — luteal/menstrual reduce intensity 15-30%; follicular boost 5-10%. Hooks into Phase 5's `Scheduler.adjustForCyclePhase`.

### UI

- Cycle settings under profile: enter last period start, cycle/period length
- Manual phase override per day (1-5 intensity)
- Optional Flow app integration (Apple Health cycle data — reuse Phase 6's `health` plugin)
- Wire the dashboard "Luteal Phase Focus" card to read live phase + adjustment

### Acceptance

- Set last period Nov 1, 28-day cycle → today shows correct phase
- During luteal week, scheduled leg day shows "Volume reduced 20% — luteal"
- Manual override on a single day overrides the auto-prediction

**Estimated effort**: 1-2 days. Skip the Flow integration; reuse Apple Health's cycle data instead.

---

## Phase 8 — Analytics & Recovery

### Recovery heatmap

- New domain: `MuscleRecovery.compute(asOf)` — for each muscle group, walk back through the last 30 days of completed sets, weighted by RPE and recency; output `{muscle: fatigueScore 0..1}`
- New widget: a body silhouette (front + back) with muscle group regions tinted by fatigue
- Cards: "Recovered" (green), "Recovering" (yellow), "Fatigued" (red)

### Push/pull balance

- `BalanceAnalyzer.summary(window: 4 weeks)` — sums set-volume tagged by `force` (push/pull/static) and flags asymmetries > 25%

### Biometric correlations

- Sleep vs RPE: scatter — sleep hours (X) vs avg session RPE (Y)
- Resting HR vs tonnage: track whether elevated HR correlates with reduced output
- Both need Phase 6's `health_samples` table

### UI

- Expand Insights tab with new cards under the existing tonnage / 1RM cards
- Each correlation card has an info icon with a methodology blurb (R² value, sample size)

### Acceptance

- Heatmap shows chest fatigued (red) after a heavy press day, recovering 48h later
- Sleep vs RPE shows the expected inverse correlation after ~20 sessions of data

**Estimated effort**: 3-4 days.

---

## Phase 9 — Smart Substitution & Calendar Export

### Smart substitution (biomech matching)

The taxonomy is already in `exercise_catalog` (mechanics, force, plane, equipment, primaryMuscle).

- `ExerciseSubstitution.findReplacements(exerciseId)`:
  - Filter by exact `mechanics` + `force` + `plane` match
  - Score by equipment availability (user-set "available equipment" toggle in profile)
  - Score by user history (recently performed → higher confidence)
- Wire to the existing `smart_substitution_sheet.dart` (currently still the Phase-1 visual mock)
- Trigger from active workout's exercise menu: "Substitute"

### Calendar export

- `device_calendar` plugin (~3.x)
- One-way export: scheduled workouts → user's iCloud / Google Calendar
- Event title: program day name + emoji (Leg Day 🦵, Push Day 💪, etc.)
- Settings: target calendar, lead time (default same-day 8am)
- Two-way sync explicitly out of scope (one-direction is plenty for v1)

### Acceptance

- In an active workout, tap "Substitute" on Barbell Bench → see Dumbbell Bench Press, Machine Chest Press, Push-Up as top suggestions (all horizontal-push compounds)
- Enable calendar sync → next 7 days of scheduled workouts appear in Google Calendar with emoji suffixes

**Estimated effort**: 2-3 days.

---

## Phase 10 — Supabase Backend — DONE

Originally planned as a Firebase migration; **superseded**. Replaced by Supabase —
see `docs/supabase-auth-wear-setup.md`, `docs/rb01-gemini-secret-remediation.md`,
and `docs/rb02-sync-verification.md` for full design and verification logs.

### Auth — DONE

- `supabase_flutter` (pure Dart, so iOS works seamlessly).
- `AuthProviderService` interface + `SupabaseAuthService`; `AuthRepository`'s
  public API is unchanged.
- Session persisted via `SecureAuthStorage` (Keychain / EncryptedSharedPreferences).
- Auth state is a live subscription (`onAuthStateChange`) observing token refresh
  and expiry.
- `UnconfiguredAuthService` keeps credential-less builds and tests fully local-first.

### Cloud Sync — DONE

- **Schema v25+**: Added `syncUuid`, `updatedAt`, `deletedAt`, `syncedAt` across
  all 36 user tables.
- **Server migrations**: `0001`–`0007` applied to Supabase PostgreSQL, with 100%
  RLS coverage (`user_id = auth.uid()`), server-enforced `updated_at` timestamps,
  `sync_tombstones` hard-delete propagation, and Realtime publication on all 37 tables.
- **Sync Engine**: `SyncService` outbox architecture driven by SQLite triggers,
  parent-first ordering, natural-key resolution for seeded catalogue items vs
  `sync_uuid` for custom rows (`is_custom`).
- **Edge Functions**: `gemini-analyze` deployed on Supabase Functions using server-side
  `GEMINI_API_KEY` for AI photo/label analysis.
- **Automated Round-Trip Verification**: Multi-client live sync test suite
  (`test/sync/live_round_trip_test.dart`) passes green against the live backend.

---

## Phase 11 — Polish & Pre-release (when shipping publicly)

- Onboarding pickers for **sex** (`Profile` currently assumes male in BMR — see `MacroTargets.fromProfile`)
- **Imperial units** option (lb/in/oz). Storage stays metric; display layer converts.
- **Bodyweight-loaded sets** (Pull-Up + 25kg etc.) — add `bodyweight_offset_kg` column to `set_entries`
- **Settings screen** consolidating profile edit, units, attribution (OFF), data export
- **Data export** (JSON) for paranoia / backup
- **A11y pass** — semantic labels, contrast check on all `withValues(alpha:)` calls
- **Empty states polish** — most are functional but plain
- **App icons + splash** — currently default Flutter
- **Localization** scaffolding — currently English-only
- **Notifications** — `flutter_local_notifications` for fasting end / scheduled workout reminders

---

## Phase ordering recommendation

```
Phase 4  ──▶  Phase 5  ──┬──▶  Phase 6  ──▶  Phase 7
                         │       (health)      (cycle)
                         │
                         └──▶  Phase 9 (substitution)
                                  │
                                  └──▶  Phase 8 (analytics — needs Phase 6 data)
                                          │
                                          └──▶  Phase 10 (Supabase)
                                                  │
                                                  └──▶  Phase 11 (polish)
```

- Phase 4 is small and clears the most visible mock from the dashboard. Do it next.
- Phase 5 is the big one — unlocks dashboard's "Today's Plan" and is a prereq for almost everything else's UX.
- Phase 6 unlocks both Phase 7 (cycle) and Phase 8 (correlations).
- Phase 9 can run in parallel with Phase 6/7/8 if you want — independent.

---

## Architecture notes for future-you

- **Repositories are the only thing the UI sees**. UI never imports Drift directly; if you find yourself reaching past `*_repository.dart`, lift it into a method on the repo.
- **All time-of-day math goes through `Clock`** (`lib/core/clock.dart`). Tests override it; production uses `SystemClock`. Don't sprinkle `DateTime.now()` directly — it bites tests.
- **Drift streams power live UI everywhere.** Don't manually invalidate caches; let the watch queries re-emit.
- **`@DataClassName` annotations are mandatory** on new tables — Drift's default pluralization produces ugly names (`SetEntrie`, etc.).
- **Schema version bump checklist**: add the `@DataClassName` annotation, register the table in `@DriftDatabase(tables: [...])`, bump `schemaVersion`, add an `onUpgrade` branch that creates the new table for users coming from the previous version.
- **Riverpod**: prefer `StreamProvider` over `FutureProvider` when reading from Drift — you get live updates for free.
- **For features that need cross-context state** (rest timer, active workout, selected nutrition date), use `NotifierProvider` / `StateProvider`. Don't pass state down through constructors more than 2 levels deep.

---

## Open questions worth answering before continuing

1. **Sex in `Profile`** — onboarding currently doesn't ask. BMR is ~10% off for women. Either add to onboarding or skip the BMR calculator and let user enter targets manually. (Recommend: add sex to onboarding before Phase 4 — single dropdown.)
2. **Default plate weight / units** — currently kg-only. Will users want lb? Decide before Phase 11.
3. **Notifications scope** — fasting timer end, rest timer end, scheduled workout reminders. All trivially supported by `flutter_local_notifications`. Pick a phase to add them (recommend bundling into Phase 4 since fasting + rest timer share the same plugin).
4. **OFF attribution placement** — currently in the food picker footer. Public release may need a clearer credit (settings screen).
