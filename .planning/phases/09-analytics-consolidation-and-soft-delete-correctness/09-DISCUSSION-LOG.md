# Phase 09: Analytics consolidation and soft-delete correctness - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-08-14
**Phase:** 09-analytics-consolidation-and-soft-delete-correctness
**Areas discussed:** Recovery card removal, Number changes from effective-load switch, Soft-delete verification strategy

---

## Recovery card removal

| Option | Description | Selected |
|--------|-------------|----------|
| Delete outright | Remove `_RecoveryCard` and `muscle_recovery.dart` entirely; `RecoveryDetailCard` (v3) becomes the only recovery view | ✓ |
| Keep both, label them | Keep the coarse 9-group card but label it as a simplified summary above the detailed v3 card | |

**User's choice:** Delete outright.
**Notes:** No fallback/summary card — the v3 model fully supersedes the legacy one.

---

## Number changes from effective-load switch

| Option | Description | Selected |
|--------|-------------|----------|
| Just show correct numbers | No banner/explanation — old numbers were wrong, new ones are correct, silent fix | ✓ |
| Add a one-time note | Dismissible note on Insights explaining recalculated numbers may look different | |

**User's choice:** Just show correct numbers.
**Notes:** Treated as an ordinary bugfix, not a user-facing change needing explanation.

---

## Soft-delete verification strategy

| Option | Description | Selected |
|--------|-------------|----------|
| Automated test | Add a regression test asserting a soft-deleted set is excluded from tonnage/CNS/recovery/balance/correlation results | ✓ |
| Manual check only | Verify by hand during the phase without a dedicated regression test | |

**User's choice:** Automated test.
**Notes:** This becomes the acceptance gate for ANLY-03 (see CONTEXT.md D-04).

---

## Claude's Discretion

- Exact query/filter mechanism for excluding soft-deleted rows.
- Whether existing providers (`pushPullBalanceProvider`, `sleepVsRpeProvider`, `hrVsTonnageProvider`) are rewritten in place or replaced, as long as the end state is one shared, soft-delete-filtered, effective-load-aware data path.
- Test file location/naming for the soft-delete regression test.

## Deferred Ideas

None — discussion stayed within phase scope.
