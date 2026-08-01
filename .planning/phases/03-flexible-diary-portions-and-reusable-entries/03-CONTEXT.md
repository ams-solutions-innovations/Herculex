# Phase 3: Flexible diary, portions and reusable entries - Context

**Gathered:** 2026-07-30
**Status:** Complete

<domain>
## Phase Boundary

Replace the fixed four-meal presentation with persisted, user-configurable meal slots while keeping old `FoodEntries.meal` keys valid and preserving current food/recipe logging flows.
</domain>

<decisions>
- Meal slots are persisted in local preferences as ordered `{key,label}` records; built-in keys remain stable.
- Renaming changes presentation only; historical entries continue to use their stable key.
- Custom slots can be added, renamed, reordered and deleted; built-in slots are retained.
- Food and recipe logging accepts a stable `mealKey`, while the old `Meal` enum remains supported for compatibility.
- Unknown historical meal keys are rendered as a fallback section instead of being silently moved to Snacks.
</decisions>

<canonical_refs>
- `lib/features/nutrition/domain/meal.dart` — legacy meal enum and date helpers.
- `lib/features/nutrition/domain/meal_slots.dart` — dynamic slot model.
- `lib/features/nutrition/presentation/meal_slots_provider.dart` — persisted slot state.
- `lib/features/nutrition/presentation/meal_slots_view.dart` — Edit meal slots UI.
- `lib/features/nutrition/presentation/nutrition_view.dart` — dynamic diary sections.
- `lib/features/nutrition/data/nutrition_repository.dart` — stable meal-key logging.
</canonical_refs>

<deferred>
- Portion conversion and nutrient availability are Phase 4.
- Saved meals, copy-day and recipe importer are later reusable-entry work.
</deferred>
