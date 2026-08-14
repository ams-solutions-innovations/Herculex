---
phase: 10-assisted-rep-tracking
plan: 06
subsystem: rep-tracking-debug-tooling
tags: [flutter, dart, rep-tracking, fixtures, debug-tool, share_plus]
requires:
  - "MotionSample/MotionTrace/RepMovement (10-02)"
  - "RepCaptureService (10-03b, extended by 10-04's buildPhoneSuggestion/activeCaptureIdFor)"
  - "PhoneMotionSource start/stop/captureEnded (10-03b/10-04)"
  - "the debug-only /admin/* router convention and AdminDashboardView (existing)"
provides:
  - "fixture_corpus.dart — the closed 11-fixture FixtureSpec list and FixtureCorpusStatus.evaluate sufficiency logic, pure Dart"
  - "fixture_recorder.dart — on-device CSV+sidecar writer matching 10-02's exact fixture schema, synthetic:false hardcoded"
  - "RepCaptureService.debugRawTraceObserver — a debug-only hook called before the REP-04 raw-buffer discard"
  - "fixture_recording_view.dart — the /admin/fixture-recording checklist, per-fixture capture form and export-via-share_plus screen"
affects:
  - "10-02 Task 5 (still the actual REP-06 gate): once the developer records real workouts through this screen and exports/commits the files under test/fixtures/motion/, that checkpoint can clear"
tech-stack:
  added: []
  patterns:
    - "Directory-injected test seam: FixtureRecorder takes an optional baseDirOverride so tests point it at a temp directory without touching getApplicationDocumentsDirectory()"
    - "Debug-only hook pattern: a nullable field defaulting to null, assigned from exactly one presentation-layer file, reset in a finally-equivalent — mirrors no prior pattern in the codebase but is intentionally the narrowest possible REP-04 exception"
key-files:
  created:
    - lib/features/reps/domain/fixture_corpus.dart
    - lib/features/reps/data/fixture_recorder.dart
    - lib/features/reps/presentation/fixture_recording_view.dart
    - test/fixture_corpus_test.dart
    - test/fixture_recorder_test.dart
  modified:
    - lib/features/reps/data/rep_capture_service.dart
    - lib/features/admin/presentation/admin_dashboard_view.dart
    - lib/app/router.dart
decisions:
  - "MotionTrace already had toCsv()/fromCsv() (10-02 output) matching the exact t_ms,x,y,z fixture format, so fixture_recorder.dart reuses it rather than re-implementing CSV serialisation — one fewer place the format could drift from 10-02's own fixtures."
  - "ring-dips maps to RepMovement.dip, not a separate RepMovement.ringDip — the enum only has {pullUp, dip} (rep_movement.dart is the single declaration, imported everywhere). The plan's <interfaces> block mentioned a hypothetical 'ringDip' serialised value; fixture_corpus.dart's ringdip_wrist_8reps entry uses RepMovement.dip, matching rep_tracking_eligibility.dart's actual mapping. Documented here as a deviation from the plan's own interface sketch, not from 10-02/10-04's real code."
  - "The wrist capture-form path arms debugRawTraceObserver on Start and disarms it on Stop and in State.dispose (belt-and-braces double reset), because there is no Dart-side call to begin a wrist capture — the watch itself starts it (10-CONTEXT) — so the screen can only prepare to catch whichever capture_end the shared RepCaptureService reports next."
  - "The phone capture-form path bypasses debugRawTraceObserver entirely and saves directly from PhoneMotionSource.captureEnded's trace, since RepCaptureService.buildPhoneSuggestion (10-04) never buffers phone samples the way the wrist path's _CaptureState does — there is no discard-then-observe moment to hook on the phone side, the trace is simply handed to the caller."
metrics:
  duration: ~50 min
  tasks: 5
  files_created: 5
  files_modified: 3
  tests_added: 9
  completed: 2026-08-14
---

# Phase 10 Plan 06: Assisted Rep Tracking — In-App Fixture-Recording Debug Tool Summary

An in-app debug tool that replaces 10-02 Task 5's "record on hardware, hand-copy CSVs" procedure: a closed 11-fixture corpus definition, an on-device recorder that writes byte-for-byte the same CSV+sidecar format 10-02's fixtures use, a narrowly-scoped debug hook on `RepCaptureService`, and a checklist-plus-capture screen under the existing debug-only admin area — so the developer can record the corpus opportunistically across upcoming real workouts instead of one dedicated hardware session.

**This plan does not close REP-06 and does not touch `test/fixtures/motion/`.** It produces files in app-private storage that the developer still has to record (by actually doing pull-ups/dips wearing the watch), export, and commit by hand. 10-02 Task 5's automated fixture-count/provenance check remains the real gate.

## What Was Built

**Task 1 — the closed corpus (`a0a6790`).** `fixture_corpus.dart` declares `FixtureSpec` and `const List<FixtureSpec> requiredFixtures` with exactly the 11 rows from 10-02-PLAN.md's Task 5 table, verbatim (name, purpose, movement, source, placement, target rep count). `FixtureRecordState.needsRedo` exists as a future hand-set state but `FixtureCorpusStatus.evaluate` never assigns it — a spec is only ever `recorded` or `missing`, always derived from the name list passed in, never cached in-memory state. Pure Dart, no I/O, no Flutter.

**Task 2 — the on-device recorder (`1502e20`).** `fixture_recorder.dart`'s `FixtureRecorder` resolves `fixturesDir()` under the app's documents directory (`fixtures/motion`), writes `<name>.csv` via `MotionTrace.toCsv()` and `<name>.json` with all ten sidecar keys, and hardcodes `'synthetic': false` as a literal in the map — never a parameter. `listRecorded()` requires both a `.csv` and a `.json` present for a name to count as recorded, so an interrupted save (only one half written) is correctly reported as still missing. A constructor-injectable `baseDirOverride` makes the whole class testable against a temp directory without touching the real app documents dir.

**Task 3 — the debug raw-trace hook (`d93c0af`).** `RepCaptureService` gained `debugRawTraceObserver`, a public nullable field defaulting to `null`. The wrist capture-end handler now hoists its assembled `MotionTrace` to an outer-scope variable so the existing `finally` block (which already discards the raw buffer for REP-04) can call `debugRawTraceObserver?.call(captureId, trace)` immediately before `_captures.remove(captureId)` — wrapped in its own `try`/`catch` so a throwing observer can never stop the buffer from clearing. The doc comment states plainly it is debug-only and assigned from exactly one file; verified by `grep -rln "debugRawTraceObserver" lib/features/` showing only `rep_capture_service.dart` and `fixture_recording_view.dart`. All 15 pre-existing `rep_capture_service_test.dart` cases still pass unmodified — the hook is additive and inert by default.

**Task 4 — the debug screen (`fd1382c`).** `fixture_recording_view.dart` builds `FixtureRecordingView`: on build it calls `FixtureRecorder.listRecorded()` and renders `FixtureCorpusStatus.evaluate(...)` as a sufficiency banner ("11/11 recorded — corpus complete" or "N missing — M/11 recorded") plus all 11 rows with a recorded/missing icon, name and purpose. Tapping any row opens `_FixtureCaptureScreen`: read-only movement/source/placement text from the `FixtureSpec`, editable `description`/`recordedBy`/`deviceModel` text fields, and a `repCount` number field whose helper text states plainly it must be the human count, never the app's. Start/Stop drive the fixture's source: for `wrist`, Start arms `debugRawTraceObserver` (disarmed on Stop and again in `State.dispose` as a belt-and-braces reset) while the developer starts the real capture on the watch itself; for `phone`, Start/Stop call `PhoneMotionSource.start()`/`stop()` directly and a `captureEnded` listener saves the resulting trace. "Export recorded fixtures" gathers every `.csv`/`.json` pair via `Share.shareXFiles`. Wired into `admin_dashboard_view.dart` under a new "Rep Tracking" section and registered as `/admin/fixture-recording` inside the router's existing `kDebugMode`-gated admin block — same release-exclusion convention as every other `/admin/*` route.

**Task 5 — pure-logic tests (`bb7b90a`).** `test/fixture_corpus_test.dart` (5 cases): 11 entries, unique names, empty/partial/full `evaluate()` outcomes and `sufficient` boundary. `test/fixture_recorder_test.dart` (4 cases, temp-dir-backed via `baseDirOverride`): save→listRecorded round-trip, all ten sidecar keys present with `synthetic` always `false`, the CSV's exact `t_ms,x,y,z` row order matching sample count, and a CSV written without its `.json` sidecar correctly excluded from `listRecorded()`.

## Verification

| Check | Result |
|---|---|
| `flutter test test/fixture_corpus_test.dart test/fixture_recorder_test.dart` | 9 tests, 0 failures |
| `flutter analyze lib/features/reps/` | No issues found |
| `flutter analyze lib/app/router.dart lib/features/admin/presentation/admin_dashboard_view.dart` | No issues found |
| `grep -n "debugRawTraceObserver" lib/features/reps/data/rep_capture_service.dart` | field declaration + guarded call site inside the existing discard `finally` |
| `grep -rln "debugRawTraceObserver" lib/features/` (excluding `rep_capture_service.dart`) | exactly one hit: `fixture_recording_view.dart` |
| `grep -n '"synthetic"' lib/features/reps/data/fixture_recorder.dart` | the sidecar map literal `'synthetic': false,` — never a parameter |
| `flutter test test/rep_capture_service_test.dart test/rep_tracker_widget_test.dart test/rep_tracker_write_boundary_test.dart test/rep_review_sheet_e2e_test.dart` (regression) | 32 tests, 0 failures — no regressions from the observer hook or the new files |
| `flutter test test/rep_detector_test.dart test/rep_fixture_provenance_test.dart` | fail to load — pre-existing, unrelated to this plan: these files are 10-02 Task 6 output, which is still blocked behind 10-02 Task 5's pending human checkpoint. Confirmed by inspection, not caused by this plan's changes. |

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `FixtureRecorder.fixturesDir()`'s override check triggered an unnecessary-`!` analyzer warning**
- **Found during:** Task 2, first analyze pass
- **Issue:** `_baseDirOverride != null ? _baseDirOverride!() : ...` — the analyzer flagged the `!` as redundant because the ternary's condition already promotes the field within that branch, but Dart's field-promotion doesn't extend across the ternary the way a local variable's would.
- **Fix:** Hoisted the field read to a local (`final override = _baseDirOverride;`) before the ternary, which promotes cleanly with no `!` needed.
- **Files modified:** `lib/features/reps/data/fixture_recorder.dart`
- **Commit:** `1502e20`

### Intentional Scope Decisions

- **`RepMovement.ringDip` does not exist and was never added.** The plan's `<interfaces>` block sketched a `'ringDip'` string as a possible serialised movement value, but `RepMovement` (10-01's single declaration, imported everywhere) only has `{pullUp, dip}`, and `rep_tracking_eligibility.dart` already maps `ring-dips` to `RepMovement.dip`. `fixture_corpus.dart`'s `ringdip_wrist_8reps` entry uses `RepMovement.dip`, matching the real mapping rather than the plan's own interface sketch. This is a deviation from what the plan predicted the interface would look like, not from any actual 10-01/10-02/10-04 code, which was read directly before writing Task 1.
- **The plan's `<interfaces>` block for `RepCaptureService` predates 10-04's real additions.** Before touching the file, I read the actual current `rep_capture_service.dart` (which already carries `buildPhoneSuggestion`/`activeCaptureIdFor`/`abort`/`rawBufferSampleCount` from 10-03b and 10-04, none of which the 10-06 plan's interface sketch mentioned) rather than trusting the plan's snippet. Task 3's edit is additive to the real file and does not touch or restate any of those existing members.
- **The wrist and phone capture-form paths in Task 4 use genuinely different mechanisms**, as called out in the plan's own action text but worth restating precisely here: wrist fixtures rely on `debugRawTraceObserver` because the wrist path's raw samples are only ever available inside `RepCaptureService`'s private `_CaptureState` buffer, discarded immediately after detection (REP-04) — the observer is the only way to see them before they're gone. Phone fixtures need no such hook: `PhoneMotionSource.captureEnded` already hands the screen a complete `MotionTrace` directly, so the capture form saves from that stream without touching `RepCaptureService` at all for the phone case.

## Known Stubs

None that block this plan's own goal. The tool is fully wired end to end (checklist → capture → save → export); what remains stubbed is the fixture corpus itself — zero of the 11 required `.csv`/`.json` pairs exist on any device yet, because that requires the developer to actually perform the workouts. That is the explicitly out-of-scope human step this plan exists to make easier, not a gap in what this plan built.

## Threat Flags

None beyond what the plan's own threat register (T-10-17, T-10-18, T-10-19) already covers — no new network endpoints, auth paths or schema changes were introduced. `debugRawTraceObserver`'s only two call sites (declaration + guarded call in `rep_capture_service.dart`, single assignment in `fixture_recording_view.dart`) match the plan's mitigation for T-10-17 exactly.

## Requirements

REP-06 remains open in `REQUIREMENTS.md`, deliberately. Per 10-CONTEXT's plan sequence table: "10-06 does not close REP-06 by itself — it produces app-local files the developer still exports and commits under `test/fixtures/motion/` by hand. 10-02 Task 5's automated fixture-count check remains the actual gate." No requirement IDs are marked complete by this plan.

## How a Developer Uses This Screen End to End

1. **Open it.** Launch a debug build, go to the existing Admin Dashboard (`/admin` — same place "Insert Custom Workout"/"Insert Custom Recipe" live), and tap the new "Fixture Recording (REP-06)" card under a "Rep Tracking" section. This pushes `/admin/fixture-recording`.
2. **What they see.** A banner at the top states overall sufficiency ("11/11 recorded — corpus complete" or "N missing — M/11 recorded"), computed fresh from an on-device directory scan every time the screen loads — not from anything cached in memory. Below it, all 11 required fixtures are listed (`pullup_wrist_clean_8reps` through `noise_regrip_rest_45s_0reps`), each showing its name, purpose, source/placement, and a check icon (recorded, green) or an empty circle (missing).
3. **Recording one fixture.** Tapping any row opens a capture form for that specific fixture. Movement, source and placement are shown read-only (prefilled from the fixture's spec — nothing to fill in there). The developer fills in: the ground-truth rep count (a plain number field, with helper text explicitly saying to count out loud or film the set and enter the human count — never the detector's), a short description, their name/handle (`recordedBy`), and the exact device model string they're using (typed by hand, e.g. "Galaxy Watch 6 SM-R930" — no new device-info plugin).
4. **Starting/stopping capture.**
   - **For a wrist fixture** (7 of the 11): tap Start on the phone screen, then start the actual capture on the watch itself as normal (10-CONTEXT: capture always begins from the user's own tap on the watch, never from the phone). The phone screen is now "armed" and waiting. When the watch capture ends, the trace is caught automatically and saved with the form's ground-truth values. Tap Stop on the phone form afterward (or if the developer wants to abandon that attempt) to disarm the hook.
   - **For a phone fixture** (2 of the 11 — the pocket and armband placement ones): the developer must have already picked the matching sensor placement (pocket vs. armband) on the app's own consent screen beforehand, since `PhoneMotionSource` reads that setting, not anything on this debug screen. Tap Start to begin the phone's own accelerometer capture directly, physically do the set with the phone in that placement, then tap Stop — the trace saves immediately with the form's values.
5. **Getting files off the device.** Back on the main checklist screen, tap the export icon (top-right, share icon). This gathers every `.csv`/`.json` pair currently recorded and opens the OS share sheet via `share_plus` — e.g. AirDrop/Nearby Share/email/cloud-drive save, whatever's available on the device. There is no automatic upload; nothing leaves the device until this explicit tap.
6. **Committing.** The developer places the exported `.csv`/`.json` pairs under `test/fixtures/motion/` in the repo and commits them normally. Once all 11 are present with `synthetic: false`, 10-02 Task 5's blocking checkpoint can be resumed/cleared and Task 6's accuracy suite can run for the first time against real data.

This can be done incrementally across as many real workout sessions as needed — the checklist always reflects exactly what's been recorded so far, and there is no requirement to record all 11 in one sitting.

## Next Phase Readiness

- The tool is complete and ready to use starting the developer's next workout involving pull-ups or dips.
- REP-06 is still open. It closes only once 10-02 Task 5's `<how-to-verify>` automated check (`test/fixtures/motion/*.csv` count ≥ 11 and `synthetic: false` on all of them) passes for real — after the developer records, exports and commits the corpus using this screen.
- No further Dart/Kotlin work is needed for REP-06 to close; the remaining work is entirely the human recording step this plan was built to make easier.

## Self-Check: PASSED

All five created files exist on disk (`fixture_corpus.dart`, `fixture_recorder.dart`, `fixture_recording_view.dart`, `test/fixture_corpus_test.dart`, `test/fixture_recorder_test.dart`); all three modified files (`rep_capture_service.dart`, `admin_dashboard_view.dart`, `router.dart`) carry the changes. All five task commits (`a0a6790`, `1502e20`, `d93c0af`, `fd1382c`, `bb7b90a`) are present in `git log`.
