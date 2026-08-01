# Phase 07: Workout Linked Sets - Context

**Gathered:** 2026-07-30
**Status:** Ready for planning
**Source:** User request + codebase scout

<domain>
## Phase Boundary

Improve active workout logging so supersets and giant sets are modeled as linked exercises, visibly connected in the workout list, and fast to log in sequence.

</domain>

<decisions>
## Implementation Decisions

### Linked Exercise Model
- Superset and giant set behavior uses `workout_exercises.superset_group`; it is not a per-set `set_type`.
- Two linked exercises are shown and treated as a superset.
- Three or more linked exercises are shown and treated as a giant set.

### Logging Flow
- Completing a set inside a linked group advances input focus to the next exercise in that linked group.
- Rest timer starts after the last exercise in the linked group, preserving the intent of one rest period after the sequence.

### Visual Design
- Linked exercises receive a left-side rail with numbered nodes and a `SUPER SET` / `GIANT SET` label at the start of the group.
- Exercises remain in the existing active workout list pattern to avoid a disruptive redesign.

### Reordering
- Exercises can be reordered from the active workout list with a bottom-right drag handle.
- Reordering updates `order_index` only; existing set data remains untouched.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Code
- `lib/features/workouts/presentation/active_workout_view.dart` - Active workout exercise list and reorder surface.
- `lib/features/workouts/presentation/active_exercise_card.dart` - Exercise card, set rows, exercise menu, completion behavior.
- `lib/features/workouts/data/workouts_repository.dart` - Workout exercise ordering and `superset_group` persistence.
- `lib/features/workouts/presentation/set_type_menu.dart` - Per-set technique menu.
- `lib/data/local/tables.dart` - Existing `supersetGroup` and `setType` schema.

### Research
- ACSM 2026 resistance training guideline update - consistency, individualization, and advanced techniques as optional rather than default.
- NSCA PTQ 10.1 rest interval article - rest needs vary by exercise intensity, fatigue, cardiovascular recovery, and time constraints.
- Sports Medicine time-efficient training review - supersets/drop sets/rest-pause can reduce training time but raise fatigue and are best applied intelligently.

</canonical_refs>

<specifics>
## Specific Ideas

- User specifically requested a way to connect exercises to other exercises.
- User specifically requested visual lines between linked exercises.
- User specifically requested automatic movement to the next exercise input after finishing one linked exercise.
- User specifically requested a bottom-right icon that can be held to move exercises up/down.

</specifics>

<deferred>
## Deferred Ideas

- Rich group editor with multi-select creation before exercises are added.
- Analytics that separates superset density from raw volume in training load reports.

</deferred>

---

*Phase: 07-workout-linked-sets*
*Context gathered: 2026-07-30*
