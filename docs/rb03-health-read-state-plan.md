# RB-03 Health Read State Remediation Plan

Date: 2026-08-13

## Status

Implemented and verified as of 2026-08-13.

This covers `docs/app-audit-report-2026-08-10.md` release blocker #3:
health data is fabricated when platform reads fail or return no usable data.

## Goal

Health data imported from Apple Health, Health Connect, Samsung Health, or the
`health` Flutter plugin must carry an explicit read state:

- `available`: a platform read succeeded and produced at least one trusted
  metric value.
- `denied`: permissions are missing or were rejected.
- `unavailable`: the platform, plugin, or data type is not supported on this
  device/build.
- `error`: the platform read attempted but failed unexpectedly.
- `empty`: the platform read succeeded but returned no usable records.

The app must not replace missing health reads with synthetic measurements such
as `0`, `10000`, or inferred calories/sleep/heart-rate values. Derived features
may choose conservative behavior, but that behavior must be based on an explicit
non-available state rather than a fake health sample.

## Current Problem Surface

- `lib/features/health/data/health_service.dart`
  - Catches read errors and continues as if the metric were simply zero.
  - Deletes today's rows before knowing whether each metric was actually read.
  - `getAverageSteps` returns `10000.0` when no step samples exist.
  - `getWorkouts` returns an empty list on plugin failure, making "failed" and
    "no workouts" indistinguishable.
- `lib/features/health/presentation/health_providers.dart`
  - `activityBasedAdjustmentProvider` creates a fake `HealthSampleData` with
    `value: 0.0` when steps are missing.
- `lib/features/health/presentation/health_integrations_view.dart`
  - Biometrics grid fills missing metric cards with `0`.
  - Empty-state copy only says no synced data, not why.
- `lib/features/dashboard/presentation/dashboard_providers.dart`
  - Exercise calories collapse loading, denied, unavailable, empty, and error
    into `0`.
- `lib/features/nutrition/presentation/nutrition_providers.dart`
  - Burned-calorie target adjustment only reads persisted rows, so it cannot
    distinguish a true zero from unread/untrusted health data.

## Implementation Plan

### 1. Add an explicit health read contract

Create a small domain model near the health feature, for example
`lib/features/health/domain/health_read_state.dart`.

Recommended shape:

- `enum HealthReadStatus { available, denied, unavailable, error, empty }`
- `class HealthRead<T>` with:
  - `status`
  - `value`
  - `dataTypes`
  - `platform`
  - `readAt`
  - optional `message`
  - optional `Object error`
- Convenience getters:
  - `isAvailable`
  - `hasTrustedValue`

For today's biometrics, add a typed aggregate:

- `class DailyHealthRead`
  - `dateIso`
  - one `HealthRead<T>` per metric group:
    - steps
    - activeKcal
    - restingHr
    - sleepHours
    - waterMl
    - foodKcal
    - weightKg
  - `hasAnyAvailableMetric`
  - `overallStatus`, derived from child reads:
    - `available` if any metric is available
    - `denied` if all attempted reads are denied
    - `unavailable` if all attempted reads are unavailable
    - `error` if any attempted read errored and none are available
    - `empty` if all attempted reads succeeded empty

### 2. Make platform reads return states, not substitutes

Refactor `HealthService.runDailySync()` into small metric-specific read helpers:

- `_readSteps`
- `_readActiveKcal`
- `_readRestingHr`
- `_readSleepHours`
- `_readWaterMl`
- `_readFoodKcal`
- `_readWeightKg`
- `_readWorkouts`

Each helper should:

- perform exactly one platform read concern;
- return `HealthRead<T>`;
- classify known permission failures as `denied`;
- classify known unsupported platform/data-type failures as `unavailable`;
- classify plugin exceptions as `error`;
- return `empty` when the plugin succeeds but yields no usable datapoints;
- return `available` only when there is a real value from platform data.

Do not initialize numeric reads to `0`. Use nullable accumulators or local lists
and only produce a numeric value when data was actually read.

### 3. Stop destructive replacement on failed reads

Replace the current "delete all today's rows, then insert positive values"
transaction with per-metric upsert/delete behavior:

- If a metric read is `available`, replace only that metric's row for the date.
- If a metric read is `empty`, delete only that metric's row for the date,
  because the platform confirmed there is no data.
- If a metric read is `denied`, `unavailable`, or `error`, leave the previous
  trusted row untouched unless product decides stale data should be hidden.

Preferred UI behavior is to avoid showing stale rows as today's successful read.
If the existing `health_samples` table cannot express freshness/state, add an
in-memory provider for the latest read result first and defer schema changes
unless tests prove persistence needs state metadata.

### 4. Remove synthetic fallback values from providers

Update provider behavior so missing health data remains missing:

- `activityBasedAdjustmentProvider`
  - If today's steps are not `available`, return a new neutral result such as
    "Health data unavailable" with `volumeFactor: 1.0`.
  - If baseline steps are unavailable or empty, use a neutral no-adjustment
    result, not `10000`.
- `HealthService.getAverageSteps`
  - Change return type to `Future<HealthRead<double>>` or
    `Future<double?>`.
  - Empty history should be `empty` or `null`, never `10000.0`.
- `externalWorkoutsProvider`
  - Change to expose `HealthRead<List<HealthDataPoint>>` or a paired status
    object, so `error` does not look like no workouts.
- `todayExerciseKcalProvider`
  - Prefer returning a typed result, for example `HealthRead<double>`, or
    `double?` if a smaller change is needed.
  - Remaining-calorie calculations should add exercise calories only when the
    value is trusted.

### 5. Show explicit UI states

Update health UI copy and cards to distinguish the five states:

- `available`: show measured value and normal timestamp/source affordance.
- `denied`: show permission/access action.
- `unavailable`: show platform unsupported or not installed/configured.
- `error`: show retry affordance and concise failure message.
- `empty`: show "No data recorded for this period" rather than `0`.

Specific UI targets:

- `HealthIntegrationsView`
  - Today's biometrics section should render per-metric status instead of zero
    cards.
  - The top impact card should avoid training recommendations derived from
    missing step data.
- `HealthPlatformDetailView`
  - Manual sync should report partial success when some metrics are available
    and others are denied/unavailable/error/empty.
  - The success snackbar should not fire after an all-denied/all-error sync.
- Dashboard and nutrition calorie surfaces
  - Treat missing exercise calories as "not counted" rather than `0 kcal`
    from a successful health read.

### 6. Keep sleep overlap handling

Preserve and test the existing interval-merge approach for sleep:

- collect `SLEEP_SESSION`, `SLEEP_ASLEEP`, `SLEEP_DEEP`, and `SLEEP_REM`;
- sort intervals;
- merge overlaps before summing;
- return `empty` if the read succeeds but there are no usable intervals;
- return `available` only when the merged duration is positive.

### 7. Test plan

Add focused unit tests around the new state contract and service behavior.
Because `HealthService` currently constructs `Health()` internally, first make
the plugin client injectable behind a small adapter interface.

Suggested tests:

- permission denied:
  - `requestPermissions` failure or permission exception yields `denied`;
  - no synthetic rows are inserted.
- unavailable platform/type:
  - unsupported plugin response maps to `unavailable`;
  - UI/provider state remains explicit.
- plugin error:
  - thrown read exception yields `error`;
  - previous trusted rows are not replaced with zero/empty rows.
- empty platform data:
  - successful empty read yields `empty`;
  - metric row for that date is removed or hidden according to the chosen
    persistence policy.
- partial data:
  - steps available and sleep denied persists/returns steps only;
  - aggregate status communicates partial success.
- overlapping sleep:
  - overlapping intervals are merged and not double-counted.
- downstream providers:
  - activity adjustment is neutral when steps or baseline are unavailable;
  - remaining calories do not count exercise calories unless available.

Likely files:

- `test/health_service_read_state_test.dart`
- `test/health_providers_read_state_test.dart`
- small widget tests only if status rendering is non-trivial.

### 8. Verification commands

Run focused checks first:

```bash
flutter test test/health_service_read_state_test.dart test/health_providers_read_state_test.dart
flutter test test/health_integration_test.dart
flutter analyze lib/features/health lib/features/dashboard/presentation/dashboard_providers.dart lib/features/nutrition/presentation/nutrition_providers.dart test/health_service_read_state_test.dart test/health_providers_read_state_test.dart
```

Then run the broader suite if time allows:

```bash
flutter test
flutter analyze
```

## Acceptance Criteria

- No health platform read path fabricates a user measurement.
- `available`, `denied`, `unavailable`, `error`, and `empty` are represented in
  code and visible where the user needs to understand health sync state.
- `0` is only shown or stored when it is a real platform value, not a fallback.
- Failed reads do not overwrite trusted data with synthetic empty data.
- Empty successful reads are distinguishable from denied/unavailable/error.
- Activity adjustment and calorie math remain conservative when health data is
  missing.
- Tests cover denied permission, unavailable platform/type, platform error,
  empty data, partial data, and overlapping sleep.

## Implementation Summary

- Added `HealthReadStatus`, `HealthRead<T>`, and `DailyHealthRead` in
  `lib/features/health/domain/health_read_state.dart`.
- Added an injectable `HealthAdapter` so health plugin behavior can be tested
  without platform channels.
- Refactored `HealthService.runDailySync()` to return explicit metric states
  and persist only trusted `available` values.
- `empty` reads delete only the affected metric row for the date.
- `denied`, `unavailable`, and `error` reads leave previous trusted rows intact
  instead of replacing them with zero or empty data.
- Removed the 10000-step average fallback.
- Updated health providers, activity adjustment, dashboard exercise calories,
  and nutrition burned-calorie adjustment to treat missing health data as
  missing, not as `0`.
- Updated health integration sync UI to store/display the last explicit read
  result and avoid all-failed syncs looking like successful green syncs.
- Kept and tested merged sleep intervals so overlapping sleep types are not
  double-counted.

## Verification

Ran:

```bash
flutter test test/health_service_read_state_test.dart test/health_providers_read_state_test.dart
flutter test test/health_integration_test.dart
flutter analyze lib/features/health lib/features/dashboard/presentation/dashboard_providers.dart lib/features/nutrition/presentation/nutrition_providers.dart test/health_service_read_state_test.dart test/health_providers_read_state_test.dart
```

Results:

- Focused RB-03 tests passed.
- Existing health integration tests passed.
- Focused analyzer passed.

No Drift schema change was required.
