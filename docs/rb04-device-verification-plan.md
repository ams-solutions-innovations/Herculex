# RB-04 Database FK Device Verification Plan

Date: 2026-08-13

## Status

Planned, not yet performed.

RB-04 code remediation is already implemented and covered by synthetic tests:
the orphan repair migration runs from `from < 23`, all declared Drift foreign
keys are enforced through `beforeOpen`, and the current app schema is v25.

This document covers the remaining blocker from `BLOCKERS.md`: a real
device-based upgrade and UI delete-path verification pass. It is intentionally
manual because the missing evidence is about the shape of an actual on-device
database and the app's production UI wiring, not about the repository methods
or migration fixtures in isolation.

## Goal

Prove that an existing pre-RB-04 install can upgrade to the current build
without boot-looping, without residual SQLite FK violations, and without any
FK-sensitive UI delete path throwing or leaving dangling data.

## Scope

In scope:

- Android phone device or emulator using the real app database.
- Upgrade from a pre-RB-04 build, meaning a build whose local schema is before
  v23 or otherwise predates `PRAGMA foreign_keys = ON` in
  `lib/data/local/database.dart`.
- Current build from this worktree, currently `AppDatabase.schemaVersion == 25`.
- UI paths backed by the RB-04 repositories:
  - workout session delete;
  - active workout exercise removal;
  - active workout set delete;
  - program delete;
  - program day delete;
  - rotation delete;
  - workout template delete;
  - template folder delete;
  - exercise removal from template;
  - gym delete;
  - custom food delete, both unreferenced and referenced by history;
  - optional recipe/custom-food recipe reference check if the build exposes it
    naturally through the UI.

Out of scope:

- Reworking FK code. Failures from this pass should become bug fixes, not
  changes to this checklist.
- RB-05 nutrition history correctness, except where it affects the custom food
  delete behavior that used to be part of RB-04's RESTRICT risk surface.
- Cloud sync, Wear sync, Supabase RLS, and auth policy verification.

## Prerequisites

Use one dedicated test device/emulator and one disposable local app install.
Do not use a personal production database.

Prepare:

- A pre-RB-04 APK or Flutter run target. Preferred target: a commit/build from
  before the v23 FK repair migration landed.
- The current APK or Flutter run target from this worktree.
- `adb` access to the test device.
- A way to inspect the app database after upgrade. On debug builds this is
  usually `adb shell run-as <applicationId>`, then copy or inspect the database
  under the app's `databases` directory. Discover the actual package/database
  names during the pass instead of assuming them.
- A clean evidence folder, for example:

```powershell
New-Item -ItemType Directory -Force .verification\rb04-device
```

## Evidence To Capture

Save these artifacts under `.verification/rb04-device/` or paste their results
into the "Results" section below:

- pre-upgrade app version/commit and current app version/commit;
- device model/API level;
- pre-upgrade database copy or at least `PRAGMA user_version`;
- upgrade logcat excerpt covering first launch after installing the current
  build;
- post-upgrade `PRAGMA user_version`;
- post-upgrade `PRAGMA foreign_keys`;
- post-upgrade `PRAGMA foreign_key_check`;
- after-delete-path `PRAGMA foreign_key_check`;
- notes/screenshots for every UI path exercised.

## Procedure

### 1. Install and seed the pre-RB-04 build

1. Uninstall the app from the device.
2. Install/run the pre-RB-04 build.
3. Use the UI long enough to create relational data:
   - create or complete a workout with at least two exercises and multiple
     sets;
   - assign a gym to a workout or machine setting if the UI exposes that path;
   - create a workout template in a folder, with at least one exercise and
     multiple template sets;
   - create a training program/block that references a template and generates
     scheduled workouts;
   - create an exercise rotation if the UI path is available;
   - create two custom foods: one never logged, one logged in today's diary;
   - create a recipe using a custom food if the UI path is available.
4. Close the app.
5. Record the installed build identity and pre-upgrade database version.

Suggested DB discovery:

```powershell
adb shell pm list packages | Select-String herculex
adb shell run-as <package> ls databases
adb shell run-as <package> sqlite3 databases/<db-file> "PRAGMA user_version;"
```

If the device image does not include `sqlite3`, copy the database out through
`run-as` and inspect it locally with any SQLite client.

### 2. Upgrade to the current build

1. Install/run the current build over the existing install. Do not uninstall.
2. Capture logcat during first launch.
3. Wait until the app reaches its first usable screen.
4. Check the database:

```sql
PRAGMA user_version;
PRAGMA foreign_keys;
PRAGMA foreign_key_check;
```

Expected:

- `user_version` is the current schema version, currently `25`.
- `foreign_keys` returns `1`.
- `foreign_key_check` returns zero rows.
- No migration error, boot loop, or app crash appears in logcat.

### 3. Exercise FK-sensitive UI delete paths

After each group, keep the app open long enough for the UI stream to refresh,
then run `PRAGMA foreign_key_check`.

Workout paths:

- Delete one set from an active workout exercise.
- Remove one exercise from an active workout.
- Delete a completed workout session from history.

Program paths:

- Delete one program day from a program/block.
- Delete a full program/block with generated scheduled workouts.
- Delete one rotation, if the rotation UI is present.

Template paths:

- Remove one exercise from a workout template.
- Delete a workout template that has exercises and sets.
- Delete a workout folder containing at least one template.

Gym path:

- Delete a gym that has been assigned to a session or machine setting.

Nutrition paths:

- Delete the unreferenced custom food. Expected: hidden/removed from catalogue.
- Delete the custom food that has diary history. Current RB-05 behavior is soft
  delete, so expected behavior is: food disappears from catalogue-facing custom
  food search, historical diary totals remain readable, and
  `PRAGMA foreign_key_check` stays empty.
- If a recipe was created with a custom food, delete/soft-delete the food and
  verify the recipe/history screen still opens without a DB exception.

Expected for every path:

- No SQLite constraint exception in UI or logcat.
- The user-facing list updates coherently.
- `PRAGMA foreign_key_check` remains empty.

### 4. Final database and app sanity pass

1. Force stop and reopen the app.
2. Recheck:

```sql
PRAGMA foreign_keys;
PRAGMA foreign_key_check;
```

3. Navigate through Dashboard, Workouts, Programs/Blocks, Templates, Gyms, and
   Nutrition. The app should not crash while reading rows affected by the
   delete pass.

## Acceptance Criteria

RB-04 can be closed only when all of the following are true:

- Upgrade from pre-RB-04 to current build succeeds in place.
- Current app opens with `PRAGMA foreign_keys = 1`.
- `PRAGMA foreign_key_check` is empty immediately after upgrade.
- Every FK-sensitive UI delete path above either passes or is explicitly
  marked unavailable because the current UI has no path for it.
- `PRAGMA foreign_key_check` is still empty after the delete-path pass.
- No SQLite FK exceptions, app boot loops, or data-reading crashes are present
  in captured logs.
- Any failures found have follow-up fixes or blocker entries before RB-04 is
  marked closed.

## Results

Not run yet.

When run, fill this in:

| Item | Result | Evidence |
| --- | --- | --- |
| Device/builds recorded | Pending |  |
| Pre-upgrade DB captured/versioned | Pending |  |
| Upgrade first launch | Pending |  |
| `PRAGMA foreign_keys` after upgrade | Pending |  |
| `PRAGMA foreign_key_check` after upgrade | Pending |  |
| Workout delete paths | Pending |  |
| Program/rotation delete paths | Pending |  |
| Template/folder delete paths | Pending |  |
| Gym delete path | Pending |  |
| Nutrition delete paths | Pending |  |
| Final reopen + FK check | Pending |  |

## Closeout Edits After Passing

After this pass succeeds:

- Update this document's Status and Results sections.
- Update `docs/fk-enforcement-remediation-progress.md` with a final manual
  verification entry.
- Remove RB-04 from `BLOCKERS.md`.
- Update `TASKS.md` so RB-04 no longer appears under "Everything else".
- If the audit report remains in active use, change its RB-04 callout from
  "pending one manual device pass" to closed with a link here.
