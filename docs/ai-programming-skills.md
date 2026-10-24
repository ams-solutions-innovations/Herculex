# Herculex AI programming skills

Implemented 24 October 2026. These are runtime coaching modules loaded into the
Herculex AI system instruction for `program_brief`. The application selects
relevant modules from structured settings and sends their instructions with each
request. It does not upload the full textbook or train the model on the book.

## Source and versions

The source is **The Bodybuilding Programming Blueprint**, v2.0, 29 September
2026, particularly chapters 9–26, 35–48 and worked example 42. The desktop DOCX
was exclusively locked during implementation, so the accompanying 71-page PDF
was read instead. PDF SHA-256:
`0AB580008733F51373A3133A3672A4F3ACFE4294CED1B7ABDC5DFD82E506D3D1`.

The curated modules live in
`supabase/functions/gemini-analyze/programming_skills.ts`. Each carries source
chapters and applicable Blueprint rule IDs. Method details without a specific
rule ID are coaching implementation choices, rather than universal scientific
thresholds.

- Coaching corpus: `kb-2026.10-2`.
- Programming modules: `blueprint-2-skills-1`.
- Responses report `programmingSkillsVersion` and the selected `programmingSkills`.
  These are retained in the existing brief JSON when the user saves a program.

## Selection

| Module | Selected for | Main responsibility |
| --- | --- | --- |
| `foundation` | Every program brief | Days, time, coverage, experience and feasible architecture |
| `hypertrophy` | Hypertrophy or unspecified goal | Stable benchmarks, muscle priorities, sustainable dose |
| `strength` | Strength goal | Main-lift practice, rest, specificity and progression |
| `powerbuilding` | Powerbuilding goal | Heavy practice plus hypertrophy assistance |
| `athletic` | Athletic goal | Performance priority and coordination with other sport |
| `linear` | Linear model, novice, or a strength candidate | Stable main lifts and simple progression |
| `concurrent` | Concurrent model or powerbuilding/athletic candidate | Heavy/moderate/technique day roles |
| `block` | Block model or advanced strength candidate | Phase purpose, specific main lifts and phase boundaries |
| `conjugate` | Max Effort model | Experienced users, suitable variation pool and recovery spacing |
| `calisthenics` | Calisthenics or mixed weights/bodyweight | Prerequisites, assistance, leverage and repeatable skill practice |
| `basic-equipment` | Basic equipment style | Feasible substitutions and practical progression |
| `crossfit` | CrossFit style | Conditioning structure and engine-owned scaling |
| `gpp` | Full body 2× + GPP style | Two complementary strength sessions and optional separate GPP |
| `low-volume` | Two-to-failure preference or API `programmingPreference: low_volume` | Brief focused sessions, coverage and selective effort |
| `arnold-inspired` | API `programmingPreference: arnold_inspired` | Moderate variety, weak-point placement and realistic workload |
| `time-saving` | Short target/observed average, shorter-session preference, or technique opt-in | Feasible assistance compression without overriding movement constraints |
| `exercise-rotation` | Every program brief | Stable benchmarks, model cadence and substitutions |

The current builder exposes goals, exercise styles, periodization and time-saving
approaches. The optional `programmingPreference` API fields load philosophy
guidance; they are not additional builder controls or standalone numeric presets.
User notes do not select modules. The model gets the applicable alternatives for
its goal and experience, then recommends the structural brief within the existing
canonical vocabulary. The server and client reject conflicting day counts,
duplicate/out-of-range day indices, novice Max Effort and CrossFit/GPP conflicts.
AI day roles are applied by session index so repeated Push/Upper labels can have
different roles. Manual role choices still take precedence.

## Input context

The builder supplies goal, experience, weeks, style, available days, schedule,
current periodization, target duration, technique consent and preference, warm-up
and GPP choices, muscle priorities and weekly set caps. Its parameters step offers
**Generate with these settings** to regenerate after changing the initial defaults.

The brief service adds default-gym equipment availability and, when at least
three valid observations exist, the rounded average of up to eight recent finished
ordinary sessions. It looks back 56 days and excludes deleted, future,
micro-workout and implausibly short/long records. The 10–180 minute bounds are
data-quality heuristics. Only the aggregate is sent. Observed duration is context;
the user's selected time remains the planning constraint and does not grant
permission for advanced techniques.

## Shorter sessions in the deterministic planner

The **Time-saving sets** control is explicit consent. Users can choose automatic,
Myo-reps, drop sets, or warm-up plus two sets to technical failure. This choice is
available when creating a block and when rebuilding its remaining weeks.

Automatic compression is considered for targets of 45 minutes or less, or when
the full session exceeds its target plus the existing 10% planning tolerance.
An explicitly selected technique can also be used for a longer target. The
planner accounts for warm-up ramps, unilateral work, mini-sets, drops and equipment
transitions, then trims lower-priority assistance. If the protected main work
still exceeds the budget, its explanation reports the remaining time mismatch.

`TimeSavingPolicy` decides from the actual selected exercise, goal, experience,
set budget and week. Current automatic eligibility is trained hypertrophy or
powerbuilding users, low-CNS isolation work and practical loading equipment.
Novices, strength/power skills, compounds, conditioning, deloads, realization
phases, neck and spinal-isolation work keep ordinary prescriptions.

| Choice | Generated work |
| --- | --- |
| Automatic | Machine/cable isolation uses a drop sequence; suitable dumbbell/band isolation uses Myo-reps |
| Drop sets | Initial controlled set followed promptly by one roughly 20% lighter step; the load hint derives from the preceding completed set |
| Myo-reps | Controlled activation set and three planned mini-sets, recorded separately from the mini-sets actually performed |
| Warm-up + two to failure | One separately flagged light primer and two working sets to technical failure, only on eligible stable machine/cable work |

The 20% reduction, mini-set count and equipment/CNS boundaries are product
heuristics. Compressed work is not represented as proven equivalent to any fixed
number of traditional sets. Primers are excluded from working-set volume. Heavy
free-weight lifts keep their intensity-dependent warm-up ramps. A lighter block
does not gain advanced methods during regeneration.

Generated prescriptions store their method context in existing variant JSON.
At session resolution the method is checked again against the exercise actually
performed, including changes carried from an old block. If eligibility no longer
holds, the session uses controlled straight sets and explains the change.

## Release

Both the Flutter client and `gemini-analyze` must be released to use the complete
feature. Older clients can still request a brief with fewer profile fields;
missing fields do not invent time-saving consent. Database schema changes are
not required. Publishing the current working tree should account for unrelated
local changes before deployment.

## Verification

- 212 targeted Flutter tests passed, covering the builder, brief service,
  planner, prescriptions, duration, session resolution and advanced-set controls.
- 58 backend tests passed, including skill routing and all existing available
  program/check-in/report tests.
- Project analyzer API: 17 changed Dart source files, zero errors and warnings.
  The standard CLI's `custom_lint` plugin fails to start on this host (Windows
  library/AOT errors), so this check used an in-memory options overlay to omit
  that plugin while retaining the project's normal analysis rules. Repository
  analysis settings were not changed. Existing RegExp deprecation infos remain.
- The complete backend directory check is blocked by the pre-existing untracked
  `gemini_transport.ts` / `gemini_transport_test.ts`: TypeScript parameter errors
  and a missing `validateRequestImages` export. The 58-test run excludes that
  unfinished transport test. The programming integration itself type-checks.

No live Gemini requests, database migrations, production deployments or installed
client updates were performed during this implementation.
