---
phase: 29-weekly-report-herculex-ai-narrative
reviewed: 2026-10-04T00:00:00Z
depth: standard
files_reviewed: 60
files_reviewed_list:
  - supabase/functions/gemini-analyze/index.ts
  - supabase/functions/gemini-analyze/prompts.ts
  - supabase/migrations/20261003000000_weekly_reports_v48.sql
  - lib/data/local/tables.dart
  - lib/features/weekly_report/data/weekly_report_repository.dart
  - lib/features/weekly_report/data/weekly_report_service.dart
  - lib/features/weekly_report/data/weekly_report_narrative_service.dart
  - lib/features/weekly_report/data/weekly_report_action_queue.dart
  - lib/features/weekly_report/application/weekly_report_controller.dart
  - lib/features/weekly_report/application/weekly_report_tdee_actions.dart
  - lib/features/weekly_report/application/weekly_report_deep_link.dart
  - lib/features/weekly_report/application/weekly_report_resume.dart
  - lib/features/weekly_report/domain/tdee_target_proposal.dart
  - lib/features/weekly_report/domain/weekly_report_facts.dart
  - lib/features/weekly_report/domain/weekly_narrative.dart
  - lib/features/weekly_report/domain/iso_week.dart
  - lib/features/weekly_report/presentation/widgets/tdee_shift_card.dart
  - lib/features/notifications/data/weekly_report_notification_scheduler.dart
  - lib/services/platform/workout_notification_service.dart
  - lib/services/ai/gemini_backend_service.dart
  - lib/app/app.dart
  - lib/app/router/router.dart
  - lib/app/router/routes.dart
  - (remaining changed lib/ and test/ files skimmed by name only; generated files excluded)
findings:
  critical: 0
  warning: 7
  info: 3
  total: 10
status: issues_found
---

# Phase 29: Code Review Report

**Reviewed:** 2026-10-04
**Depth:** standard (focus areas 1-6 traced across files; most test files not read line by line)
**Status:** issues_found

## Summary

The phase is carefully built. The migration column set matches `WeeklyReports` exactly (id, user_id, iso_year, iso_week, week_start_iso, generated_at, payload_version, payload_json, narrative_json, narrative_attempts, knowledge_version, model_version, tdee_decision, tdee_decision_kcal, viewed_at, plus updated_at and deleted_at from the sync mixins). RLS is enabled with own-row policies for select, insert, update and delete, and the update policy has a `with check`. The client sanitises user strings before they reach the prompt. Concurrent opens and narrative calls are de-duplicated in the controller. The TDEE write path is reachable only from two button handlers and is range-guarded.

No blockers. The substantive defects are in the cross-device duplicate handling, the hard-delete of tombstoned rows, the non-atomic TDEE write, and server-side quota accounting.

## Structural Findings (fallow)

None provided.

## Narrative Findings (AI reviewer)

## Warnings

### WR-01: Hard-deleting tombstoned rows in `insertSnapshot` can drop a pending remote delete and resurrect the old report

**File:** `lib/features/weekly_report/data/weekly_report_repository.dart:96-104`
**Issue:** When a week has only soft-deleted rows, `insertSnapshot` runs a raw `delete(_t).go()` and inserts a new row with a new sync uuid. A local soft delete (`deletedAt` set) exists so the deletion can be pushed. If that push is still in the outbox, hard-deleting the row loses the remote tombstone: the old remote row stays live. The regenerated week then has two live remote rows. On a fresh install or second device, `forWeek` picks the earliest by `(generatedAt, id)`, which is the old, supposedly deleted report with its old payload. This contradicts the "regenerate" intent.
**Fix:** Leave the tombstoned rows in place. `_liveForWeek` already ignores them. Insert the new row without the delete. If the delete is kept, first confirm the tombstone has been pushed, or route it through the sync layer's hard-delete path so a tombstone is recorded.

### WR-02: A cross-device duplicate can silently swap the displayed report and orphan the narrative and TDEE decision

**File:** `lib/features/weekly_report/data/weekly_report_repository.dart:150-162, 205-216` (migration header, lines 38-43)
**Issue:** Reads always pick the earliest row by `generatedAt`. If device B generated the same week earlier (or has a skewed clock) and its row syncs in after device A has saved a narrative and recorded a TDEE decision on its own row, device A starts showing B's row. That row has no narrative and no decision, so the TDEE card offers "Update my target" again and the narrative shows pending with Retry. Both are write-once on A's row but not on the row now shown, so the target can be applied twice and a second quota unit is spent. `generatedAt` is a device wall-clock value, so ordering across devices is unreliable.
**Fix:** Pick the winner by "most decided state" before `generatedAt`. For example, prefer a row with `tdeeDecision != null`, then one with `narrativeJson != null`, then the earliest. Alternatively, add a deterministic tiebreak on `sync_uuid` and copy the decision and narrative onto the winner when a duplicate is pulled.

### WR-03: TDEE update writes the target first, then the decision, with no atomicity or stale-proposal check

**File:** `lib/features/weekly_report/application/weekly_report_tdee_actions.dart:36-57`
**Issue:**
- `upsertTarget` is committed before `recordTdeeDecision`. If the decision write returns false (a concurrent double tap, or a duplicate pull as in WR-02) or throws, the target has changed but no decision is recorded. The card then reappears and the user can apply it again.
- The `proposal` passed in comes from the widget's earlier `tdeeTargetProposalProvider` read. If the saved rule changed after the card rendered (the user edited the target in another view, or a sync arrived), `upsertTarget` overwrites the new rule with macros computed from the old one. Explicit confirmation covered the displayed numbers, but the write is not re-validated against the current rule.
- `update` does not call `isActionableWeek`. Only the UI hides the buttons, so an old week's record can write targets if any caller reaches it.
**Fix:** Run both writes in one drift transaction (add a repository method that takes the target write as a callback). Re-resolve the proposal inside `update` and abort if `kcal` or `appliesTo` differ from what was shown. Enforce `isActionableWeek` inside `update` and `keep` as well.

### WR-04: Invalid `facts` and failed or rejected generations still consume a quota unit

**File:** `supabase/functions/gemini-analyze/index.ts:297-321, 569-571`
**Issue:** `bumpUsage` runs before the `weekly_report` case validates `facts`. A request with missing or oversized facts returns 400 but has already spent one of the 5 daily units. A well-formed request whose answer is later rejected (the server normaliser throws, or the client causal guard rejects) also spends a unit, and `retryNarrative` spends another. With a limit of 5, a bad run can lock out the report for the day. This is partly by design (the attempt counter is incremented before the call), but the 400 path is pure waste.
**Fix:** Validate kind-specific payloads before `bumpUsage`, or add an `ai_usage` refund RPC for 4xx validation failures. Consider a higher limit or a separate budget for retries.

### WR-05: Prompt injection is mitigated by prompt wording only; the "numbers must appear verbatim" rule is never enforced

**File:** `supabase/functions/gemini-analyze/prompts.ts:535-563`, `lib/features/weekly_report/domain/weekly_narrative.dart:30-70`
**Issue:**
- Food and exercise names are placed in the prompt as raw JSON. The client strips control characters and caps names at 40 characters, which is good. However, the server does not re-sanitise (`isValidWeeklyReportFacts` checks only size and shape). Any authenticated caller can send arbitrary strings (up to 8000 characters) directly to the endpoint, so the client sanitising is not a trust boundary. The facts are also not delimited or labelled as data beyond one sentence.
- Nothing validates the model's output against the facts. The prompt requires every stated number to appear in the data, but neither the server normaliser nor `WeeklyNarrative.fromJson` checks this. The only output gates are length, count and the causal-word list. A hallucinated figure, or one steered by a food name, is stored permanently (write-once) and shown as Herculex AI's analysis.
- The endpoint also works as a general Gemini proxy (arbitrary facts, 5 per day), with output limited only to the summary shape.
**Fix:** Re-apply control-character stripping and per-string caps server-side, for example by recursing over `facts` and limiting string length. Add an output check that every number in the summary and suggestions occurs in the serialised facts, and reject otherwise. Wrap the data in explicit delimiters (`<facts>...</facts>`) and tell the model to treat the contents as data.

### WR-06: `_update` in the TDEE card leaves the card permanently busy when the action returns false

**File:** `lib/features/weekly_report/presentation/widgets/tdee_shift_card.dart:44-67`
**Issue:** `_busy` is set true before the call and reset only in the `catch` branch. When `update` returns false (decision already exists, the week has no live row, or the range check rejects), no message is shown and `_busy` is never cleared. If the card does not rebuild into a "decided" state, both buttons stay disabled with no feedback. `_keep` has the same flaw: on a false return it also never clears `_busy`, and it ignores the result entirely. It can also throw `ArgumentError` from the repository range check when `currentKcal < 800`. That is caught by the generic handler, but the user sees a misleading "Try again".
**Fix:** Use `try { ... } finally { if (mounted) setState(() => _busy = false); }`. Show a message when the result is false. Validate `currentKcal` before calling `keep`.

### WR-07: Weekly report snapshot is frozen from a partial week when opened mid-week

**File:** `lib/features/weekly_report/data/weekly_report_service.dart:80-90`, `lib/features/weekly_report/application/weekly_report_tdee_actions.dart:25-27`
**Issue:** `generate` uses `windowEnd = min(now, week end)` and persists the row on first open, and the payload is never rewritten (RPT-04). `isActionableWeek` explicitly treats the current ISO week as openable. A user who opens the current week from the dashboard or history on, say, Tuesday permanently freezes a Monday-Tuesday report. The Sunday notification then shows that stale snapshot instead of the full week, and the AI narrative describes two days. The Sunday 18:00 trigger itself also freezes a week that still has six hours left.
**Fix:** Do not persist (or do not allow opening) the current ISO week before its end. Alternatively, generate only for completed weeks, or for the due week at the notification time, and treat the current week as a non-persisted preview.

## Info

### IN-01: Pending-open queue reads a possibly stale `SharedPreferences` cache

**File:** `lib/features/weekly_report/data/weekly_report_action_queue.dart:19-27`, `lib/app/app.dart` (`_drainPendingWeeklyReportOpen`)
**Issue:** The flag is written from the background isolate with its own `SharedPreferences` instance, but read via `ref.read(sharedPreferencesProvider)`, which holds the main isolate's cache. There is no `reload()` anywhere in `lib/` (grep confirms), so the flag is not guaranteed to be visible. In practice the weekly notification has no action buttons, so a plain tap goes through the cold-start or foreground callback and the queue is rarely written. The queue is then close to dead code, and the same limitation applies to the existing fasting queue.
**Fix:** Call `await prefs.reload()` in `take` before reading, or remove the queue and rely on the cold-start check.

### IN-02: Cold-start tap navigation runs before routing and redirect state is settled

**File:** `lib/app/app.dart:104-111, 681-690`
**Issue:** `_openWeeklyReport` does `router.go(AppRoutes.app)` and then `push` from an `initState` microtask. If the app is still on splash, auth or onboarding, a redirect can discard the push, and the tap silently does nothing. `go(AppRoutes.app)` also tears down whatever the user had open (for example an active workout screen) on a foreground tap. There is no second handler to retry once the router is ready. Taps in the other launch states (foreground, warm background) are handled by `onWeeklyReportTap`.
**Fix:** Defer the cold-start navigation until the router has resolved past splash and onboarding (for example, after the first `routerProvider` location settles). Use `push` only when the current location is already the app shell.

### IN-03: Server and client declare the same limits independently

**File:** `supabase/functions/gemini-analyze/index.ts:888-890`, `lib/features/weekly_report/domain/weekly_narrative.dart:20-23`, `lib/features/weekly_report/domain/weekly_report_facts.dart:38`
**Issue:** The 700, 300, 2-3 and 8000 constants are duplicated in TypeScript and Dart with comments as the only link. A change on one side would silently produce rejected narratives or rejected facts.
**Fix:** Keep the comment cross-references and add a test that asserts the constants match (for example by reading the TS constants in a Dart test, or via a shared fixture).

---

_Reviewed: 2026-10-04_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
