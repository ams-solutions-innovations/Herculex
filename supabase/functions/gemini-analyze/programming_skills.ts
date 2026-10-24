// Runtime coaching skills for Herculex, not Codex development skills.
// Curated from The Bodybuilding Programming Blueprint v2.0 (2026-09-29),
// Parts III–VII and X–XI. The original document is never sent to Gemini.
// Numeric prescriptions stay in the deterministic Dart planner.
export const PROGRAMMING_SKILLS_VERSION = "blueprint-2-skills-1";

export interface ProgrammingSkill {
  id: string;
  title: string;
  chapters: string;
  ruleIds: readonly string[];
  instruction: string;
}

const skill = (
  id: string,
  title: string,
  chapters: string,
  ruleIds: string[],
  instruction: string,
): ProgrammingSkill => ({ id, title, chapters, ruleIds, instruction });

export const programmingSkills = {
  foundation: skill(
    "foundation",
    "Schedule and training dose",
    "9–18, 35, 45–48",
    [
      "SPLIT-DAYS-01",
      "SPLIT-DAYS-02",
      "SPLIT-DAYS-03",
      "SPLIT-DAYS-04",
      "VOLUME-START-01",
      "EFFORT-DEFAULT-01",
      "VALIDATE-PLAN-01",
    ],
    `Select the simplest feasible architecture from actual available days, session
time, goal, equipment and training experience. Two days normally means full body
A/B; three means full body A/B/C or upper/lower/full body; four usually means
upper/lower; five or six can support PPL if preferred and recoverable. These are
coaching defaults, not evidence that one split is universally best. Do not add
weekly work merely because visits increase. Preserve push, pull, knee and hinge
coverage and stated muscle priorities. Appearance does not establish experience.
New or novice trainees need stable exercises, practice and a technique buffer.
The engine validates actual time, equipment, pain exclusions, volume and effort.
Use only its canonical split/model vocabulary; do not invent unsupported methods.`,
  ),

  hypertrophy: skill(
    "hypertrophy",
    "Muscle growth",
    "9–17, 22, 38",
    [
      "VOLUME-START-01",
      "REPS-GOAL-01",
      "PROGRESSION-DOUBLE-01",
    ],
    `Choose a sustainable muscle coverage schedule with stable benchmark lifts,
complementary joint actions and priority muscles placed early. Simple double
progression is usually sufficient until comparable logs justify more complexity.
Periodization names alone do not establish superior hypertrophy. Compare local
muscle progress, adherence and fatigue across several weeks. Add priority work by
reallocating lower-priority work, not by automatically expanding every session.`,
  ),

  strength: skill(
    "strength",
    "Strength and main lift practice",
    "10–11, 19–20",
    [
      "REPS-GOAL-01",
      "REST-PERFORMANCE-01",
      "PROGRESSION-DOUBLE-01",
    ],
    `Protect specific main-lift practice, complete warmup ramps and sufficient rest.
Use linear/simple progression when it still works; consider a defined block for
experienced trainees with a test or peak. Separate demanding exposures by recovery
needs. Keep main lift benchmarks stable. Never replace heavy squat/hinge work with
drop sets or failure work to satisfy a short time budget; reduce assistance first.`,
  ),

  powerbuilding: skill(
    "powerbuilding",
    "Strength with hypertrophy assistance",
    "18–20, 25",
    [
      "REST-PERFORMANCE-01",
      "SPECIALIZE-PRIORITY-01",
    ],
    `Coordinate heavy benchmark practice with moderate hypertrophy assistance.
Concurrent heavy/moderate day roles can retain both qualities. Upper/lower fits
four visits; full body or upper/lower/full body can fit fewer. Main lift methods
do not apply to every accessory. Compress only eligible assistance when time is
short and keep strength rest and technique quality.`,
  ),

  athletic: skill(
    "athletic",
    "Athletic and concurrent sport",
    "20, 34, 41",
    [
      "CONCURRENT-SPORT-01",
      "RECOVERY-ADJUST-01",
    ],
    `Keep the stated sport/performance outcome primary. Put speed and technical
practice before fatiguing assistance. Coordinate endurance and lower-body lifting
instead of treating hard intervals like easy walking. Use concurrent day roles
when appropriate; leave sport demands as uncertainty when unknown. Do not add
failure, drop sets or fatigue circuits to technical/power work.`,
  ),

  linear: skill(
    "linear",
    "Stable linear progression",
    "19",
    [
      "PROGRESSION-DOUBLE-01",
      "PROGRESSION-PLATEAU-02",
    ],
    `Use when repeatable main-lift progression or a simple strength block fits.
Keep main lifts fixed across the block; assistance may rotate on the engine's
slower cadence. Load changes follow comparable performance and readiness rather
than a compulsory weekly increase. A single bad exposure is not a plateau.`,
  ),

  concurrent: skill(
    "concurrent",
    "Heavy and moderate exposures",
    "19–20",
    [
      "CONCURRENT-SPORT-01",
      "REST-PERFORMANCE-01",
    ],
    `The app's concurrent model organizes heavy, moderate and technique exposures
within the week; it does not itself imply endurance sessions. Use intensity,
volume, dynamic_technique or mixed day roles to explain distinct purposes. Keep
benchmarks long enough to compare performance. Main lifts normally rotate every
four weeks and assistance every three, subject to anchor locks and user overrides.`,
  ),

  block: skill(
    "block",
    "Defined training phases",
    "19, 21",
    [
      "SPECIALIZE-PRIORITY-01",
      "RECOVERY-ADJUST-01",
    ],
    `Use for an experienced trainee's defined specialization or strength peak.
Explain what the phase aims to improve and how it will be judged. In the app's
block model, accumulation favors volume-friendly variants, transmutation favors
competition-adjacent variants and realization locks the exact main lift. Keep
exercises stable within a phase; avoid changing all variables at each boundary.
Do not impose a strength peak merely because a hypertrophy user is advanced.`,
  ),

  conjugate: skill(
    "conjugate",
    "Max effort and planned variation",
    "20",
    [
      "LEVEL-ADVANCED-04",
      "EFFORT-FAILURE-02",
    ],
    `Choose max_effort only for an experienced strength-focused user with a reason
for planned main-lift variation. Never infer readiness from photographs. The
engine permits at most one max-effort slot per session, two per week, and requires
three suitable variants and recovery spacing. Main variants normally rotate every
two weeks; supplemental every three and accessories every four. A daily heavy
top set is submaximal technical work, not forced failure. Novices use simpler
practice/progression. Never bypass a small pool by inventing exercises.`,
  ),

  calisthenics: skill(
    "calisthenics",
    "Bodyweight and mixed training",
    "7–8, 13, 16, 36",
    [
      "PROGRESSION-DOUBLE-01",
      "EFFORT-DEFAULT-01",
    ],
    `Route both calisthenics and mixed calisthenics/weights here. Progress a stable
movement through repetitions, assistance, external load or a controlled leverage
change. Respect the engine's prerequisites and skill level for each movement.
Do not equate bodybuilding experience with handstand, ring or muscle-up skill.
Technical skills and compound bodyweight movements retain a technique buffer.
Do not recommend weighted drop sets when equipment or a safe progression is absent.`,
  ),

  basic: skill(
    "basic-equipment",
    "Limited equipment",
    "7–8, 36",
    [
      "VALIDATE-PLAN-01",
      "PROGRESSION-DOUBLE-01",
    ],
    `Build coverage from the actual available equipment. Use repetitions, practical
load increments and exercise-family substitutions before adding complexity.
Do not require a cable stack, machine, fast plate changes or partner assistance
for time-saving methods when the equipment context cannot support them.`,
  ),

  crossfit: skill(
    "crossfit",
    "Conditioning first",
    "20, 34, 36",
    [
      "CONCURRENT-SPORT-01",
      "VALIDATE-PLAN-01",
    ],
    `Use the crossfit split for crossfit style. The deterministic engine selects
warmup/skill/strength/metcon/cooldown structure and scaled AMRAP, EMOM or For Time
work. It owns time caps, prerequisites, movement complexity and equipment gates.
Use day roles to distribute stress. Do not convert metcon or skill work to muscle
failure/drop-set prescriptions to shorten the session.`,
  ),

  gpp: skill(
    "gpp",
    "Two full body sessions with optional GPP",
    "18, 20, 34",
    [
      "SPLIT-DAYS-01",
      "CONCURRENT-SPORT-01",
    ],
    `Keep two complementary full-body strength sessions. When includeGppConditioning
is true add the separate simple GPP day using full_body_ab_gpp; when false choose
full_body_ab. Conditioning is low-complexity general preparation, not permission
to add advanced CrossFit skills or a high-fatigue finisher to every strength day.`,
  ),

  lowVolume: skill(
    "low-volume",
    "Brief high effort preference",
    "24–26, 42",
    [
      "STYLE-HEAVY-01",
      "EFFORT-FAILURE-02",
      "VALIDATE-PLAN-01",
    ],
    `Apply when the user explicitly prefers low-volume/high-effort or the selected
time-saving approach is two_to_failure. Favor a small repeatable exercise menu,
logbook progression and complete weekly coverage. The engine may use two working
sets after a separate light primer on eligible stable isolation work. Failure is
optional and restricted by experience, movement safety and recovery. Keep a buffer
on heavy/technical lifts. Do not claim universal one-set superiority, guarantee
progress each visit or schedule arbitrarily infrequent training.`,
  ),

  arnold: skill(
    "arnold-inspired",
    "Variety and weak point preference",
    "23, 25",
    [
      "STYLE-ARNOLD-01",
      "SPECIALIZE-PRIORITY-01",
    ],
    `Use only when the profile explicitly requests arnold_inspired. Retain
complementary angles, priority placement and enjoyable variety while keeping a
stable benchmark and realistic session budget. Historical extreme volumes and
forced repetitions are not defaults. Optional supersets need compatible equipment
and preserved performance. When time is short, reduce lower-priority variety
instead of cramming the historical routine into a compressed session.`,
  ),

  timeSaving: skill(
    "time-saving",
    "Shorter sessions",
    "10–12, 24–26, 35, 42",
    [
      "EFFORT-FAILURE-02",
      "REST-PERFORMANCE-01",
      "VALIDATE-PLAN-01",
    ],
    `Load when the requested session is at most 45 minutes, the user asks for
shorter sessions, or time-saving techniques are enabled. The time budget is a
constraint, not a mandate for maximal effort. Reduce lower-priority work first and
distribute coverage across available days. Advanced techniques require the
allowTimeSavingSetTechniques opt-in. The deterministic engine chooses among
myo_reps, drop_sets and two_to_failure from the selected timeSavingTechnique,
experience and actual exercise. Drop sets use a practical load reduction on an
eligible isolation; two_to_failure uses a separate light warmup primer and two
technical-failure working sets on a stable isolation for experienced users.
Never count the primer as hypertrophy work. Novices keep straight controlled work.
Heavy squats, hinges, technical skills, strength peaks and conditioning do not
receive these methods. Preserve graded compound warmups and adequate rest. Do not
promise equal stimulus for every compressed technique or an exact session duration.
Describe this strategy in day rationales without emitting numeric prescriptions.`,
  ),

  rotation: skill(
    "exercise-rotation",
    "Stable benchmarks and substitutions",
    "7–8, 13, 19–20, 48",
    [
      "PROGRESSION-PLATEAU-02",
      "RECOVERY-MISSED-02",
    ],
    `Change an exercise for pain, equipment, preference, a repeated plateau or a
planned phase, not random novelty. Preserve movement family, target muscle and
loading feasibility. Compare like with like; variation-specific records remain
separate. The Dart rotation policy owns cadence: linear main lifts stay fixed,
concurrent main lifts rotate slowly, block lifts lock within phases and max-effort
variants rotate sooner. User core-lift anchors and safety gates take priority.
Do not interpret a missed workout as permission to skip benchmarks or double work.`,
  ),
} satisfies Record<string, ProgrammingSkill>;

/** Routing uses structured app choices, never instructions hidden in userNote. */
export function selectProgrammingSkills(
  profile: Record<string, unknown>,
): ProgrammingSkill[] {
  const selected = [programmingSkills.foundation];
  const add = (value: ProgrammingSkill) => {
    if (!selected.includes(value)) selected.push(value);
  };
  const goal = profile.goal;
  add(
    goal === "strength"
      ? programmingSkills.strength
      : goal === "powerbuilding"
      ? programmingSkills.powerbuilding
      : goal === "athletic"
      ? programmingSkills.athletic
      : programmingSkills.hypertrophy,
  );
  const model = profile.periodizationModel;
  if (model === "linear") add(programmingSkills.linear);
  else if (model === "concurrent") add(programmingSkills.concurrent);
  else if (model === "block") add(programmingSkills.block);
  else if (model === "max_effort") add(programmingSkills.conjugate);
  // Give the recommender the relevant alternatives, not just the current picker.
  if (profile.experience === "novice") add(programmingSkills.linear);
  else if (goal === "powerbuilding" || goal === "athletic") {
    add(programmingSkills.concurrent);
  } else if (goal === "strength") {
    add(programmingSkills.linear);
    if (profile.experience === "advanced") {
      add(programmingSkills.block);
      add(programmingSkills.conjugate);
    }
  }
  switch (profile.trainingStyle) {
    case "calisthenics":
    case "mixed_calisthenics_weights":
      add(programmingSkills.calisthenics);
      break;
    case "basic":
      add(programmingSkills.basic);
      break;
    case "crossfit":
      add(programmingSkills.crossfit);
      break;
    case "full_body_2x_gpp":
      add(programmingSkills.gpp);
      break;
  }
  if (
    profile.programmingPreference === "low_volume" ||
    profile.timeSavingTechnique === "two_to_failure"
  ) {
    add(programmingSkills.lowVolume);
  }
  if (profile.programmingPreference === "arnold_inspired") {
    add(programmingSkills.arnold);
  }
  if (
    (typeof profile.workoutDurationMinutes === "number" &&
      profile.workoutDurationMinutes <= 45) ||
    (typeof profile.averageSessionMinutes === "number" &&
      profile.averageSessionMinutes <= 45) ||
    profile.preferShorterSessions === true ||
    profile.allowTimeSavingSetTechniques === true
  ) {
    add(programmingSkills.timeSaving);
  }
  add(programmingSkills.rotation);
  return selected;
}

export function programmingSkillInstruction(
  skills: readonly ProgrammingSkill[],
): string {
  return `Herculex runtime programming skills ${PROGRAMMING_SKILLS_VERSION}.
Source: The Bodybuilding Programming Blueprint v2.0, 29 September 2026.
Use the selected skills below for structural decisions. Their method details are
context for the deterministic planner; the program_brief output contract still
forbids exercise lists and numeric prescriptions. App choices and limits are
constraints. Explain uncertainty rather than inventing missing context.\n\n` +
    skills.map((s) =>
      `SKILL ${s.id}: ${s.title}\nBlueprint chapters ${s.chapters}; rules ${
        s.ruleIds.join(", ")
      }.\n${s.instruction}`
    ).join("\n\n");
}

/** Reject conflicting schedules before showing or persisting an AI brief. */
export function validateBriefAgainstProfile(
  brief: Record<string, unknown>,
  profile: Record<string, unknown>,
): void {
  const days = profile.daysPerWeek;
  if (
    typeof days === "number" && Number.isInteger(days) && days >= 1 && days <= 7
  ) {
    const roles = brief.dayRoles as { dayIndex: number }[];
    const indices = new Set(roles.map((r) => r.dayIndex));
    if (
      roles.length !== days || indices.size !== days ||
      roles.some((r) =>
        !Number.isInteger(r.dayIndex) || r.dayIndex < 0 || r.dayIndex >= days
      )
    ) {
      throw new Error(
        "Program brief does not match the selected training days.",
      );
    }
  }
  if (
    profile.experience === "novice" && brief.periodizationModel === "max_effort"
  ) {
    throw new Error(
      "Max Effort is not appropriate for novice program generation.",
    );
  }
  if (profile.trainingStyle === "crossfit" && brief.splitType !== "crossfit") {
    throw new Error(
      "Program brief does not match the selected CrossFit style.",
    );
  }
  if (profile.trainingStyle === "full_body_2x_gpp") {
    const expected = profile.includeGppConditioning === false
      ? "full_body_ab"
      : "full_body_ab_gpp";
    if (brief.splitType !== expected) {
      throw new Error(
        "Program brief does not match the selected GPP structure.",
      );
    }
  }
}
