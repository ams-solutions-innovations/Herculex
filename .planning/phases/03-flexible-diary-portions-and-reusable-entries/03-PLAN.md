---
phase: 3
plan: 1
type: execute
wave: 1
depends_on: ["02-01"]
autonomous: true
---

# Phase 3 plan: flexible diary and meal slots

1. Persist ordered meal slots with stable keys and default seed values.
2. Add Edit meal slots route with add, rename, reorder and custom-delete actions.
3. Render diary accordions from configured slots and retain unknown historical keys.
4. Pass meal keys through food, recipe and photo-assisted logging.
5. Run analyzer and nutrition/catalogue regression tests.

Acceptance: a custom Pre-workout slot can be created and receives a food log; renaming does not rewrite entries; default slots remain available; no existing nutrition tests regress.
