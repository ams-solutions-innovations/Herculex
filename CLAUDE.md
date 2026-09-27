# Herculex

Flutter app for training, nutrition, fasting and recovery tracking. Phone
(Android/iOS), a Wear OS companion under `android/wear/`, and Android home-screen
widgets. Offline-first on drift/SQLite with optional Supabase sync.

Flutter 3.44 · Dart 3.12 · Riverpod · go_router · drift

## Commands

```bash
flutter analyze                      # ~30-60s. Must be 0 errors.
flutter test                         # ~2min. 1308 pass / 4 skipped.
dart run tool/check_structure.dart   # layout rules (see docs/ARCHITECTURE.md)
dart format lib test tool
tool/codegen.ps1                     # drift build_runner (or -Watch)
```

`flutter analyze` exits 1 on warnings as well as errors, so check the error
count, not just the exit code. Both it and `flutter test` print far more than a
terminal shows — redirect to a file rather than piping to `tail`, and be aware
that **piping loses the real exit code** (you get `tail`'s).

Test output uses `\r` for progress; `tr '\r' '\n'` before grepping.

## Layout

`lib/` is feature-first. The rules and the reasoning are in
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md); the short version:

```
lib/
  app/           bootstrap, DI (providers.dart), router/
  core/          utilities — error/ notifications/ utils/
  design_system/ tokens/ theme/ components/
  data/          local/ (drift) sync/ (Supabase)
  services/      ai/ platform/
  features/<name>/ data/ domain/ application/ presentation/
```

Inside a feature: `domain/` is plain Dart (no Flutter), `data/` holds
repositories, `application/` holds Riverpod providers and controllers,
`presentation/` holds widgets. Once `presentation/` reaches 8 files it splits
into `views/ sheets/ dialogs/ widgets/`, and the filename suffix decides which.

**`core/` and `design_system/` must never import `features/`.**

## Conventions

- **Imports are always `package:herculex/...`**, never relative. A file move is
  then `git mv` plus one search-and-replace. `part`/`part of` stay relative
  (language rule); so do same-folder barrel exports. Cross-directory `export`
  is **not** covered by the lint — spell those `package:` by hand or they break
  silently on the next move.
- **No hand-written file over 600 lines.** 51 are still over; the checker lists
  them. Split with `part`/`part of` in a subfolder named after the file, which
  keeps the public import path unchanged. Parts cannot have their own imports.
- **Route paths are constants** in `app/router/routes.dart` — `AppRoutes.x`, or
  `AppPaths.x(id)` for parameterised ones. Never a string literal at a call
  site.
- **The UI never touches drift directly.** If you are reaching past a
  `*_repository.dart`, add a method to the repository instead.
- **All time-of-day math goes through `Clock`** (`core/utils/clock.dart`).
  Tests override it; `DateTime.now()` sprinkled in code breaks them.
- Prefer `StreamProvider` over `FutureProvider` for drift reads — live updates
  come free and you never invalidate a cache by hand.
- `@DataClassName` is mandatory on new tables; drift's default pluralisation
  produces `SetEntrie`.

## Schema changes are five chores, not one

Bumping the drift `schemaVersion` without all of these fails ~26 tests, or
silently quarantines cloud sync (worse — it looks fine locally):

1. `schemaVersion` in `lib/data/local/database.dart`, plus an `onUpgrade`
   `if (from < N)` branch.
2. `dart run drift_dev schema dump lib/data/local/database.dart drift_schemas/`
3. `dart run drift_dev schema generate drift_schemas/ test/generated_migrations/`
4. Retarget the tests: `test/migration_test.dart` (every `migrateAndValidate`
   call, plus a new replay from the newest fixture) and `test/schema_v2*.dart`
   (`newVersion:`, `DatabaseAtVNN`, and one hardcoded `PRAGMA user_version`).
5. **A matching `supabase/migrations/NNNN_*.sql`** if the table is synced.
   `SyncService` does `SELECT *` and forwards every non-FK column, so a column
   that exists locally but not in Postgres makes PostgREST answer PGRST204 and
   the outbox quarantines the row after 8 attempts.

Guard `addColumn` steps against `pragma_table_info` rather than running them
unconditionally: the hand-written fixtures sit on both sides of any given step
— some are too narrow to have the table at all, others build it from current
definitions and already have the columns.

Migrations are written but **not applied**. `0015` and `0016` are both
outstanding; apply in order before shipping a build that carries local v37.

## Gotchas

- **Gradle:** direct `gradlew` calls need Android Studio's bundled JBR, not the
  system JDK 26. `flutter build` handles this itself.
- **Supabase project ref is `ldzgyzigvbwofbswitrv`.** `jioesomepkauponjrena` is
  a different product and was wrongly configured repo-wide until 2026-08-15.
- Line endings: the repo stores LF, git checks out CRLF. `git diff` reports
  whitespace-only churn after any stash/checkout — use
  `git diff --ignore-all-space` to see whether a change is real.
- `git mv` in a tight loop occasionally loses a race on `.git/index.lock`.
  Check that every move landed.

## Active tracks

Two roadmaps are live and own parts of the tree. Coordinate before editing:

- `.planning/ROADMAP.md` — GSD project roadmap, milestone **v2.0, Phases 15–29**.
  Phases 15–21 are complete; 22–29 are pending. Phase 11 (Gym Buddy) shipped
  with v1.0 and now lives in `.planning/milestones/v1.0-ROADMAP.md` — it is not
  the current focus. Phase 10 (assisted rep tracking) was removed from the
  roadmap entirely on 2026-09-01 — `lib/features/reps/` no longer exists, and
  no feature is exempt from the layout rules below any more.

  **Execution order is not numeric** — see the roadmap's own note. Phases 26–29
  (Herculex AI: knowledge base, AI program generation, adaptive TDEE, weekly
  report) were appended on 2026-09-27 to preserve numbering, but run
  `26 → 28 → 27 → 22 → 23 → 29 → 24 → 25`. Design detail lives in
  [docs/herculex-ai-plan-2026-09-27.md](docs/herculex-ai-plan-2026-09-27.md).
  House rule for all AI work, unchanged since `06-AI-SPEC.md`: deterministic
  primary, AI bounded, AI never writes to the database, user confirms.
- `docs/ui-rework/ROADMAP.md` — UI/UX rework. Phase 9 (in progress) owns
  deleting the `AppColors` shim (`design_system/theme/colors.dart`, ~119
  importers) and the app-wide literal-colour sweep. Phase 7 owns splitting
  `active_exercise_card.dart`, unblocked now that rep tracking is gone.
