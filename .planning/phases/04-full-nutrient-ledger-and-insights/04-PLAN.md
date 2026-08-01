---
phase: 4
plan: 1
type: execute
wave: 1
depends_on: ["03-01"]
autonomous: true
---

# Phase 4 plan: nutrient ledger and portions

1. Add additive portion columns and basis-aware calculation helpers.
2. Aggregate source nutrient maps into DailyTotals with availability semantics.
3. Add persisted selected-nutrient settings and a compact configurable summary.
4. Surface basis/unit in the food detail/logging flow.
5. Run analyzer and regression tests for 100 g, 100 ml, labelled serving and missing nutrient cases.

Acceptance: a 100 g item, a 250 ml item and a legacy serving item calculate without unit fabrication; selected micronutrients render with units; absent source values are marked unavailable; existing diary tests remain green.
