---
phase: "08"
plan: "08-01"
subsystem: android-notifications
tags: [now-bar, live-update, android-16, notifications, kotlin]
requires:
  - OngoingWorkoutSurfaceSnapshot (native parse layer, unchanged)
  - LiveUpdatesCapability.isPlatformSupported
provides:
  - Promotable Android 16 Live Update notification on API 36+
  - Non-reflective hasPromotableCharacteristics / FLAG_PROMOTED_ONGOING diagnostics
  - Feedback notification on its own id, no longer competing for id 1
affects:
  - android/app/src/main/kotlin/com/ams/herculex/nowbar/
  - android/app/build.gradle.kts
tech-stack:
  added:
    - android-36.1 compile platform (Android 16 QPR1)
  patterns:
    - Platform Notification.Builder on API 36+, NotificationCompat.Builder below
key-files:
  created: []
  modified:
    - android/app/src/main/kotlin/com/ams/herculex/nowbar/OngoingWorkoutSurfaceRenderer.kt
    - android/app/src/main/kotlin/com/ams/herculex/nowbar/OngoingWorkoutSurfaceFeedback.kt
    - android/app/build.gradle.kts
key-decisions:
  - Pinned the app module to compileSdkVersion("android-36.1") because the promotion
    setter does not exist in platform 36.0
  - Used the real shipped setter name setRequestPromotedOngoing(true), not the
    plan's requestPromotedOngoing(true), which is a pre-release name that never shipped
  - shortCriticalText is derived from the collapsed subtitle's set counter ("3/5"),
    falling back to the collapsed value
  - ProgressStyle uses one unit-length segment per set with progress = current set index
requirements-completed:
  - NOWBAR-01
duration: 41 min
completed: 2026-08-04
---

# Phase 08 Plan 01: Android 16 Live Update Renderer Summary

Replaced the reflective promoted-ongoing hack in the native workout surface renderer with
genuine Android 16 Live Update API calls, so `hasPromotableCharacteristics()` can report
true and One UI can promote the ongoing workout into the Samsung Now Bar.

**Tasks:** 8 | **Files modified:** 3 | **Commits:** 1 (`516428c`)

## What Was Built

`AndroidOngoingWorkoutSurfaceRenderer.show()` now branches on
`capability.isPlatformSupported` into two builder paths:

- **API 36+ (`buildPromotedNotification`)** — platform `Notification.Builder`, because the
  bundled androidx version exposes none of the promoted-ongoing setters (this was the
  original reason for the reflection). Calls `setRequestPromotedOngoing(true)`,
  `setStyle(Notification.ProgressStyle())` with one unit-length segment per set and
  progress at the current set index, `setShortCriticalText(...)`, `setColorized(true)` +
  `setColor(0xFF0A84FF)` (the app accent from `lib/theme/app_theme.dart`), plus the
  retained `setOngoing`/`setWhen`/`setUsesChronometer`/`CATEGORY_WORKOUT`/
  `VISIBILITY_PRIVATE`/`setSmallIcon`/`setContentIntent` and the snapshot's actions in
  order. `setLocalOnly` and `setSilent` are deliberately absent — both can disqualify a
  notification from promotion. `setOnlyAlertOnce(true)` is kept.
- **Below API 36 (`buildCompatNotification`)** — the previous `NotificationCompat.Builder`
  + `BigTextStyle` path verbatim, minus the deleted extras write. Both branches post the
  same `NOTIFICATION_ID` on the same `CHANNEL_ID`; `clear()` is unchanged.

`shortCriticalText` is parsed out of `collapsed.subtitle`, which the Dart snapshot builder
populates as `"Set 3/5"`, yielding `"3/5"` — short enough for the Now Bar chip. It falls
back to the bare set index, then to `collapsed.value` (`"82.5 kg x 8"`).

Deleted: `requestPromotedOngoingIfAvailable()`, the reflective `isRequestPromotedOngoing()`,
and the `"android.requestPromotedOngoing"` constant.
`hasPromotableCharacteristicsIfAvailable()` and `activeNotificationIsPromotedOngoing()` are
now direct `Notification.hasPromotableCharacteristics()` and
`Notification.FLAG_PROMOTED_ONGOING` reads guarded by `SDK_INT >= 36`, with no
`runCatching` around them — a false value now means "not promotable", never "the lookup
blew up".

`lastDiagnostics` gained `"shortCriticalText"` and reports `"style"` as `"ProgressStyle"`
on the promoted branch, `"BigTextStyle"` below. Every pre-existing diagnostics key is
retained, so the Dart parser and `test/ongoing_workout_surface_bridge_test.dart` still
pass. Both `Log.i(... event=posted ...)` and `Log.d` lines keep their documented keys and
additionally emit `style=` and `shortCriticalText=`.

`OngoingWorkoutSurfaceFeedback` no longer writes the promoted extras and posts to id
`4202` instead of `1`, so it can no longer overwrite the Live Update.

## Deviations from Plan

**[Rule 1 — plan referenced a non-existent API] `requestPromotedOngoing` does not exist**
Found during: Task 2 verification (`:app:compileDebugKotlin`).
Issue: the plan (and the phase CONTEXT) specify `requestPromotedOngoing(true)`. That is a
pre-release Android 16 beta name. `javap` against the installed platforms shows the shipped
setter is `Notification.Builder.setRequestPromotedOngoing(boolean)`, and it is absent from
`android-36` entirely — it first appears in `android-36.1` (Android 16 QPR1). Platform 36.0
has `FLAG_PROMOTED_ONGOING`, `hasPromotableCharacteristics()` and `setShortCriticalText()`,
but no promotion-request setter.
Fix: used the real setter name, and pinned the app module with
`compileSdkVersion("android-36.1")` instead of inheriting `flutter.compileSdkVersion` (36).
`minSdk`/`targetSdk` are untouched; this only changes what the compiler links against.
Files modified: `OngoingWorkoutSurfaceRenderer.kt`, `android/app/build.gradle.kts`.
Verification: `:app:compileDebugKotlin` re-run with `--rerun-tasks` — BUILD SUCCESSFUL.
Commit: `516428c`.

The alternative — staying on platform 36 and calling
`setFlag(Notification.FLAG_PROMOTED_ONGOING, true)` — was rejected because it relies on an
undocumented equivalence rather than the named API, which is exactly the class of
indirection this plan set out to remove.

**Total deviations:** 1 auto-fixed (1× Rule 1). **Impact:** the plan's success criterion
"contains a literal `requestPromotedOngoing(true)` call" is met in substance by
`setRequestPromotedOngoing(true)`; the literal string does not and cannot appear.

## Verification Results

| Check | Result |
|-------|--------|
| `flutter test test/ongoing_workout_surface_bridge_test.dart test/now_bar_native_action_contract_test.dart test/ongoing_workout_surface_snapshot_test.dart` | PASS — 16/16 |
| `.\gradlew.bat :app:compileDebugKotlin` (JBR JAVA_HOME) | PASS — BUILD SUCCESSFUL, task executed under `--rerun-tasks` |
| `grep -r "android.requestPromotedOngoing" android/` | PASS — no matches |
| `setLocalOnly`/`setSilent` absent from API 36+ branch | PASS |
| Feedback notification id != 1 | PASS — 4202 |

Not verifiable here: the on-device criterion
(`adb logcat -s WorkoutSurfaceRenderer` showing `event=posted ... promotable=true` on a
Samsung Android 16 device). That requires physical hardware and is the phase's headline
outcome — it must be checked during UAT.

## Issues Encountered

The repository working tree carries a large volume of uncommitted prior-phase work
(the whole `android/.../nowbar/` package, the Dart surface layer, and its tests are all
untracked). This commit stages only the two files this plan modified plus the build file,
so `HEAD` alone does not compile — the surrounding package exists only in the working tree.
That is a pre-existing condition, not something this plan introduced, and committing the
rest would misattribute earlier work. Worth resolving before the phase is shipped.

## Next Phase Readiness

Ready for 08-02, which makes the native renderer the sole publisher of notification id 1
on API 36+ so this promotable notification is no longer overwritten once per second.
