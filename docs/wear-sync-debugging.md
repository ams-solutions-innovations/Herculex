# Herculex Wear Sync Debugging

Last updated: August 8, 2026

## Structured Log Shape

Use the `WearSync` prefix on phone and watch:

`entity=<active_workout|fasting> revision=<n> origin=<phone|watch> entityId=<id> path=<path> delivery=<message|data|flutter> apply=<accepted|ignored|failed>`

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

## Baseline Notes

- Build and install both APKs from the same source state before testing. `flutter run` does not refresh the wear APK.
- DataClient is the durable latest-state channel; MessageClient is only a fast hint or command transport.
- Repeated snapshots with the same `entityId`, `origin`, `revision`, and `updatedAtEpochMs` should log `apply=ignored`.
- Legacy payloads without revision remain accepted for one release window for phone/watch APK drift.
- Ongoing workout notifications should appear once on start, stay silent during updates, and disappear on end.
