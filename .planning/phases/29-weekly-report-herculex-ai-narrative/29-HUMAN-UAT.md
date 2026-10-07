---
status: partial
phase: 29-weekly-report-herculex-ai-narrative
source: [29-VERIFICATION.md]
started: 2026-10-04
updated: 2026-10-04
---

## Current Test

[awaiting human testing on a physical Android device, signed-in account]

## Tests

### 1. Sunday notification
expected: With "Weekly report" on and the time set ~2 min ahead on a Sunday, "Your weekly report is ready / See how your week went." posts with no numbers in it.
result: [pending]

### 2. Tap from foreground and background
expected: Opens the correct week (late taps Mon-Sat open the week that just ended). Measured cards render at once; the Herculex AI card goes loading -> summary + 2-3 suggestions; relationships read "tended to go with", never "because".
result: [pending]

### 3. Cold-start tap
expected: Force-stop the app, tap the notification: the report route opens and generation happens once (assumption A10, never device-tested).
result: [pending]

### 4. Stability and offline
expected: Re-opening a week and editing a food entry leave the report unchanged, with no new narrative call. Airplane mode on a fresh week shows "Narrative pending"; Retry works after reconnecting.
result: [pending]

### 5. TDEE shift card
expected: "Update my target to X kcal" / "Keep current target"; Update changes only the saved target, then the card is read-only; past weeks show the outcome read-only.
result: [pending]

### 6. Sync round trip
expected: A weekly_reports row appears remotely, pending_sync_ops drains with no PGRST204 quarantine, and the weekly_report quota counter moves. (Migration and function are already live.)
result: [pending]

## Summary

total: 6
passed: 0
issues: 0
pending: 6
skipped: 0
blocked: 0

## Gaps
