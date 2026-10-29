# Web track — Herculex in the browser

Branch `feature/web`. Owner of everything web-specific in this repo.

## Decisions (2026-10-26)

- **The web app is this Flutter app**, built with `flutter build web` and deployed to `app.herculex.app`
  (Cloudflare Pages). UI, domain logic and `SyncService` are reused 1:1 — the browser is "just another
  device" with its own drift database, so it follows every sync rule the phone does.
- **The marketing site is separate**: a static Astro site in `../Herculex Web`, deployed to `herculex.app`.
  It ports the design tokens from `lib/design_system/` and copies `docs/PRIVACY_POLICY.md` and
  `docs/TERMS_OF_SERVICE.md` (`npm run sync-legal` there).
- **English only**, like the app.
- **Desktop layout**: same components and tokens; at ≥ 840 px on the web a frosted nav rail replaces
  `HxNavBar`, and content sits in max-width columns. The rail is always narrow and icon-only (labels are
  tooltips) and lists more than the phone's four tabs — see "Rail tools" below. Phone-width browsers keep
  the mobile layout. Native tablets are unchanged.
- **The web requires an account** (the phone does not). Signing out on the web wipes that browser's data.
- **Phone-only on the web**: health integrations and steps/sleep (health samples are not synced), watch,
  widgets, workout bubble, device calendar, local notifications, Gym Buddy, physique/progress photos, and
  **starting or logging a workout** (`PlatformCapabilities.hasLiveWorkout`). The web plans and reviews
  training; it never begins a session.
- **No Apple sign-in on the web** until a Services ID is configured. Google + email work.

## Phases

Order: W1 → W2 → W3 → W4 → W5 → W6 → W7 → W8. W3 must ship in a phone release **before** the web launch.

| Phase | Goal | Status |
| --- | --- | --- |
| W1 | Web compiles and boots locally: `PlatformCapabilities`, drift on wasm, native bridges gated, food JSON excluded from the web bundle | done |
| W2 | Accounts and routing: web sign-in (email + Google OAuth), `/sign-in`, `/reset-password`, initial-sync gate (`/restoring`), per-row pull isolation, web sign-out wipes the browser | done — `/auth/confirm` (token_hash links) waits for the email-template switch |
| W3 | Multi-device hardening: synced `user_preferences` table (schema v53) + bridge for the profile, meal slots, goals, supplements, units, colour theme | done — natural keys for `daily_summaries` / `carb_cycle_plans` still open |
| W4 | Remote food catalogue: `food_catalogue` table + `search_food_catalogue` RPC, `RemoteFoodCatalogueSource`, catalogue-ref prefetch on pull | done (code) — migration + upload not run yet |
| W5 | Desktop shell: `HxBreakpoints`, `HxNavRail`, `HxContentWidth`, `HxLayoutScope`, 4-column dashboard, centred `HxScreenShell`, quick-add beside the rail | done — rail lives in `MainScaffold`; pushed screens (`HxScreenShell`, or `HxRailFrame` for screens with their own `Scaffold`) show the same rail on wide web without quick-add, fed by `HxShellNavigationScope` from `app.dart` |
| W6 | Media, AI and export: `XFile` through the AI pipelines, Gemini-only label scan, browser downloads for exports | not started — Dream Physique photo steps and check-ins show a "runs in the phone app" notice on web until the `XFile` pipeline lands |
| W7 | Build and deploy: `web/` (index, manifest, splash, icons, `_headers`), `tool/web/build_web.ps1` / `deploy_web.ps1`, CORS allowlist on Edge Functions | done (code) — not deployed |
| W8 | Hardening: initial-pull performance, multi-tab, private-mode banner, privacy policy update, and the sync follow-ups below | not started |

A web build **without** Supabase credentials runs local-only like a phone
(`accountRequiredProvider`), which is what `flutter run -d chrome` gives you
unless you pass `--dart-define-from-file`.

## Desktop overviews and technique guide (2026-10-27)

Beyond the shell (W5), the screens people plan with now use the width:

- **Exercise library**: lazy grid of two or three columns (`HxMasonry.columnsFor`), chips wrap instead of
  scrolling sideways, `HxScreenShell(maxContentWidth: wideMax)`.
- **Workouts tab**: the tab takes `wideMax`; the live workout stays a 960 px column, history and templates are
  two columns inside 1040 px. **Programs** is a split view from 1000 px: week board (two lanes from 640 px) or
  month grid on the left, `UpcomingWorkoutsPanel` ("Coming up", next three weeks, grouped by day) on the right.
  The device-calendar sync button is hidden where there is no device calendar.
- **Training Techniques** (`/training-techniques`, `SetTypesGuideView`): what a drop set, myo reps, rest-pause…
  are, from `SetTypeInfo.all`. Linked from the exercise library, Profile → Library and Settings → Data & Library;
  `?type=<id>` puts one technique first. The marketing site has the same guide at `herculex.app/training-techniques`
  (`src/data/set-types.ts` there mirrors `SetTypeInfo` — change both together).

## Rail tools and no live workouts on the web (2026-10-28)

- **The rail is icon-only at every width** (`HxNavRail.width`, 76 px; the "extended" labelled rail and
  `HxBreakpoints.extendedRail` are gone). Below the four home tabs and a divider it lists `railTools`
  (`lib/features/shell/rail_tools.dart`): Exercise library, Insights, Labs, Body measurements, Fasting,
  Supplements. Add a tool by adding an `HxRailTool` there. When the window is too short for every icon the
  destinations scroll and quick-add stays pinned.
- Pushed screens get the same list through `HxShellNavigationScope.tools`; `app.dart` wraps it in
  `RouterLocationBuilder` (it defers a delegate notification that lands mid-build) and passes `currentTool`
  (`railToolIndexFor(location)`), so the open tool is highlighted
  instead of the last home tab. A tool opens with `openRailTool` (`go('/app')` then `push`), so Back returns to
  the home shell rather than stacking tools.
- **Labs now runs on the web** (it is no longer in `nativeOnlyRoutes`). It reads the synced tables; health
  samples do not exist on the web, so sleep/steps categories stay empty, and the consent in
  `SharedPreferences` is per browser. There is no PDF sandbox on the web: `LabsPdfService.canSaveFiles` is
  false, reports are kept as snapshots only and the share/export icon is hidden.
- **No way to start a workout on the web** (`hasLiveWorkout`): hidden are quick-add "Quick workout", Workouts →
  "Start Empty Workout", template and circuit "Start", the planned-workout preview and day-detail "Start /
  Resume workout" and the dashboard "Next workout" start button (its "View" stays). A session that was
  started on the phone and synced still shows the live workout view and banner, so it can be finished.

## Sync audit follow-ups (2026-10-27)

Shipped: pull on resume / tab focus (`SyncService.syncOnResume`), a follow-up
pull for a hint that lands mid-pull, a push ~2 s after the last local write, and
`20261027140000_v39_planner_sync_wiring.sql` (tombstone + realtime for the seven
v39 planner tables). `test/sync/supabase_sync_parity_test.dart` now fails when a
synced table lacks RLS, the clock, a tombstone trigger or realtime;
`test/sync/workout_two_device_test.dart` covers session → exercises → sets,
templates and a delete across two databases.

`supabase migration list` on 2026-10-27: everything through
`20261021115928` is applied on the remote. Pending `supabase db push` (needed
before the web launch and the phone release): `20261027120000_food_catalogue`,
`20261027130000_user_preferences`, `20261027140000_v39_planner_sync_wiring`.

Still open, in rough order of impact:

- **Custom exercises lose their muscles and aliases on the other device.**
  `exercise_muscles` / `exercise_aliases` have no sync columns or Supabase
  table, so recovery, volume, adaptation and achievements ignore a custom
  exercise's sets on the second device. Same for `food_micros` of custom foods.
  Needs drift v54 plus a migration.
- **Unique-key collisions between devices** (`daily_summaries`,
  `carb_cycle_plans`, `gym_equipment`, `exercise_progressions`). A push `23505`
  is acknowledged and the op dropped, so the row is lost; on pull the apply
  fails and the table cursor sticks.
- **Catalogue skew.** A stock exercise slug unknown to the receiving device
  resolves to NULL and the pull stalls on it. Deploy web and phone together
  when `exercises.json` changes.
- No multi-tab handling (a second tab runs its own `SyncService` and 58
  realtime channels); no check that drift picked a multi-tab-safe storage mode.
- Ops are quarantined after ~20 minutes offline (8 attempts) and never retried
  automatically; `_pushParentIfUnsynced` re-upserts the whole parent chain on
  every child push (3–4x traffic, can overwrite a newer remote parent edit).
- `Achievements` has sync scaffolding but no registry entry or Supabase table.
- `docs/DATA_TRUTH_TABLE.md` still lists profile, units and supplements as
  local only.
- The `web/index.html` splash colours and the Android widget palettes mirror
  Classic Blue only; they do not follow the colour themes (nine since
  2026-10-27).

## Interaction with other tracks

- `.planning/ROADMAP.md` Phase 25 (sync/privacy/export hardening): W3 covers `user_preferences` and the
  natural-key fixes early; mark them verified there. `food_catalogue` is shared data and, like
  `product_catalogue`, is excluded from the per-user wipe.
- Phase 24 (XP ledger): make it a synced table, or XP will differ between phone and web.
- `docs/ui-rework/ROADMAP.md`: Phase 9 owns the `AppColors` shim — web code uses `context.hx` only and keeps
  edits to `app.dart` small. Phase 7 owns `active_exercise_card.dart` — the web track does not touch it.

Manual setup outside the code (Cloudflare, Supabase Auth, Google OAuth): [SETUP.md](SETUP.md).
