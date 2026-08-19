/// Everything Hercul is allowed to know, resolved into numbers.
///
/// Hercul adds no analytics. Every value here is already computed somewhere in
/// the app — `CnsTrends`, `MuscleRecoveryV3`, `WeeklyMuscleVolume`,
/// `BalanceAnalyzer`, `DailyTotals` against `MacroTargets`, `BodyMeasurements`,
/// `TrainingSnapshot` — and this type is the flat, provider-free view of it that
/// the rule evaluator reads. Keeping it pure is what makes a rule testable
/// without a database.
///
/// **A missing signal is null, never zero.** Zero protein and "no food logged
/// yet" would otherwise be the same fact, and Hercul would greet a fresh install
/// by telling the user they are undereating. Rules declare what they need in
/// `requires` and are skipped when it is absent.
library;

/// A signal that varies by subject — a muscle group, an exercise slug — rather
/// than being a single number for the whole account.
///
/// `volume.weeklySets` is meaningless without knowing *which* muscle, so those
/// live keyed by argument instead of flattened into one key per muscle.
typedef SignalSeries = Map<String, double>;

class HerculContext {
  /// Single-value signals, keyed `namespace.name`.
  final Map<String, double> scalars;

  /// Argument-keyed signals, `namespace.name` -> argument -> value.
  final Map<String, SignalSeries> series;

  /// Non-numeric signals — `profile.goal`, `cns.status`, `profile.sex`.
  final Map<String, String> labels;

  /// Evaluation time, injected so cooldowns and "days since" are testable.
  final DateTime now;

  const HerculContext({
    this.scalars = const {},
    this.series = const {},
    this.labels = const {},
    required this.now,
  });

  /// Numeric value for [signal], or null when it was never resolved.
  double? number(String signal, [String? arg]) {
    if (arg == null) return scalars[signal];
    return series[signal]?[arg];
  }

  String? label(String signal) => labels[signal];

  /// True when the signal has a value — the check behind a rule's `requires`.
  bool has(String signal, [String? arg]) =>
      number(signal, arg) != null || (arg == null && labels[signal] != null);

  HerculContext copyWith({
    Map<String, double>? scalars,
    Map<String, SignalSeries>? series,
    Map<String, String>? labels,
    DateTime? now,
  }) =>
      HerculContext(
        scalars: scalars ?? this.scalars,
        series: series ?? this.series,
        labels: labels ?? this.labels,
        now: now ?? this.now,
      );
}

/// The closed vocabulary of signals a rule may reference.
///
/// A rule naming anything outside this set is a typo, not a feature — the
/// corpus is data, so nothing else would catch `nutrition.protienPct7d` before
/// it silently never fired. The validation test checks the corpus against it.
abstract final class HerculSignals {
  // ── profile ──────────────────────────────────────────────────────────────
  static const heightCm = 'profile.heightCm';
  static const weightKg = 'profile.weightKg';
  static const ageYears = 'profile.ageYears';

  /// `weightLoss | muscleGain | maintenance | improveHealth` (label).
  static const goal = 'profile.goal';

  /// `male | female` (label).
  static const sex = 'profile.sex';

  // ── central nervous system ───────────────────────────────────────────────
  /// Rolling fatigue 0–1.
  static const cnsLoad = 'cns.currentLoad';

  /// 1 − load, clamped 0–1.
  static const cnsReadiness = 'cns.readiness';

  /// Acute ÷ chronic weekly load. > 1.4 is the classic deload trigger.
  static const cnsAcwr = 'cns.acwr';

  /// 1 when a deload is indicated, else 0.
  static const cnsDeloadSuggested = 'cns.deloadSuggested';

  /// `FRESH | MODERATE | HIGH` (label).
  static const cnsStatus = 'cns.status';

  // ── recovery, per muscle group ───────────────────────────────────────────
  /// 0 wrecked – 100 recovered. Argument: muscle group.
  static const recoveryScore = 'recovery.score';

  // ── volume ───────────────────────────────────────────────────────────────
  /// Working sets this week. Argument: muscle group.
  static const weeklySets = 'volume.weeklySets';

  static const weeklyTonnageKg = 'volume.weeklyTonnageKg';
  static const pushPct = 'volume.pushPct';
  static const pullPct = 'volume.pullPct';

  // ── nutrition ────────────────────────────────────────────────────────────
  /// Mean protein ÷ target over the trailing 7 days. 1.0 = on target.
  static const proteinPct7d = 'nutrition.proteinPct7d';
  static const kcalPct7d = 'nutrition.kcalPct7d';

  /// Days in the last 7 with any food logged — the honesty check on the above.
  static const daysLogged7d = 'nutrition.daysLogged7d';

  // ── bodyweight ───────────────────────────────────────────────────────────
  /// Signed change over the window. Negative = lost. Argument: day count.
  static const weightDeltaKg = 'body.weightDeltaKg';

  // ── training history ─────────────────────────────────────────────────────
  /// Sessions containing this exercise in the last 30 days. Argument: slug.
  static const performedLast30d = 'exercise.performedLast30d';

  /// Days since this exercise was last performed. Argument: slug.
  static const lastPerformedDays = 'exercise.lastPerformedDays';

  /// Best estimated 1RM in kg. Argument: exercise slug.
  static const e1rmKg = 'exercise.e1rmKg';

  /// One exercise's best e1RM divided by another's. Argument: `slugA:slugB`.
  ///
  /// A ratio rather than two signals because a condition compares a signal to a
  /// constant, not to another signal — and the interesting question is almost
  /// always relative ("is your deadlift keeping up with your squat"), which also
  /// makes the threshold portable across strength levels.
  static const e1rmRatio = 'exercise.e1rmRatio';

  // ── sessions ─────────────────────────────────────────────────────────────
  static const daysSinceLastWorkout = 'session.daysSinceLastWorkout';
  static const sessionsThisWeek = 'session.sessionsThisWeek';
  static const sessionsPerWeek4w = 'session.sessionsPerWeek4w';

  /// Signals addressed by an argument rather than standing alone.
  static const argumentSignals = {
    recoveryScore,
    weeklySets,
    weightDeltaKg,
    performedLast30d,
    lastPerformedDays,
    e1rmKg,
    e1rmRatio,
  };

  /// Signals whose value is a string.
  static const labelSignals = {goal, sex, cnsStatus};

  static const all = {
    heightCm, weightKg, ageYears, goal, sex,
    cnsLoad, cnsReadiness, cnsAcwr, cnsDeloadSuggested, cnsStatus,
    recoveryScore,
    weeklySets, weeklyTonnageKg, pushPct, pullPct,
    proteinPct7d, kcalPct7d, daysLogged7d,
    weightDeltaKg,
    performedLast30d, lastPerformedDays, e1rmKg, e1rmRatio,
    daysSinceLastWorkout, sessionsThisWeek, sessionsPerWeek4w,
  };
}
