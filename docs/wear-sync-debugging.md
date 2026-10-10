# Herculex Wear Sync Debugging

Last updated: August 8, 2026

## Structured Log Shape

Use the `WearSync` prefix on phone and watch:

`entity=<active_workout|fasting> revision=<n> origin=<phone|watch> entityId=<id> path=<path> delivery=<message|data|flutter> apply=<accepted|ignored|failed>`

When a snapshot is accepted but a value on screen did not change, the envelope line above is not enough. The watch also logs one line per set field where the phone's value and its own differ, saying which side won:

`set=<wireId> field=<weight|reps|completion> remote=<revision>/<origin> local=<revision>/<origin> kept=<remote|local>`

`kept=local` with a larger `local` revision is the "last change wins" rule working. If it is the *older* edit that was kept, compare the two revisions: they are wall-clock milliseconds, and each device raises its own counter to every revision it receives, so a gap of more than a few seconds points at a device clock that is wrong. Revisions more than 10 minutes ahead of a device's own clock are clamped.

For user-visible bugs, capture:

| Case | Direction | Transport | Expected result |
| --- | --- | --- | --- |
| Phone-started workout | phone -> watch | MessageClient then DataClient | Message applies first; durable duplicate is ignored by revision. |
| Watch-started workout | watch -> phone | MessageClient then DataClient | Phone creates/adopts one active session and alerts once. |
| Phone edit while connected | phone -> watch | MessageClient fast path | Watch updates set/exercise state without restarting ongoing notification. |
| Phone edit while disconnected | phone -> watch | DataClient durable state | Latest snapshot applies after reconnect. |
| Watch edit while connected | watch -> phone | MessageClient fast path | Phone Drift set at the same position is updated. |
| Watch edit while disconnected | watch -> phone | DataClient durable state | Latest watch snapshot applies after reconnect. |
| Finish/discard | both directions | MessageClient + durable clear | Active state and ongoing notification are removed. |
| Phone fasting start/stop | phone -> watch | DataClient durable fasting snapshot | Watch timer derives elapsed locally from `startedAtEpochMs`. |
| Watch fasting start/stop | watch -> phone | FIFO command with `commandId` | Phone applies command, ACKs it, then sends authoritative snapshot. |
| Samsung rotating bezel | local watch UI | Rotary focus owner | Only the selected `WEIGHT` or `REPS` target changes. |

## Rest Timer ("IT'S GO TIME")

The phone owns the rest countdown. The watch mirrors it and arms an alarm that buzzes at the end.

| Hop | Path | Payload |
| --- | --- | --- |
| phone → watch, fast | `MessageClient` `/herculex/workout/start_rest_timer` | `{endsAtEpochMs, totalSeconds, label, showOnWatch, alert, rev}` |
| phone → watch, durable | `DataClient` `/herculex/state/rest_timer` | `rest_json` = the same payload |
| watch → phone | `MessageClient` `/herculex/workout/rest_timer_ack` | `{endsAtEpochMs, rev, armed, reason}` |

`endsAtEpochMs: 0` means skipped or cancelled. `rev` orders the messages, so a late start cannot undo a later skip; the same `rev` arriving as message and as data item is applied once.

**The phone keeps its own end-of-rest notification until the watch acks with `armed: true` for the rest that is running now.** Sending the message is not proof the watch will buzz. `armed` is true only when an exact alarm is set and notifications are allowed. `reason` says what happened:

| `reason` | `armed` | Meaning |
| --- | --- | --- |
| `exact` | true | Exact alarm set. |
| `inexact` | false | No exact-alarm access; the alarm can be up to ~75% of the rest late, so the phone keeps its own. |
| `notifications_denied` | false | Notifications (or the "Rest finished" channel) are off on the watch. |
| `alarm_failed` | false | `AlarmManager` refused. |

Not acked (watch out of range, old watch APK, phone app not running when the ack arrives): the phone alerts as if there were no watch. Worst case is two alerts, never none.

Watch logs: `adb logcat -s SyncService RestTimerStore WearSync`. Look for `rest timer via message|data: reason=… armed=… rev=…`.

Checks on the watch after a rest starts:

- `adb shell dumpsys alarm | grep -B3 -A12 com.ams.herculex` — a pending `RTC_WAKEUP` alarm at `endsAt`.
- `adb shell cmd appops get com.ams.herculex SCHEDULE_EXACT_ALARM` — and `dumpsys package com.ams.herculex | grep EXACT` for `USE_EXACT_ALARM`.
- `adb shell dumpsys notification --noredact | grep -A15 rest_timer_go_time_v2` — present for 30 s after a missed buzz.
- `adb shell dumpsys vibrator_manager` — a recent entry with status `IGNORED_BACKGROUND` means a background vibration was dropped.
- `adb shell dumpsys package com.ams.herculex | grep lastUpdateTime` — compare with when you last installed the wear APK; `flutter run` does not update it.

## Baseline Notes

- Build and install both APKs from the same source state before testing. `flutter run` does not refresh the wear APK.
- DataClient is the durable latest-state channel; MessageClient is only a fast hint or command transport.
- Repeated snapshots with the same `entityId`, `origin`, `revision`, and `updatedAtEpochMs` should log `apply=ignored`.
- Legacy payloads without revision remain accepted for one release window for phone/watch APK drift.
- Ongoing workout notifications should appear once on start, stay silent during updates, and disappear on end.
