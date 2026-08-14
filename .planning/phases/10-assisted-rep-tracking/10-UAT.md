---
status: not_started
phase: 10-assisted-rep-tracking
source: [10-01-PLAN.md, 10-02-PLAN.md, 10-03-PLAN.md, 10-04-PLAN.md, 10-05-PLAN.md]
---

## Device Validation Matrix

Every row is run on real hardware. Automated tests cannot cover transport, battery or sensor availability.

| # | Configuration | Covers |
|---|---|---|
| 1 | Watch + phone, both nearby, BT connected | happy path |
| 2 | Watch only, phone in a locker (out of range whole set) | buffer + flush on reconnect |
| 3 | Phone only, pocket placement, watch not worn | phone source, placement gate |
| 4 | Phone only, placement never selected | source must refuse to start |
| 5 | Watch, airplane mode toggled mid-set | disconnect mid-capture |
| 6 | Watch at < 15 % battery | battery refusal |
| 7 | Set abandoned mid-tracking (app backgrounded, workout discarded) | listener teardown, no orphan state |
| 8 | Feature never consented | zero UI surface anywhere |

## Tests

### 1. Consent Is the Only Door
expected: With consent never granted, no rep-tracking UI appears anywhere in an active workout, including on eligible exercises. The only entry point is Profile → the consent screen. Enabling per-exercise tracking is impossible until consent is granted.
result:
severity:

### 2. Tracking Never Starts Itself
expected: With consent granted and pull-ups enabled, starting a set shows a "Start tracking" control but no live count and no sensor activity. Capture begins only after the tap.
result:
severity:

### 3. Live Count on the Wrist
expected: During a tracked pull-up set the watch shows a rising provisional count with haptic feedback per rep, labelled provisional. Perform exactly 8 reps; the watch count is within ±1.
result:
severity:

### 4. The Review Sheet Proposes, Never Decides
expected: Ending the set opens the review sheet with an editable rep field pre-filled with the detected count. Change it to a different number and save. The logged set holds the **edited** number. The set is not written until Save is tapped.
result:
severity:

### 5. Dismissal Writes Nothing
expected: Start tracking, do reps, end the set, then dismiss the review sheet without saving. The set remains incomplete, its reps unchanged, and no calibration progress is recorded.
result:
severity:

### 6. Watch Out of Range for a Whole Set (matrix row 2)
expected: Leave the phone in a locker. Track a full set on the watch. On return to range, the buffered samples flush and the review sheet offers a detected count. If they never arrive, the sheet opens in manual state with the reason stated — it does **not** fall back to the provisional count and does not show "0 reps".
result:
severity:

### 7. Disconnect Mid-Set (matrix row 5)
expected: Toggle airplane mode mid-set. Confidence drops and the sheet reports missed coverage rather than silently returning a low count. If coverage is too poor, it shows count-only or manual with the reason.
result:
severity:

### 8. Phone Placement Is Required (matrix rows 3 and 4)
expected: With source set to phone and no placement chosen, tracking cannot start and the consent screen's primary action stays disabled. After selecting "pocket", a pocketed-phone set counts within ±1 of 8 real reps.
result:
severity:

### 9. Battery Gate (matrix row 6)
expected: Below 15 % battery on the capturing device, starting tracking is refused with a plain reason. Manual set entry still works normally.
result:
severity:

### 10. Walking Does Not Count Reps
expected: With tracking started, walk around the gym for 60 seconds without doing a rep. The count stays at 0 on both the watch and the review sheet.
result:
severity:

### 11. No RPE Before Calibration
expected: On the first tracked sets the review sheet's RPE field is empty with no suggestion, and the expander shows calibration progress ("3 of 10 sets"). After 10 confirmed sets across at least 3 separate sessions with consistently entered RPE, a suggestion appears — pre-filled and editable.
result:
severity:

### 12. Placement Change Resets Calibration
expected: Once calibrated for pocket, switch the phone to an armband. The next set shows count-only with "calibrating for this placement", not an RPE suggestion. Switching back to pocket restores the calibrated state.
result:
severity:

### 13. Teardown (matrix row 7)
expected: Start tracking, background the app, then discard the workout. `adb shell dumpsys sensorservice` shows no lingering registration for the app. Reopening the app shows no stuck tracker state.
result:
severity:

### 14. Nothing Leaves the Device
expected: With tracking used for several sets, inspect the Supabase project — no motion, calibration or observation rows appear. Revoking consent from the consent screen removes all stored per-exercise prefs and observations locally.
result:
severity:

### 15. Feature Off Is Truly Off (matrix row 8)
expected: On a fresh install with consent never granted, the active workout screen for pull-ups is identical to the pre-phase build, and no accelerometer registration occurs at any point.
result:
severity:
