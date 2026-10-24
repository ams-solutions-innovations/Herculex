# Calisthenics progression

Implemented on 2026-10-14. The local coaching corpus in
`supabase/functions/gemini-analyze/knowledge_base.ts` is explicitly a placeholder;
it contains no exercise-specific progression prescriptions. The rules below are
authored product defaults informed by the primary sources linked here, not
scientifically validated readiness thresholds.

## User flow

The exercise picker groups authored calisthenics paths before the ordinary
equipment-family grouping. Opening a group shows its levels, the current
recommendation, and a prescription. Search finds individual exercises but opens
the whole available path. Users can choose any level and return to an easier one.
Custom exercises retain their existing behavior.

Pull-ups and dips use assisted → strict → weighted. Push-ups, ring push-ups,
ring rows, handstand push-ups and pistol squats use explicit movement variations.
Bar and ring muscle-ups have independent assisted-strict → strict → weighted
paths. Kipping muscle-up is shown in the bar muscle-up group as a technique
branch; its results never satisfy strict-strength thresholds.

The picker supplies three sets and a target at the lower end of the selected
range, or the next rep/duration/load within the current level. An active workout
shows the progression explanation and an explicit Use action. Existing program
prescriptions remain frozen; choosing a higher level does not rewrite past
workouts or existing scheduled sessions.

New smart-program slots follow the same three-set progression instead of a
generic role-based prescription such as 4 × 8. The rep target is derived from
the athlete's completed history and remains capped at RPE 8; manually authored
templates and program prescriptions retain their selected targets.

Before accepting a suggested higher level, the user confirms controlled,
pain-free full-range performance. A readiness notification appears after a
finished phone workout crosses the threshold. Readiness means **ready to try**,
not guaranteed ability or automatic promotion. Try the lower end of the next
range and return to assistance if movement quality breaks down.

## Evaluation

- Three completed standard working sets at the upper end of the authored range,
  repeated in the last two sessions of that level, at least 24 hours apart.
- Only results within 42 days; future, unfinished and deleted workouts, deleted
  sets, warmups and advanced set techniques do not qualify.
- RPE must be at most 8 when logged. Missing RPE remains unknown; technique is
  confirmed by the user rather than inferred from rep counts.
- The same external load and the same band ID/count/mode signature are required.
  A band variant needs explicitly logged assistance; resistance-mode bands and
  bands attached to a nominal strict set cannot qualify as unassisted strength.
- Muscle-up paths additionally require recent 3 × 5 strict pull-ups and dips
  on the relevant apparatus. Those are conservative app prerequisites, not a
  claim that the athlete can already execute a muscle-up transition.
- Weighted top levels add 1.25 kg after two successful sessions and restart at
  the bottom of the rep range. This is added load, never bodyweight-inclusive
  percentage arithmetic. Band colors are never converted into kilograms.
- Holds progress in two-second steps to a capped working duration. Existing
  full levers, planche and L-sits have duration progression only: the catalog
  lacks reviewed tuck/straddle regressions, so the app does not invent them or
  treat floor and ring execution as equivalent.

Band assistance is a continuum within Level I. Build repetitions with the same
band, then try a lighter band and rebuild; a lighter band is not automatically
equivalent to a strict repetition. Incline height, foot assistance, unilateral
symmetry and technique cannot currently be verified by the logger; keep the
setup constant and meet unilateral targets on both sides.

## Data and integration

`CalisthenicsProgression` is pure Dart; `CalisthenicsProgressionRepository` derives
recommendations from existing synced history and band attachments. No new schema
or remote migration is needed. A stream refreshes the picker and active cards
when history changes. Notification crossings compare history with and without
the finishing session; reopening the picker alone does not send a notification.

Template set metadata has a versioned `calisthenicsPlan` extension containing
the selected equipment variant and optional duration. `PlannedSessionResolver`
preserves it when starting a template. Malformed/unknown metadata is ignored.
Rep/load targets use existing planned columns; timed targets prefill an editable,
uncompleted duration. Local buddy exercise additions receive the same targets;
each buddy's progression is based on their own history.

## Sources and interpretation

- [CrossFit: Strict Before Kipping?](https://www.crossfit.com/pro-coach/strict-before-kipping?topicId=article.20230924200535417)
  supports separating prerequisite strict strength from kipping skill. The app
  therefore does not impose a universal kipping → strict ladder.
- [CrossFit: Strict Muscle-Up Foundations](https://www.crossfit.com/essentials/strict-muscle-up-foundations)
  informs assisted strict practice and transition work as separate from merely
  accumulating kipping repetitions.
- [ACSM: Progression models in resistance training for healthy adults](https://pubmed.ncbi.nlm.nih.gov/19204579/)
  supports progressive resistance and goal-specific rep ranges. Its general load
  guidance is not direct evidence for this app's skill thresholds or 1.25 kg step.
- [GMB: Bodyweight Progressions](https://gmb.io/progressions/)
  informs prioritising movement quality and appropriate variation rather than
  relying on repetition counts alone.

The exact ranges, two-session rule, 24-hour separation, 42-day window and RPE
ceiling are reviewable app policy in `calisthenics_progression.dart`. They do not
replace individual coaching or establish a universal gymnastics level system.

## Validation

48 focused tests passed across the progression engine, repository, level
chooser, existing weighted calisthenics behavior, template/program snapshot
resolver, workout finish flow and exercise library. Tests include explicit
technique confirmation, history exclusions, readiness crossings and template
variant/load preservation.

Full Flutter analysis reported no Dart errors, but existing warnings/info remain.
The custom_lint plugin fails to start on this Windows SDK installation
(`custom_lint_client.dart is not an AOT snapshot`). Structure checking reports
61 existing oversized files; all newly added files are below 600 lines. The
phone UI has widget-test coverage; no device build/deployment was performed.
