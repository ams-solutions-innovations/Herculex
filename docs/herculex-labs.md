# Herculex Labs

Labs is a device-only personal observation and experiment module. Open it from
Insights or add the Herculex Labs card through dashboard customisation. The build
flag `--dart-define=HERCULEX_LABS=false` disables the feature; it is available by
default but performs no analysis until the user enables selected categories.

## Data and privacy

Versioned Labs records use the `herculex_labs_v1_` preferences namespace, matching
the existing supplement tracker storage approach. Original trackers remain the
source of truth. Records cover category/history/AI consent, optional daily context,
supplement product-definition changes and intake dose snapshots, diet/change
periods, experiment definitions and immutable report revisions. Labs records are
not registered for Supabase sync. PDFs live in the private documents `labs/`
directory, which is also included in account deletion.

Revocation gates collection, source adapters, rendering, export and pending report
jobs. Narrowing consent clears derived report snapshots and local PDFs. A privacy
epoch invalidates an in-flight report even when consent is subsequently restored
to the same settings. Separate controls delete reports or all Labs state.

Daily supplement intake retains the product and dose recorded at the time of the
tick, including nutrient composition. Editing a definition or toggling an old
intake does not rewrite its dose. A backdated tick without a prior snapshot, or a
legacy tick, confirms use but has unknown dose. An absent tick is unknown, not
non-use. The underlying tracker still represents one checklist dose per day;
Labs does not invent additional doses or ingredient quantities.

## Analysis contract

Pure Dart analysis operates on normalised observations with source identity,
timestamp, units, stratum and recorded/self-reported/estimated quality. Completed
working sets are resolved through the existing effective-load machinery. e1RM
uses the Epley estimate for standard rep-based sets of 1–10 reps; it remains an
estimate. Equipment, accessories and recorded effort separate strength series.
Daily summaries prevent treating individual sets as independent experiments.

Available descriptions include load/repetition/set progression per comparable
exercise, estimated strength, rep ranges, primary-muscle working sets, advanced
set and superset shares, duration/density, nutritional totals, protein per kg
when recent weight is consented, completed fasts, sleep, body measurements,
physique check-in availability, supplement doses and optional daily context.
Unsupported telemetry is not fabricated. Actual rest duration, tempo, meal
consumption times and HRV are not inferred from planned values or logging times.
Photographic check-ins never identify which exercise caused a physique change.

Descriptive comparisons require three observed days in each calendar half.
Exploratory associations use a fixed catalog, at most 180 days of history,
prespecified day lags, at least eight weekly blocks, actual observation-time
detrending, deterministic two-week block permutations, moving-block bootstrap
intervals and Benjamini-Hochberg correction across tested questions. Coverage
selects a comparable strength stratum before testing; outcomes do not select the
most favourable stratum. Screening thresholds are product defaults, not clinical
validation. Simultaneous routines and residual carryover remain limitations.

Optional experiments freeze a baseline description, one planned change, outcome,
direction and meaningful target before a 14-day baseline and 14-day change phase.
Evaluation is descriptive, requires comparable observations in each phase and
does not mark a target achieved until the review date. Stopped experiments censor
later observations and do not claim target success. Supplements and diets remain
user-directed changes, not prescribed start/stop trials.

Diet periods record a goal and show intake coverage, weight changes and reported
hunger. Minimum screening coverage is 14 days, ten intake days and four weigh-in
days. Missing weigh-ins or incomplete logs cannot produce a supported comparison,
and a single period never establishes a best diet.

## Reports and optional AI

Reports cover local calendar days 1–15 and 16–month end, with exclusive stored end
boundaries. App startup/resume and a best-effort foreground timer catch up completed
periods. Mobile background suspension may delay generation until the next app
run. The first period is marked partial where applicable. Unchanged snapshots
are idempotent; changed historical data produces a new revision.

The same deterministic findings feed the app and PDF. Analysis and PDF layout
run in isolates; fonts are bundled for offline use and Slovenian characters.
Exports include graphs, support labels, coverage, intervals, changes, experiments,
limitations and method references. No external PDF rendering service is involved.

AI is optional, requires separate consent, a category selection, an exact
aggregate payload preview and a user-triggered send. `labs_report` extends the
existing authenticated Gemini proxy with its own five-per-day default quota
(`GEMINI_LIMIT_LABS_REPORT`). The server requires `labs_summary_v1` consent and
whitelists aggregate fields. Raw observations, photos, product names and notes
are excluded. Client validation rejects causal language and numeric AI claims;
AI cannot modify deterministic results. Unavailable AI leaves local analysis and
PDFs usable. The updated `gemini-analyze` function must be deployed separately
before the optional AI action works against an existing deployment.

## Verification

- `flutter test test/features/labs` covers synthetic signals/trends, sparse data,
  consent, historical doses, diets, experiments, real database adapters, report
  idempotence/revisions, cancellation, AI guards, PDF and light/dark mobile UI.
- Related dashboard, supplement notification and weekly-report wipe tests protect
  the integration seams.
- `deno test --allow-env --allow-read --allow-net
  supabase/functions/gemini-analyze/labs_guard_test.ts
  supabase/functions/gemini-analyze/weekly_report_test.ts` checks server contracts.
- Visual QA fixtures are synthetic, generated under `outputs/labs-*`; they are
  not user reports. `outputs/labs-qa-report.pdf` is the export layout fixture.

The repository's existing custom-lint analysis plugin can crash on this Windows
runtime. Scoped analysis can be checked with an isolated Flutter-lints config;
do not remove the repository-wide plugin to hide that environment problem.
