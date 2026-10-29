# Workout energy estimation

Implemented 2026-10-28. Entry points: `WorkoutEnergyEstimator` (pure calculation),
`WorkoutEnergyService` (session, measurements and optional Health telemetry),
`FinishWorkoutAction`, and the repository's direct/watch finish path.

## Meaning of the number

The app estimates **active kcal above resting expenditure within the recorded
session**. It does not measure metabolism. The combined model has not undergone
validation against calorimetry; adding more inputs does not establish accuracy.
The conservative discount and downward rounding express a product preference,
not a statistical lower confidence limit or a guarantee against overestimation.

Previously, multiple screens independently used `5 × kg × elapsed hours`,
counted the entire workout as continuous activity, and imposed a 10 kcal minimum.
The new shared model accounts for observed work and bounded recovery separately.
Completing an empty workout yields zero. Saved zero is a valid result.

## Evidence reviewed

* [Mitchell et al., 2024, systematic scoping review](https://doi.org/10.1007/s40279-024-02047-8):
  resistance exercise combines aerobic and anaerobic expenditure. Timing, muscle
  recruitment and recovery matter. The review found no accepted universal field
  method, and commercial wearable energy estimates varied substantially. This
  supports separating work and recovery and reporting an estimate, but does not
  validate this implementation's coefficients.
* [2024 Adult Compendium, conditioning exercise](https://pacompendium.com/conditioning-exercise/):
  published categories include general resistance work (3.5 MET), vigorous
  resistance work (6.0), squat/deadlift work (5.0), light static calisthenics
  (2.8), vigorous calisthenics (7.5), and kettlebell swings (9.8). These are
  population activity categories, not exact kcal per rep or individualized
  measurements. Our work-phase categories below are engineering priors anchored
  to these values, rather than claiming published per-exercise calibration.
* [Qiao et al., 2026, Smith-machine squat prediction](https://pubmed.ncbi.nlm.nih.gov/42017977/):
  load, body mass, peak HR and movement distance informed a model in 51 people
  doing a specific squat protocol. This motivates using load and exercise type,
  but the squat regression is not applied to unrelated exercises. We do not have
  measured movement displacement or mechanical efficiency.
* [Yun et al., September 2026, smartwatch resistance-exercise validation](https://doi.org/10.3390/bioengineering13101099):
  examined wrist HR and calorie estimates against ECG and calorimetry across four
  devices. Reliable HR sensing does not establish reliable inferred kcal. A
  high HR during lifting therefore does not trigger an aerobic calorie formula.
* [Pereira et al., September 2026, rest-interval crossover trial](https://doi.org/10.1038/s41430-026-01819-x):
  with matched lifting volume, 30 s and 180 s rests produced different session
  expenditure. Rest is not metabolically free, but its cost is distinct from
  active lifting. Our recovery curve is an explicit approximation, not a fitted
  equation from this trial.
* [Mifflin et al., 1990](https://pubmed.ncbi.nlm.nih.gov/2305711/): supplies
  resting expenditure predictors from demographics, or alternatively fat-free
  mass. These predictors estimate rest, not the energy cost of lifting.
* [Keytel et al., 2005](https://doi.org/10.1080/02640410470001730089):
  population HR regressions developed during submaximal treadmill/cycle work,
  not resistance training. The female mass coefficient in the original model
  is negative; do not copy versions that change its sign.
* [Lytle et al., 2019](https://doi.org/10.1249/MSS.0000000000001925):
  a demographic/body-composition/volume regression for a prescribed seven-lift
  machine protocol. Its session intercept is inappropriate for arbitrary short
  sessions, isolated exercises, bodyweight movements, and variable rests, so
  it is not used as a universal calorie formula.

## Calculation and assumptions

1. Load only the requested session's non-deleted completed sets, including
   completed warmups. Training analytics retain their existing non-warmup default.
   Sets from other sessions, uncompleted plans, and deleted rows cannot add energy.
2. Prefer valid historical bodyweight measurements on/before the session date
   (up to 180 days old), then a bodyweight snapshot from its sets, then profile
   mass. A missing/invalid mass uses a disclosed internal fallback of 60 kg and
   a larger discount. Body fat must be on/before that date and at most 90 days
   old. Future, deleted, non-finite, and physiologically implausible inputs are
   excluded. The date granularity cannot resolve changes within the same day.
3. Resting kcal/day: if valid BF is available, use `19.7 × FFM + 413`, where
   `FFM = kg × (1 − BF/100)`. Otherwise use Mifflin–St Jeor when age, height and
   biological sex are available. Otherwise use `15.1 × kg + 371`. Divide by 1440.
   These are alternative predictors; sex/age/height are not stacked onto BF as
   arbitrary extra multipliers. BF estimation error remains an input limitation.
4. Prefer logged duration when the exercise supports it. Otherwise estimate rep
   work at 3 s/rep, partials at 1.5 s, negatives at 4 s, and explicitly logged
   pauses at an additional 0–10 s/rep. Actual myo-rep mini-set reps count through
   `ResolvedSet.countedReps`. Planned drops, CNS factors, caps and unlogged reps
   do not invent additional work. Distance-only and console-only entries use
   conservative duration fallbacks. No explicit start-of-set timer is currently
   recorded for ordinary rep sets, so their work duration remains approximate.
5. Place work immediately before completion timestamps. Clip against the
   preceding work interval and session start, reject timestamps outside the
   session, and never charge overlapping work twice. If any completion stamp is
   missing, construct a bounded timeline from performed work and limited rest
   assumptions; scale work down if it cannot fit. Never interpret the full elapsed
   session duration as work.
6. Work-phase gross MET priors: isolation 3.5, upper compounds 5.0, lower compounds
   6.0, static holds 2.8, mobility 2.3, burpees/thrusters 7.5, swings 9.8. For
   ordinary resistance work add `0.5 × clamp(effective kg / body kg, 0, 2)` MET;
   RPE changes this by at most −15%/+5%, and warmups use 85%. Effective load
   includes existing band, chain and bodyweight/assistance rules. These modest
   modifiers are heuristics; a machine stack is not a measurement of joules.
7. Gross work rate is `MET × 3.5 × kg / 200` kcal/min. Subtract individual resting
   rate and clamp at zero. Standard MET is not multiplied by individual RMR;
   [corrected MET](https://pacompendium.com/corrected-mets/) is an intensity ratio,
   not evidence for increasing absolute calories twice.
8. During non-work time only, recovery above rest integrates
   `0.25 × preceding net work rate × (1 − exp(−min(rest seconds, 180)/60))`
   kcal. The time constant, amplitude and 180 s cutoff are conservative product
   assumptions. It stops at the next set or session end. No indefinite idle burn,
   walking-between-machines allowance, or post-session EPOC bonus is added.
9. Console kcal apply only to a metric that actually supports them. Discount the
   console number by 20%, subtract interval resting energy, and take the smaller
   of that result and the time-bounded activity estimate. Never replace the whole
   mixed workout with one cardio interval, or add console and modeled kcal twice.
10. Apply one 10% session discount (20% for fallback mass), then round **down to
    the nearest 5 kcal**. There is no minimum calorie award.

## Heart rate

At finish, existing Health read access is used for session HR samples. Denied,
unavailable, empty or slow (>3 s) telemetry falls back without requesting access.
There is no new raw-HR persistence or cloud sync.

HR can inform only running/treadmill/cycling intervals lasting at least 120 s,
with known sex, age 18–45 and mass 47–120 kg. Ten-second bins deduplicate multiple
sources. At least 60% of the interval must have valid bins; non-finite, outside
interval, below-90-bpm and implausibly high measurements are rejected. The model
blends 20% HR-based net rate and 80% activity-based net rate, bounded to 85–110%
of the activity estimate. These quality gates and blend bounds are policy, not
published calibration. HR never inflates resistance work or idle time.

Live estimates use recorded sets and refresh every 15 s during recovery. Platform
HR is read at finish, so the final aerobic estimate can differ from the live one.

## Integration and limits

Classic and dynamic workout views display `≈… kcal`. Finishing persists the same
result used for Health export. Direct repository/watch finishes also estimate
missing kcal. Editing a completed session's duration recalculates missing caller
energy; extending idle time cannot create hours of exercise. Summary/history
fallbacks use the shared model, and saved zero is respected.

Existing stored/imported kcal retain their source value; without historical
provenance they cannot safely be identified as a particular old heuristic or
rewritten as if measured by the new model. Apple Watch ownership/export behavior
is retained. Historical profile demographics are not versioned, and dated weight
and BF have day-level resolution.

The model does not have measured oxygen exchange, lactate, bar displacement,
cycling watts, treadmill incline, ambient heat, medication effects, individual
HR–VO2 calibration or precise contraction durations. It does not invent
coefficients for those unknowns. Field accuracy would need a representative
calorimetry dataset including recovery and anaerobic contribution; software
regression tests establish behavior, not physiological accuracy.

## Verification

`workout_energy_estimator_test.dart` covers idle saturation, rounding, invalid
inputs, work/rest boundaries, reps/load/RPE, exercise categories, actual warmups,
partial/pause/myo-reps, mixed cardio, console double counting, and HR eligibility.
`workout_energy_service_test.dart` covers dated measurements, stale/future/deleted
inputs, default analytics behavior, and persistence through direct/watch finish.
Existing finish-flow, watch sync, Health, summary and metric suites guard integration.
