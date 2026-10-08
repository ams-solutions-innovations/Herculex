# Architecture

How `lib/` is laid out and why. Enforced by `dart run tool/check_structure.dart`
— if you disagree with a rule, change it there rather than working around it.

## Top level

```
lib/
  main.dart
  app/              bootstrap, DI, routing
    providers.dart      the DI root (reaches into ~14 features; the one place
                        allowed to)
    router/
      router.dart       GoRouter, redirect logic
      routes.dart       every path in the app, as constants
  core/             framework-level utilities, no feature knowledge
    error/  notifications/  utils/
  design_system/    everything visual and shared
    tokens/         colours, spacing, radii, motion
    theme/          ThemeData, theme provider, system chrome, haptics
    components/     Hx* primitives and the remaining shared widgets
    design_system.dart   one import for all three
  data/             cross-feature persistence
    local/          drift database, tables, migrations, seeds
    sync/           the Supabase sync engine
  services/         platform and third-party edges
    ai/             Gemini and scan services
    platform/       notifications, home-screen widgets, shortcuts, bubble
  features/<name>/  one folder per product area
```

## Inside a feature

```
lib/features/<name>/
  data/           repositories, API clients, importers, sync services
  domain/         plain Dart: models, engines, pure functions. No Flutter.
  application/    Riverpod providers, controllers, multi-step actions
  presentation/   widgets
```

`presentation/` gains subfolders once it holds **8 or more** files:

```
presentation/
  views/      full screens        (*_view.dart)
  sheets/     modal bottom sheets (*_sheet.dart)
  dialogs/    dialogs             (*_dialog.dart)
  widgets/    everything else
```

Below eight, a flat `presentation/` is easier to scan than four folders holding
one file each. Today `workouts`, `nutrition`, `programs` and `analytics` are
split; the other 17 features are flat. The suffix in the filename decides the
folder, so placement is never a judgement call.

## The dependency rule

```
presentation ──▶ application ──▶ domain ◀── data
```

- `domain/` is the floor. It imports no Flutter and no sibling layer.
- `data/` and `application/` may both depend on `domain/`, not on each other.
- `presentation/` may reach `application/` and `domain/`, never `data/`
  directly — go through a repository.
- **`core/` and `design_system/` must never import `features/`.** They are what
  features are built *from*; a design-system widget that reaches into one
  feature cannot be reused by any other, which defeats having it.

That last rule is checked mechanically, and it caught two real violations
during the restructure: `core/utils/units.dart` imported the profile feature
just to reach the `MeasurementUnit` enum (the enum moved to `core/utils/`,
which is where a unit concept belongs), and `live_workout_banner.dart` sat in
the shared component library while importing `workouts` providers (it moved to
`features/workouts/presentation/widgets/`).

Cross-feature imports are allowed and common — `workouts` reads `health`
providers, the dashboard reads nearly everything. They are not layering
violations, just coupling to keep an eye on.

## Imports

**Always `package:herculex/...`, never relative.** Enforced by
`always_use_package_imports`, with `directives_ordering` keeping the block
sorted.

This is the rule that makes everything else cheap. While `lib/` used relative
imports — 1,250 of them, 495 at `../../../` — moving a file meant recomputing
`../` depth at every call site, so folder changes were manual and risky. With
absolute paths a move is `git mv` plus one search-and-replace.

Two exceptions, both deliberate:

- `part` / `part of` must stay relative — that is the language rule. Drift's
  `part 'database.g.dart'` is the only such pair today.
- Same-folder barrel files (`design_system/components/components.dart`,
  `tokens/tokens.dart`) export siblings relatively. They move together, so the
  paths stay valid.

Note the lint covers imports but **not exports**. A relative `export` across
directories will not be flagged and will break silently on the next move —
`app/providers.dart` had exactly one, and it produced 32 errors when
`core/clock.dart` moved. Spell cross-directory exports with `package:`.

## File size

No hand-written file over **600 lines**. Generated files (`*.g.dart`) are
exempt.

This is about editability: a 2,700-line widget file cannot be read in one pass,
and an edit to it can easily land in the wrong one of its twenty-odd private
sub-widgets. 51 files are still over the limit; `check_structure.dart` lists
them on every run and the two with a standing reason are recorded as
exemptions in that file.

The technique for splitting one is `part` / `part of` in a subfolder named
after the file:

```
presentation/views/profile_view.dart          // library; all imports; part '...'
presentation/views/profile_view/
  _settings.part.dart                         // part of '../profile_view.dart'
```

The public import path does not change, so no call site is touched. `part`
files cannot carry their own imports — everything lives in the library file —
which is why the parts should be split along thematic lines rather than
arbitrary line counts. Where a sub-widget is genuinely reusable, promote it to
a public widget in `presentation/widgets/` instead of making it a part.

## Routes

Every path lives in `app/router/routes.dart`. `AppRoutes.*` for static paths,
`AppPaths.*(id)` builders for parameterised ones — the `:id` form is only valid
in a `GoRoute(path:)` declaration, and passing it to `context.push` would
navigate to the literal `:id`.

Never spell a path as a string literal at a call site. Two had already drifted
out of sync with the route table before the constants existed, and both shipped
to users as an error screen.

## Target weight

There is one answer to "what is my target weight?": `goalTargetProvider`
(`features/physique/application/goal_target_provider.dart`). With an active
physique goal it is the weight the running roadmap phase ends at, so every
screen, chart and the home-screen widget follow the roadmap when it changes.
Without one it is the weight the member typed (`Profile.targetWeightKg`, with
`goalWeightProvider` as its fallback).

Readers watch the provider and never combine those two stores themselves.
Writers call `GoalTargetController.setTarget` (UI: `saveGoalTarget`). With a
roadmap that moves the running phase and re-chains the later ones, so a typed
weight can never contradict the roadmap; a weight that needs a different phase
is refused with a pointer to the roadmap editor. The profile's own copy of the
typed weight is left alone while a roadmap runs.

## Schema changes

Bumping the drift `schemaVersion` is five chores, not one. Missing any of them
fails ~26 tests or, worse, silently quarantines cloud sync. See `CLAUDE.md` for
the checklist.
