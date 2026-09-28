---
status: partial
phase: 28-adaptive-tdee-activity-calibration
source: [28-VERIFICATION.md]
started: 2026-09-28T00:00:00Z
updated: 2026-09-28T00:00:00Z
---

## Current Test

[testing paused: tests 4-6 need a running app / real device, not available right now]

## Tests

### 1. Supabase migration is live on ldzgyzigvbwofbswitrv, after 0015 and 0016
expected: 12 columns (id, user_id, date_iso, estimated_at, method, confidence, window_days, kcal, observed_qualified, inputs_json, updated_at, deleted_at); four `tdee_estimates_{select,insert,update,delete}_own` policies; triggers `t_set_updated_at_tdee_estimates` and `t_record_tombstone_tdee_estimates`; index `tdee_estimates_user_updated_idx`; a recalibration row syncs and `pending_sync_ops` drains without PGRST204.
note: the earlier "Pushed" report was unverified and turned out to be wrong — `supabase migration list` on 2026-09-28 showed `20260928000000` still pending on the remote (0015/0016 and everything through `20260916000000` were already live, contradicting CLAUDE.md's stale claim that 0015/0016 were outstanding). Ran `supabase db push` against the linked `ldzgyzigvbwofbswitrv` project with the user's explicit go-ahead, then verified with the four read-only queries below.
result: pass — `information_schema.columns` returned exactly the 12 expected columns; `pg_policies` returned all four `tdee_estimates_{select,insert,update,delete}_own` policies; `pg_trigger` returned both `t_set_updated_at_tdee_estimates` and `t_record_tombstone_tdee_estimates`; `pg_indexes` included `tdee_estimates_user_updated_idx` (plus the implicit `tdee_estimates_pkey`). Item 6 (real-device smoke test with a live recalibration row) is separate and still pending below.

### 2. Estimate badge under "Maintenance calories" in every state
expected: Nutrition > Targets > editor. Calibrating, Classified, Measured and Measured-aging pills read per the UI-SPEC copy at 360dp and 2x text scale, in light and dark themes. No overflow, hit area about 44px, accent colours legible, badge visible without scrolling past the field.
result: pass

### 3. Detail sheet, with and without a saved manual target
expected: Method, window ("Based on the last N days"), confidence and "WHAT WE USED" inputs are listed individually. With a saved target, two tiles sit side by side (stacked below 400dp) with the "set manually" caption. Active calories, sleep and resting HR appear only under "Also recorded (not used in the estimate)".
result: pass

### 4. HxStatTile visual regression (dashboard macro grid, training level screen)
expected: Tiles look the same as before. The Flexible wrap and the new 8px gap between label and icon bubble change nothing at normal widths. No golden tests exist, so this is a visual diff.
result: blocked
blocked_by: other
reason: "I can't run the app right now"

### 5. Profile activity-level reset flow
expected: (a) while Calibrating: saves at once with seed caption and snackbar. (b) after calibration: confirm dialog "Reset activity level?" with "Keep Current Level" / "Reset Activity Level". A Measured user sees "Saved. Your estimate stays measured from your logs." and the badge stays Measured.
result: blocked
blocked_by: other
reason: "I can't run the app right now"

### 6. Real-device progression over about 14 days
expected: With Health data plus food and weight logging, the estimate moves from Calibrating to Classified (with steps) and to Measured after about two qualifying weekly runs, without the user choosing any duration.
result: blocked
blocked_by: physical-device
reason: "Needs a real device with Health data over ~14 days; can't run the app right now either"

## Summary

total: 6
passed: 3
issues: 0
pending: 0
skipped: 0
blocked: 3

## Gaps
