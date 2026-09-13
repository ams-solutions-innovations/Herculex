# Phase 15: Program Generator Regression Fixes & Interaction Hardening - Research

**Researched:** 2026-09-13  
**Domain:** Program generator prescription rules, modal surface styling across themes, workout shell keyboard obstruction synchronization, and calendar schedule session launching.  
**Confidence:** HIGH. All four areas have been verified against the codebase (`smart_program_planner.dart`, `planned_session_resolver.dart`, `smart_substitution_sheet.dart`, `hx_sheet.dart`, `main_scaffold.dart`, `active_workout_view.dart`, `day_detail_sheet.dart`, `scheduled_workout_service.dart`).

---

<user_constraints>
## User Constraints (from REQUIREMENTS.md & Blueprint)

### Locked Decisions

1. **FIX-01 (Program Generator Prescription Guardrails):**
   - Novice linear full-body programs must never receive Dynamic Effort (8×3 speed work @ 55% 1RM) without explicit user opt-in.
   - Elimination of the split source of truth between preview and active workout: `ProgramReviewView` and `ActiveWorkoutView` must reflect identical set counts and types.
   - Hard safety gates in `SmartProgramPlanner` preventing `SlotTrainingMethod.dynamicEffort` from being assigned to novice linear full body slots.
   - Defending `PlannedSessionResolver._resolvePrescription`: if an incoming program is novice or linear, fallback to straight sets / standard linear progression instead of silently escalating to 8×3 Dynamic Effort unless explicitly flagged as user opt-in.

2. **FIX-02 (Replacement Exercise Modal Opacity & Theme Support):**
   - The exercise replacement modal must render using opaque `surfaceContainer` (via `HxSheet`) across both light and dark themes.
   - No hand-rolled translucent sheets or reliance on `theme.scaffoldBackgroundColor` (which is `Colors.transparent` in Herculex).
   - Both `ExerciseReplacementSheet` (plan review) and `SmartSubstitutionSheet` (active workout) must be fully opaque, styled with `HxSheet` or `context.hx.surfaceContainer` with anti-aliased rounded top borders and standard grab handles.

3. **FIX-03 (Keyboard Obstruction Synchronization & Hit-Testing):**
   - Active workout input focus (on weight, reps, or RPE) must hide and disable hit-testing on the app bottom navigation bar, the Finish workout button, and the Add Exercise button simultaneously.
   - Synchronized single source of truth for keyboard/focus obstruction between `MainScaffold` and `ActiveWorkoutView`.
   - Invisible controls must be excluded from semantics (`ExcludeSemantics`) and hit-testing (`IgnorePointer`) immediately upon focus, not waiting for deferred platform metrics.
   - Closing the keyboard / unfocusing immediately and smoothly restores all shell controls.

4. **FIX-04 (Calendar Day Detail Schedule Launching):**
   - `DayDetailSheet` launches scheduled workouts strictly by explicit `scheduleId`, never dropping down to generic `todaysWorkout()` with `limit(1)`.
   - Clean differentiation between **Start** (new session materialization + status update) and **Resume** (navigating directly to existing open session without re-materialization or duplicate row creation).
   - Starting or resuming from calendar day detail must immediately switch navigation to the Workouts tab (Tab 2) so the user enters the active workout flow.
   - "View workout" remains purely read-only via `previewScheduledWorkout` and never modifies workout sessions or schedule state.

</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Codebase Citations & Research Support |
|----|-------------|---------------------------------------|
| **FIX-01** | Novice linear full-body programs never receive Dynamic Effort 8×3 sets without explicit user opt-in. Preview and active workout set counts must match. | `lib/features/programs/data/smart_program_planner.dart:810-875`, `lib/features/workouts/data/planned_session_resolver.dart:400-470`, `lib/features/programs/presentation/views/program_review_view.dart:620-630`. |
| **FIX-02** | Replacement exercise modal renders using opaque `surfaceContainer` (via `HxSheet`) across light and dark themes. | `lib/features/workouts/presentation/sheets/smart_substitution_sheet.dart:80-110`, `lib/features/programs/presentation/views/program_review_view.dart:640-710`, `lib/design_system/components/hx_sheet.dart:90-105`. |
| **FIX-03** | Active workout input focus hides and un-focuses navigation bar, Finish, and Add buttons simultaneously with hit-testing disabled. | `lib/features/shell/main_scaffold.dart:200-210, 280-318`, `lib/features/workouts/presentation/views/active_workout_view.dart:370-400, 475-485`, `lib/features/workouts/presentation/widgets/active_exercise_card.dart:1550-1630`. |
| **FIX-04** | Calendar day detail launches scheduled workouts by explicit `scheduleId`, cleanly differentiating Start from Resume and switching tabs. | `lib/features/programs/presentation/sheets/day_detail_sheet.dart:190-205, 405-445`, `lib/features/workouts/data/scheduled_workout_service.dart:130-198`. |

</phase_requirements>

---

## Detailed Findings by Requirement Area

### 1. FIX-01: Program Generator 8×3 Dynamic Effort Regression

#### The Root Cause
In `SmartProgramPlanner`:
1. `_stressRole` handles day role mapping. In certain splits or day label variations (such as `full_body_linear`, `fullBodyAb`, or `upper_lower_full_body`), `DayStressRole.dynamicTechnique` was either assigned or fallback logic treated the day in a manner where `_methodFor` or day role overrides selected `SlotTrainingMethod.dynamicEffort`.
2. Even more critically, in `PlannedSessionResolver._resolvePrescription`:
   ```dart
   final methodTemplate = switch (method) {
     SlotTrainingMethod.dynamicEffort => SlotPrescription.builtIns.firstWhere(
       (p) => p.name.startsWith('Dynamic Effort'),
     ),
     ...
   };
   ```
   `SlotPrescription.builtIns.firstWhere((p) => p.name.startsWith('Dynamic Effort'))` builds:
   - 8 sets × 3 reps @ 55% 1RM with 60s rest.
3. When `ProgramReviewView` displays an exercise row, it renders:
   ```dart
   '${item.row.targetSets} sets · $reps'
   ```
   In `ProgramDayExercises`, `targetSets` was populated with `3` from `_targetFor`. Thus, review displayed "3 sets", but when the user hit "Start Workout", `PlannedSessionResolver` expanded the prescription into 8 working sets!
4. **Resolution Strategy:**
   - In `SmartProgramPlanner._methodFor`: Enforce a hard constraint: if `experience == ExperienceLevel.novice` or `model == PeriodizationModel.linear`, never return `SlotTrainingMethod.dynamicEffort`. If `stressRole == DayStressRole.dynamicTechnique`, map to `SlotTrainingMethod.technique` or `SlotTrainingMethod.straightSets`.
   - In `SmartProgramPlanner._createStableSlots`: Validate any explicit method overrides in `configuration.mainMethodByDayLabel`. If the user is novice and linear, ignore or forbid `SlotTrainingMethod.dynamicEffort` unless an explicit opt-in flag is present.
   - In `PlannedSessionResolver._resolvePrescription`: Add a safeguard: if `model == PeriodizationModel.linear` or if the program's `experienceLevel == 'novice'`, do not expand `dynamicEffort` into 8×3 speed sets unless explicitly configured. Fall back to standard straight sets matching `explicit.targetSets`.
   - Ensure `ProgramReviewView` and `PlannedSessionResolver` agree on set counts.

---

### 2. FIX-02: Replacement Modal Background Transparency

#### The Root Cause
1. Herculex defines `scaffoldBackgroundColor: Colors.transparent` in `AppTheme` (`lib/design_system/theme/app_theme.dart:77`) to allow ambient theme gradients (`backgroundGradient`) to show through screen scafolds.
2. In `SmartSubstitutionSheet` (`lib/features/workouts/presentation/sheets/smart_substitution_sheet.dart:85-92`):
   It builds a custom `DraggableScrollableSheet` with a `Container(decoration: BoxDecoration(color: AppColors.surfaceContainer, ...))` displayed via `showModalBottomSheet(backgroundColor: Colors.transparent, ...)`.
   In light mode or dynamic theme switches, relying on `AppColors.surfaceContainer` (static brightness) rather than `context.hx.surfaceContainer` or `HxSheet` can cause theme desynchronization.
3. In `ExerciseReplacementSheet` (`program_review_view.dart:702`):
   It uses `HxSheet(scrollable: false, ...)`, but the candidate items inside the sheet used `AppColors.surfaceContainerLowest` without enforcing opaque backdrop material on the sheet wrapper.
4. **Resolution Strategy:**
   - Migrate `SmartSubstitutionSheet` to use canonical `HxSheet` (or `HxSheet.show`) with `context.hx.surfaceContainer`.
   - Ensure the outer sheet uses `Material(color: context.hx.surfaceContainer, elevation: ...)` and full opacity in both dark and light theme modes.
   - Add widget tests verifying that neither replacement sheet contains transparent background containers when rendered in light or dark theme contexts.

---

### 3. FIX-03: Active Workout Keyboard Obstruction & Control Disabling

#### The Root Cause
1. In `MainScaffold` (`lib/features/shell/main_scaffold.dart:204-207`):
   ```dart
   final hideWorkoutChrome =
       index == 2 &&
       hasActiveSession &&
       View.of(context).viewInsets.bottom > 0;
   ```
2. In `ActiveWorkoutView` (`lib/features/workouts/presentation/views/active_workout_view.dart:478-479`):
   ```dart
   bool _keyboardOpen(BuildContext context) =>
       View.of(context).viewInsets.bottom > 0;
   ```
3. Timing discrepancy:
   - When a user taps a weight or reps `TextField` in `ActiveExerciseCard`, the `FocusNode` gains focus *immediately*, but `View.of(context).viewInsets.bottom` remains `0` until the operating system animates the software keyboard upward (~250ms latency).
   - During this window, the Finish button, Add Exercise button, and Bottom Navigation Bar remain fully clickable and hit-testable. If a user quickly taps to reposition their cursor or tap another field near the bottom, they can accidentally trigger Finish Workout or tab switching.
   - Furthermore, `MainScaffold` and `ActiveWorkoutView` calculate `viewInsets` independently without a shared state provider.
4. **Resolution Strategy:**
   - Create a shared Riverpod provider `activeWorkoutInputFocusedProvider` (or `keyboardObstructionActiveProvider`).
   - Listen to set-entry input focus events in `ActiveExerciseCard` (weight, reps, rpe) and update the provider on focus change.
   - When either `activeWorkoutInputFocusedProvider` is true OR `viewInsets.bottom > 0`:
     - `MainScaffold` hides `HxNavBar`, sets `bottom: -120`, `IgnorePointer(ignoring: true)`, `ExcludeSemantics(excluding: true)`.
     - `ActiveWorkoutView` hides floating action bar (Finish & Add buttons), sets `bottom: -140`, `IgnorePointer(ignoring: true)`, `ExcludeSemantics(excluding: true)`.
   - When unfocused, both restore smoothly with matching animation curves.

---

### 4. FIX-04: Calendar Day Detail Launching & Tab Navigation

#### The Root Cause
1. `DayDetailSheet._start()` (`lib/features/programs/presentation/sheets/day_detail_sheet.dart:406-418`):
   ```dart
   Future<void> _start(BuildContext context, WidgetRef ref) async {
     final navigator = Navigator.of(context);
     final service = ref.read(scheduledWorkoutServiceProvider);
     try {
       await service.startScheduledWorkoutById(row.id);
       navigator.pop();
     } on StateError catch (error) { ... }
   }
   ```
   - When `_start()` finishes, it pops the sheet, but does NOT switch the home tab to Tab 2 (`WorkoutsView`), leaving the user stuck on the calendar or profile view instead of transitioning them to the workout they just started/resumed!
2. `ScheduledWorkoutService.startScheduledWorkoutById()` (`scheduled_workout_service.dart:154-198`):
   - It checks `today.schedule.dateIso != _dateIso(_clock.now())`. If it is scheduled for today, it starts or resumes the workout.
   - When resuming (`linked != null && linked.endedAt == null`), it returns the existing `linked.id` without re-materializing.
   - However, if the sheet did not switch tabs, resuming felt unresponsive or ambiguous to the user.
3. **Resolution Strategy:**
   - In `DayDetailSheet._start()`: after successfully calling `service.startScheduledWorkoutById(row.id)`, pop the modal sheet AND switch `mainTabIndexProvider` to `2`:
     ```dart
     ref.read(mainTabIndexProvider.notifier).state = 2;
     ```
   - Verify that `startScheduledWorkoutById` guarantees idempotency: never create duplicate `WorkoutSessions` or overwrite `completedSessionId` on resume.
   - Ensure `_viewWorkout` continues to use `previewScheduledWorkout` and does not mutate any database state.

---

## Validation Architecture

The phase must be verified with automated unit and widget tests:

1. **Test Suite 1: Program Generator Guardrails (`test/smart_program_planner_test.dart` & `test/planned_session_resolver_test.dart`)**
   - Assert that a novice linear full body plan (`SplitType.fullBodyLinear`, `PeriodizationModel.linear`, `ExperienceLevel.novice`) never assigns `DayStressRole.dynamicTechnique` to any day.
   - Assert that no `ProgramDayExercises` row has `trainingMethod == 'dynamic_effort'`.
   - Assert that resolving sessions via `PlannedSessionResolver` for novice linear programs produces straight sets (e.g. 3 sets) and never 8×3 Dynamic Effort sets.
   - Assert that `ProgramReviewView` and `PlannedSessionResolver` report identical set counts.

2. **Test Suite 2: Replacement Modal Styling (`test/widgets/exercise_replacement_sheet_test.dart`)**
   - Render `ExerciseReplacementSheet` and `SmartSubstitutionSheet` under both `Brightness.light` and `Brightness.dark`.
   - Assert the top-level container background is opaque `surfaceContainer` (alpha == 255) and not `Colors.transparent`.
   - Assert presence of `HxSheet` structural elements (grab handle, title, padding).

3. **Test Suite 3: Keyboard Obstruction & Shell Synchronization (`test/widgets/active_workout_keyboard_test.dart`)**
   - Mount `MainScaffold` and `ActiveWorkoutView` with an active session.
   - Simulate focus on a weight input field: verify `HxNavBar` and floating action buttons (Finish/Add) are immediately hidden (`bottom < 0`), ignored by pointer events (`IgnorePointer.ignoring == true`), and excluded from semantics.
   - Simulate unfocus: verify all controls return to visible positions and pointer events are enabled.

4. **Test Suite 4: Calendar Schedule Launch & Tab Transition (`test/scheduled_workout_service_test.dart` & `test/day_detail_sheet_test.dart`)**
   - Schedule two workouts on the same day (`scheduleId: 101`, `scheduleId: 102`).
   - Launch `scheduleId: 102`: assert that session 102 is materialized and linked, not session 101.
   - Call resume on an in-progress scheduled workout: assert returned `sessionId` is identical and no duplicate `WorkoutSessions` row is created.
   - In `DayDetailSheet`: assert that tapping "Start workout" or "Resume workout" triggers `startScheduledWorkoutById(row.id)` and sets `mainTabIndexProvider` to `2`.
   - Assert that "View workout" generates `_WorkoutPlanPreviewSheet` without modifying `WorkoutSessions` count.

---

## Architectural Summary & Plan Decomposition

To deliver Phase 15 with zero regressions and clean verification, the work decomposes into 3 focused plans:

- **Plan 15-01 (FIX-01): Program Generator Prescription Guardrails & Set Parity**
  - Update `SmartProgramPlanner` to prevent `dynamicEffort` on novice/linear plans.
  - Update `PlannedSessionResolver` fallback logic to prevent accidental 8×3 speed prescriptions.
  - Ensure `ProgramReviewView` set counts match `PlannedSessionResolver`.
  - Fix test harness in `smart_program_planner_test.dart` to seed catalog metadata properly.

- **Plan 15-02 (FIX-02 & FIX-03): Replacement Sheet Opacity & Active Workout Keyboard Shell Synchronization**
  - Standardize `SmartSubstitutionSheet` and `ExerciseReplacementSheet` on opaque `HxSheet` with `context.hx.surfaceContainer`.
  - Implement shared keyboard/focus obstruction provider between `MainScaffold` and `ActiveWorkoutView`.
  - Synchronize immediate hiding, hit-testing disabling, and semantic exclusion for bottom nav, Finish, and Add buttons.

- **Plan 15-03 (FIX-04): Calendar Day Detail Schedule Launching & Session Idempotency**
  - Audit and harden `ScheduledWorkoutService.startScheduledWorkoutById` and `previewScheduledWorkout`.
  - Update `DayDetailSheet` to transition user to Workouts tab (`mainTabIndexProvider = 2`) on Start/Resume.
  - Add comprehensive tests for same-day multiple schedules, resume idempotency, and read-only preview.
