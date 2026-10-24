# Herculex for Apple Watch

The iPhone app embeds a native SwiftUI watchOS 10+ app and a WidgetKit extension.
Wear OS remains under `android/wear`; Apple uses the same Flutter serializers,
repositories and version 2 workout contract, with Watch Connectivity as transport.

## Build and signing

On a Mac with Flutter, CocoaPods and Xcode supporting watchOS 10 or newer:

```sh
flutter pub get
cd ios && pod install && cd ..
open ios/Runner.xcworkspace
```

Select the same development team for **Runner**, **HerculexWatch** and
**HerculexWatchWidgets**. Provision these identifiers:

| Target | Bundle identifier | Capabilities |
| --- | --- | --- |
| Runner | `com.ams.herculex` | HealthKit |
| HerculexWatch | `com.ams.herculex.watchkitapp` | HealthKit, Workout processing, App Group |
| HerculexWatchWidgets | `com.ams.herculex.watchkitapp.widgets` | App Group |

The watch and widgets share `group.com.ams.herculex.watch`. The iPhone does not
need access to that container. Watch/widget build versions read Flutter's
`Generated.xcconfig`, so they match the containing app. No Flutter runtime or
CocoaPods dependencies are linked into the watch targets.

Run the **HerculexWatch** scheme using a paired iPhone/Watch destination. The
**Runner** scheme builds and embeds the watch app too. The watch resource phase
uses macOS `sips` to convert the existing exercise illustrations to small PNGs
inside the built bundle; it never rewrites source illustrations.

```sh
# Unsigned simulator build, then native protocol tests (choose an installed iPhone).
xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner \
  -destination 'platform=iOS Simulator,name=iPhone 16' test
```

## Features and Apple adaptations

| Area | Watch implementation |
| --- | --- |
| Workouts | Today's schedule, folders, templates, free workouts, add/replace/remove exercises, equipment options, series, completion, routine saving, finish/discard and summary |
| Set logging | Crown inputs for weight, reps, time, distance and calories; RPE, warmups, advanced types, mini-sets, extra reps, bodyweight, chains and accessories |
| Training feedback | Persistent exercise/rest timers, heart rate, energy, weight/rep/estimated-1RM records, achievement messages |
| Nutrition | Macro/water goals, trends, suggested/recent foods, recipes, portion multiplier, meal selection, manual macros/water and Rambler |
| Fasting | Start/stop, local elapsed time, goal, next scheduled fast, last duration and bundled stage descriptions |
| Readiness | Phone-computed CNS readiness and weekly muscle volume |
| Watch surfaces | Eleven WidgetKit complications/widgets, Smart Stack and deep links |
| Music | Full-screen system `NowPlayingView` for the current iPhone/watch audio source |

Rambler uses watchOS system text input/dictation. Dictation availability depends
on the watch's language and system settings. The saved text is sent to the
existing phone analyzer; AI processing waits for iPhone and internet access.
The watch does not have its own login or direct cloud connection.

## Persistence and synchronization

- `WatchShared` contains the JSON protocol, atomic disk store and `WCSession`
  transport used by both apps. Payloads travel as JSON strings/files so JSON
  nulls and opaque metadata never violate WC property-list restrictions.
- A persisted outbox is written before delivery. Live messages improve latency;
  background user-info/file transfers provide retries. Business acknowledgements
  are separate from transport receipts. Large snapshots use file transfers and
  carry timestamps so a late old file cannot overwrite a newer cache.
- The iPhone retains received events while Flutter is unavailable. It applies
  them when the app/engine and repositories are ready. Until that happens, the
  watch continues to show pending changes rather than claiming synchronization.
- Native delivery is serialized. Nutrition commands are acknowledged through
  the existing `markWatch…CommandApplied` methods. Apple workouts use the awaited
  `onAppleWatchWorkoutEvent` callback, including a self-contained final snapshot.
- Database v52 adds **local-only** `processed_watch_commands`,
  `apple_watch_sessions` and `watch_health_exports`. Their explicit migration DDL
  is shared by fresh installs and upgrades; no cloud triggers reference them.
  Command receipts and business rows commit in one Drift transaction.
- Sets retain IDs, fractional RPE, opaque metadata and independent field stamps.
  Completed/discarded sessions have durable terminal records. A separate offline
  watch workout is deferred while another phone workout is active and imported
  into history on completion, without ending the phone's workout.
- Nutrition commands include `createdAtEpochMs` and `localDate`. Offline entries
  are attributed to their original local day. Older Android payloads remain valid.
- Phone rest alerts are suppressed only after the watch persists the timer and
  successfully schedules its alert with notification authorization. Otherwise the
  phone retains its fallback. Countdown values derive from absolute timestamps.

## Apple Health ownership

The watch uses `HKWorkoutSession` and `HKLiveWorkoutBuilder` for live heart rate,
energy and background execution. Denied Health access leaves manual logging
available. Watch-origin workouts can be saved offline. Phone-origin workouts
require confirmation that the watch owns the export before the watch saves.

The first export reservation in SQLite wins. Automatic finish and manual phone
export consult the same ownership record. A watch-owned workout is never also
written by the phone. HealthKit saves use a stable synchronization identifier,
and confirmation includes the HealthKit UUID. Completed live sessions retain a
recovery snapshot until their save confirmation has been queued durably.

## Verification

```sh
flutter test test/watch_command_inbox_test.dart \
  test/apple_watch_workout_sync_test.dart test/apple_watch_health_export_test.dart \
  test/wear_sync_contract_test.dart test/wear_watch_event_queue_test.dart \
  test/wear_workout_sync_service_test.dart test/health_service_read_state_test.dart
flutter test test/migration_test.dart
```

`test/fixtures/watch_sync_v2.json` is consumed by Dart and by native
`RunnerTests/WatchProtocolTests.swift`. Automated cases cover duplicate/retried
commands, rollback, crossed field versions, opaque metadata, offline calendar
days, final-snapshot import, terminal replay, unrelated active workouts and
Health export ownership.

Before release, run these checks on a physical paired iPhone/Apple Watch:

1. Install from the iPhone package; perform initial sync and inspect all screens,
   folders, artwork, small/large displays, Crown focus and VoiceOver.
2. Start, edit and finish from each device. Cross-edit weight/reps, change exercise
   lists and verify the same set identities and actual values on both devices.
3. Disconnect, record a workout/food/water/fast across midnight, restart the apps,
   reconnect, and confirm that each write occurs once on the correct day.
4. Lock the screens during exercise/rest timers. Check notification denial and
   phone fallback, cancel/replace a timer, and check that old alerts do not fire.
5. Grant/deny Health permissions. Confirm live readings, Activity rings, one
   HealthKit workout, finish from phone, discard, crash recovery and a second
   workout started before the first one's Health confirmation returns.
6. Add all complication families and Smart Stack widgets. Verify deep links,
   cached-data labels, midnight rollover, fasting elapsed time and music control.

Windows verification cannot compile Apple SDK code, run native XCTest, validate
signing, or confirm physical-device/background behavior. Swift syntax and Xcode
project structure checks are useful preflight checks, not a substitute for those
Mac/device release checks. App Store submission is a separate step.

### Windows verification recorded 2026-10-22

- All **97** targeted Flutter tests in the command above passed, including the
  migration suite and existing Wear OS synchronization regressions.
- All **12** Swift source files passed a Swift grammar parse. Xcode target source
  membership, watch SDK/minimum version, inherited build versions, entitlements,
  property lists, icon resources and the project file were checked structurally.
- Targeted Dart analysis reported no code errors and one existing informational
  getter/setter lint. The environment's `custom_lint` analyzer plugin failed to
  start, so its additional checks were unavailable.
- Apple SDK compilation, native XCTest and the physical-device checklist above
  remain unverified until run on macOS with paired Apple hardware.
