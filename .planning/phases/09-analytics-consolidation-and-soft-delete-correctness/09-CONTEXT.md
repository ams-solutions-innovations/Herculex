# Phase 09: Analytics consolidation and soft-delete correctness - Context

**Gathered:** 2026-08-14
**Status:** Ready for planning
**Source:** Codebase audit of `lib/features/analytics/` (providers, repository, domain engines, Insights view) plus the v24/v25 schema and sync-tombstone chain.

<domain>
## Phase Boundary

Make Insights report one correct number per metric, sourced from the shared effective-load snapshot, and make sure sync tombstones (`deletedAt`) can never inflate analytics after a cross-device delete.

In scope: consolidating `analytics_providers.dart` onto `trainingSnapshotProvider`, removing the legacy coarse recovery engine and its duplicate card, adding soft-delete filtering to every analytics read path, and switching push/pull balance + biometric-correlation cards to effective load.

Out of scope: the rep-tracking work in Phase 10 (no functional dependency — Phase 10 only shares a schema-version slot, this phase does not add tables); any new analytics metric or chart type; changes to `training_snapshot.dart`'s effective-load math itself (already correct, post-dates the schema churn); changes to `cns_trends.dart`, `muscle_recovery_v3.dart`, `variant_performance.dart` beyond wiring them to soft-delete-filtered input (their algorithms are not in question).

</domain>

<decisions>
## Implementation Decisions

### Legacy recovery card and engine
- **D-01:** Delete `_RecoveryCard` from `insights_view.dart` and delete `domain/muscle_recovery.dart` and `muscleRecoveryProvider` outright — no "keep both, label as summary" fallback. `RecoveryDetailCard` (v3, 19 muscle groups) becomes the only recovery view.
- **D-02:** Delete `cnsFatigueProvider` (`analytics_providers.dart:60-74`) — confirmed dead code, never watched by any widget, superseded by `cnsTrendsProvider`.

### Number changes from the effective-load switch
- **D-03:** No banner, toast, or one-time dismissible note when push/pull and correlation numbers shift after switching to effective load. The old numbers were wrong (missing bands/chains/bodyweight); ship the fix silently like any other bugfix.

### Soft-delete correctness
- **D-04:** Add an automated regression test: soft-delete a set (set `deletedAt`) and assert it is excluded from tonnage, CNS, recovery, balance, and correlation results. This is the acceptance gate for ANLY-03, not a manual-only check.
- **D-05:** Soft-delete filtering (`WHERE deletedAt IS NULL`, or the Drift-companion filter) should be applied once at the shared query level feeding `trainingSnapshotProvider` and `analytics_repository.dart`, not re-implemented per provider — this is implementation detail left to the planner/executor, but the single-filter-point approach is the intended shape given D-01/consolidation.

### Claude's Discretion
- Exact query/filter mechanism for excluding soft-deleted rows (shared repository method vs. Drift query modifier).
- Whether `pushPullBalanceProvider`, `sleepVsRpeProvider`, `hrVsTonnageProvider` are rewritten in place to consume `trainingSnapshotProvider`/`ResolvedSet` or replaced with new equivalents — as long as the end state is one shared, soft-delete-filtered, effective-load-aware data path per ANLY-01/04.
- Test file location/naming for the D-04 regression test.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Roadmap and requirements
- `.planning/ROADMAP.md` — Phase 9 entry (goal, requirements ANLY-01–04, success criteria)
- `.planning/REQUIREMENTS.md` — ANLY-01–04 under "Analytics correctness"

### Prior phase context (informational — no functional dependency)
- `.planning/phases/10-assisted-rep-tracking/10-CONTEXT.md` — notes the only relationship to this phase is merge order (Phase 10 takes schema v26; this phase adds no tables), not a functional dependency.

No other external specs/ADRs — requirements fully captured in decisions above.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `trainingSnapshotProvider` (`lib/features/analytics/presentation/analytics_providers.dart:108-113`) — the shared, effective-load-resolved snapshot already used by `recoveryV3Provider`, `cnsTrendsProvider`, `equipmentPerformanceProvider`, `accessoryPerformanceProvider`. This is the target data path for the providers being consolidated.
- `domain/training_snapshot.dart` — where `ResolvedSet`/effective-load resolution lives; already correct post-v24/v25, just needs soft-delete-filtered input and to become the single source for the remaining providers.
- `domain/muscle_recovery_v3.dart`, `domain/cns_trends.dart` — keep as-is; only their upstream input needs to be soft-delete-clean (already true if they only consume `trainingSnapshotProvider`).

### Established Patterns
- Sync tombstones: `deletedAt` via the `SyncTombstone` mixin (`lib/data/local/tables.dart:22`) is the soft-delete marker for `SetEntries`, `WorkoutExercises`, `WorkoutSessions`, `ExerciseCatalog`, `SetAccessories`, `SetBands`. Deletes route through `deletedAt`, not hard SQL DELETE (per sync trigger routing), except a documented hard-delete edge case for stray seeded rows.
- Riverpod: `FutureProvider` watching Drift streams is the existing convention throughout `analytics_providers.dart`; no need to introduce a new provider type for this phase.

### Integration Points
- Providers to retarget onto `trainingSnapshotProvider` and soft-delete-filtered reads: `muscleRecoveryProvider` (delete, per D-01), `cnsFatigueProvider` (delete, per D-02), `pushPullBalanceProvider`, `sleepVsRpeProvider`, `hrVsTonnageProvider` (`analytics_providers.dart:43-102, 154-167`).
- `insights_view.dart:47-49` — remove `_RecoveryCard` widget class and its instantiation; `RecoveryDetailCard` stays.

</code_context>

<specifics>
## Specific Ideas

No specific UI/behavior references beyond the decisions above — this phase is a correctness/consolidation pass, not new UX.

</specifics>

<deferred>
## Deferred Ideas

None raised during discussion — stayed within phase scope.

</deferred>

---

*Phase: 09-analytics-consolidation-and-soft-delete-correctness*
*Context gathered: 2026-08-14*
