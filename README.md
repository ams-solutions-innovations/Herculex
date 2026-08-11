# Herculex

Fitness, nutrition, and recovery tracking — **100% on-device**. No account, no
sign-in, no cloud: all data lives in a local SQLite database (Drift) and
`SharedPreferences` on the user's phone.

## Features

- **Workouts** — logging with equipment variants, accessories, bands, set types,
  per-gym machine configs; active-workout mode with a live lock-screen notification.
- **Programs** — periodization (linear / concurrent / block / max-effort), exercise
  rotation pools, micro-workouts, CSV import/export.
- **Analytics** — 19-group muscle recovery heatmap, CNS fatigue trends, per-variant
  PRs and 1RM estimates, progressive-overload targets.
- **Nutrition** — OpenFoodFacts lookup + barcode scanning, custom foods/recipes,
  macro rings, day-specific targets, carb cycling, fasting timer.
- **Health** — body measurements, progress photos, cycle tracking, activity adjustment.

## Tech stack

| Concern | Choice |
| --- | --- |
| State | `flutter_riverpod` |
| Routing | `go_router` |
| Local DB | `drift` + `sqlite3_flutter_libs` (schema v23) |
| Charts | `fl_chart` |
| Nutrition API | OpenFoodFacts via `http`, `mobile_scanner` barcode |

## Getting started

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # Drift codegen
flutter run
```

First launch goes straight to **onboarding** (goal, activity, optional name and
body stats). Completing onboarding writes the local profile and opens the app.
There is no login step.

## Project layout

```
lib/
  app/         # MaterialApp, router, root providers
  core/        # Clock, Result, Failures
  data/        # Drift database, seed data, sync engine
  features/    # Feature-first modules (data / domain / presentation each)
  theme/       # Dark theme, colors, haptics
  widgets/     # Shared UI (glass containers, nav bar, buttons)
```

## Developer tools

Content-seeding admin screens (`/admin`, insert workout/recipe) are **debug-only**
— the routes are compiled out of release builds (`kDebugMode` in
[`lib/app/router.dart`](lib/app/router.dart)).

## Tests

```bash
flutter test
flutter analyze
```

## Releasing

See [RELEASE.md](RELEASE.md) for app-id, signing, and store-submission steps.
