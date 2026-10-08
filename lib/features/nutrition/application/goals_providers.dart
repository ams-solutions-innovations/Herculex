import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:herculex/app/providers.dart';
import 'package:herculex/features/nutrition/application/nutrition_providers.dart';
import 'package:herculex/features/nutrition/domain/diet_phase.dart';

// ── Active diet plan (Cut / Bulk / Maingain / Maintain & pace) ───────────────

class ActiveDietPlan {
  final DietPhase phase;
  final double weeklyRateKg;
  final int kcalDelta;
  final String paceLabel;

  /// False while the member has never applied a plan and these are only the
  /// defaults (cut at 0.5 kg/week), so a screen does not mistake the default
  /// for a choice.
  final bool isSet;

  const ActiveDietPlan({
    required this.phase,
    required this.weeklyRateKg,
    required this.kcalDelta,
    required this.paceLabel,
    this.isSet = true,
  });

  ActiveDietPlan copyWith({
    DietPhase? phase,
    double? weeklyRateKg,
    int? kcalDelta,
    String? paceLabel,
  }) => ActiveDietPlan(
    phase: phase ?? this.phase,
    weeklyRateKg: weeklyRateKg ?? this.weeklyRateKg,
    kcalDelta: kcalDelta ?? this.kcalDelta,
    paceLabel: paceLabel ?? this.paceLabel,
    isSet: isSet,
  );
}

class ActiveDietPlanNotifier extends Notifier<ActiveDietPlan> {
  static const _phaseKey = 'diet_active_phase';
  static const _rateKey = 'diet_weekly_rate_kg';
  static const _deltaKey = 'diet_kcal_delta';
  static const _labelKey = 'diet_pace_label';

  @override
  ActiveDietPlan build() {
    final p = ref.watch(sharedPreferencesProvider);
    final phaseStr = p.getString(_phaseKey) ?? 'cut';
    final phase = DietPhase.values.firstWhere(
      (e) => e.name == phaseStr,
      orElse: () => DietPhase.cut,
    );
    final rate = p.getDouble(_rateKey) ?? 0.5;
    final delta = p.getInt(_deltaKey) ?? -500;
    final label = p.getString(_labelKey) ?? '0.50 kg/w (Normalno)';

    return ActiveDietPlan(
      phase: phase,
      weeklyRateKg: rate,
      kcalDelta: delta,
      paceLabel: label,
      isSet: p.containsKey(_phaseKey),
    );
  }

  Future<void> setPlan({
    required DietPhase phase,
    required double weeklyRateKg,
    required int kcalDelta,
    required String paceLabel,
  }) async {
    final p = ref.read(sharedPreferencesProvider);
    await p.setString(_phaseKey, phase.name);
    await p.setDouble(_rateKey, weeklyRateKg);
    await p.setInt(_deltaKey, kcalDelta);
    await p.setString(_labelKey, paceLabel);
    state = ActiveDietPlan(
      phase: phase,
      weeklyRateKg: weeklyRateKg,
      kcalDelta: kcalDelta,
      paceLabel: paceLabel,
    );
  }
}

final activeDietPlanProvider =
    NotifierProvider<ActiveDietPlanNotifier, ActiveDietPlan>(
      ActiveDietPlanNotifier.new,
    );

// ── Starting weight ──────────────────────────────────────────────────────────

typedef StartingWeightData = ({double kg, String dateIso});

class StartingWeightNotifier extends Notifier<StartingWeightData?> {
  static const _kgKey = 'goals_start_kg';
  static const _dateKey = 'goals_start_date';

  @override
  StartingWeightData? build() {
    final p = ref.watch(sharedPreferencesProvider);
    final kg = p.getDouble(_kgKey);
    final date = p.getString(_dateKey);
    if (kg == null || date == null) return null;
    return (kg: kg, dateIso: date);
  }

  Future<void> set(double kg, DateTime date) async {
    final p = ref.read(sharedPreferencesProvider);
    final iso = _iso(date);
    await p.setDouble(_kgKey, kg);
    await p.setString(_dateKey, iso);
    state = (kg: kg, dateIso: iso);
  }

  static String _iso(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

final startingWeightProvider =
    NotifierProvider<StartingWeightNotifier, StartingWeightData?>(
      StartingWeightNotifier.new,
    );

// ── Goal weight ──────────────────────────────────────────────────────────────

class GoalWeightNotifier extends Notifier<double?> {
  static const _key = 'goals_goal_kg';

  @override
  double? build() => ref.watch(sharedPreferencesProvider).getDouble(_key);

  Future<void> set(double kg) async {
    await ref.read(sharedPreferencesProvider).setDouble(_key, kg);
    state = kg;
  }

  /// Forgets the goal weight. Without this a cleared profile target kept
  /// reappearing from here, because every reader falls back to this value.
  Future<void> clear() async {
    await ref.read(sharedPreferencesProvider).remove(_key);
    state = null;
  }
}

final goalWeightProvider = NotifierProvider<GoalWeightNotifier, double?>(
  GoalWeightNotifier.new,
);

// ── Weekly goal (positive = loss, negative = gain, in kg/week) ────────────────

class WeeklyGoalNotifier extends Notifier<double> {
  static const _key = 'goals_weekly_kg';

  @override
  double build() => ref.watch(sharedPreferencesProvider).getDouble(_key) ?? 0.5;

  Future<void> set(double kgPerWeek) async {
    await ref.read(sharedPreferencesProvider).setDouble(_key, kgPerWeek);
    state = kgPerWeek;
  }
}

final weeklyGoalProvider = NotifierProvider<WeeklyGoalNotifier, double>(
  WeeklyGoalNotifier.new,
);

// ── Fitness goals ────────────────────────────────────────────────────────────

class FitnessGoalsState {
  final int workoutsPerWeek;
  final int minutesPerWorkout;

  const FitnessGoalsState({
    required this.workoutsPerWeek,
    required this.minutesPerWorkout,
  });

  FitnessGoalsState copyWith({int? workoutsPerWeek, int? minutesPerWorkout}) =>
      FitnessGoalsState(
        workoutsPerWeek: workoutsPerWeek ?? this.workoutsPerWeek,
        minutesPerWorkout: minutesPerWorkout ?? this.minutesPerWorkout,
      );
}

class FitnessGoalsNotifier extends Notifier<FitnessGoalsState> {
  static const _workoutsKey = 'goals_workouts_pw';
  static const _minutesKey = 'goals_minutes_pw';

  @override
  FitnessGoalsState build() {
    final p = ref.watch(sharedPreferencesProvider);
    return FitnessGoalsState(
      workoutsPerWeek: p.getInt(_workoutsKey) ?? 0,
      minutesPerWorkout: p.getInt(_minutesKey) ?? 0,
    );
  }

  Future<void> setWorkouts(int v) async {
    await ref.read(sharedPreferencesProvider).setInt(_workoutsKey, v);
    state = state.copyWith(workoutsPerWeek: v);
  }

  Future<void> setMinutes(int v) async {
    await ref.read(sharedPreferencesProvider).setInt(_minutesKey, v);
    state = state.copyWith(minutesPerWorkout: v);
  }
}

final fitnessGoalsProvider =
    NotifierProvider<FitnessGoalsNotifier, FitnessGoalsState>(
      FitnessGoalsNotifier.new,
    );

// ── Show net carbs by meal ────────────────────────────────────────────────────

class ShowNetCarbsNotifier extends Notifier<bool> {
  static const _key = 'goals_show_net_carbs';

  @override
  bool build() => ref.watch(sharedPreferencesProvider).getBool(_key) ?? true;

  Future<void> toggle() async {
    final next = !state;
    await ref.read(sharedPreferencesProvider).setBool(_key, next);
    state = next;
  }
}

final showNetCarbsByMealProvider = NotifierProvider<ShowNetCarbsNotifier, bool>(
  ShowNetCarbsNotifier.new,
);

// ── Meal goals ───────────────────────────────────────────────────────────────

class MealGoalsState {
  final bool enabled;
  final bool showAsCalories;
  final double breakfastPct;
  final double lunchPct;
  final double dinnerPct;
  final double snacksPct;

  const MealGoalsState({
    this.enabled = true,
    this.showAsCalories = true,
    this.breakfastPct = 30.0,
    this.lunchPct = 30.0,
    this.dinnerPct = 30.0,
    this.snacksPct = 10.0,
  });

  MealGoalsState copyWith({
    bool? enabled,
    bool? showAsCalories,
    double? breakfastPct,
    double? lunchPct,
    double? dinnerPct,
    double? snacksPct,
  }) => MealGoalsState(
    enabled: enabled ?? this.enabled,
    showAsCalories: showAsCalories ?? this.showAsCalories,
    breakfastPct: breakfastPct ?? this.breakfastPct,
    lunchPct: lunchPct ?? this.lunchPct,
    dinnerPct: dinnerPct ?? this.dinnerPct,
    snacksPct: snacksPct ?? this.snacksPct,
  );

  int mealCalories(int totalKcal, double pct) =>
      (totalKcal * pct / 100).round();

  /// Share of the daily budget allotted to a diary slot, or null for custom
  /// slots — those have no configured split, so the diary shows no "of Y".
  double? pctForSlot(String mealKey) => switch (mealKey) {
    'breakfast' => breakfastPct,
    'lunch' => lunchPct,
    'dinner' => dinnerPct,
    'snack' => snacksPct,
    _ => null,
  };
}

class MealGoalsNotifier extends Notifier<MealGoalsState> {
  @override
  MealGoalsState build() {
    final p = ref.watch(sharedPreferencesProvider);
    return MealGoalsState(
      enabled: p.getBool('meal_enabled') ?? true,
      showAsCalories: p.getBool('meal_show_cal') ?? true,
      breakfastPct: p.getDouble('meal_breakfast') ?? 30.0,
      lunchPct: p.getDouble('meal_lunch') ?? 30.0,
      dinnerPct: p.getDouble('meal_dinner') ?? 30.0,
      snacksPct: p.getDouble('meal_snacks') ?? 10.0,
    );
  }

  Future<void> setEnabled(bool v) async {
    await ref.read(sharedPreferencesProvider).setBool('meal_enabled', v);
    state = state.copyWith(enabled: v);
  }

  Future<void> setShowAsCalories(bool v) async {
    await ref.read(sharedPreferencesProvider).setBool('meal_show_cal', v);
    state = state.copyWith(showAsCalories: v);
  }

  Future<void> setBreakfastPct(double v) async {
    await ref.read(sharedPreferencesProvider).setDouble('meal_breakfast', v);
    state = state.copyWith(breakfastPct: v);
  }

  Future<void> setLunchPct(double v) async {
    await ref.read(sharedPreferencesProvider).setDouble('meal_lunch', v);
    state = state.copyWith(lunchPct: v);
  }

  Future<void> setDinnerPct(double v) async {
    await ref.read(sharedPreferencesProvider).setDouble('meal_dinner', v);
    state = state.copyWith(dinnerPct: v);
  }

  Future<void> setSnacksPct(double v) async {
    await ref.read(sharedPreferencesProvider).setDouble('meal_snacks', v);
    state = state.copyWith(snacksPct: v);
  }
}

final mealGoalsProvider = NotifierProvider<MealGoalsNotifier, MealGoalsState>(
  MealGoalsNotifier.new,
);

/// Calorie goal for one diary slot on one day (§3), or null when meal goals
/// are off, the day has no resolved target, or the slot is user-created.
/// Resolves against the *effective* daily target so carb-cycling and diet
/// schedules flow through to per-meal goals automatically.
typedef MealGoalKey = ({String mealKey, DateTime date});

final mealGoalKcalProvider = Provider.autoDispose.family<int?, MealGoalKey>((
  ref,
  key,
) {
  final goals = ref.watch(mealGoalsProvider);
  if (!goals.enabled) return null;

  final pct = goals.pctForSlot(key.mealKey);
  if (pct == null) return null;

  final targets =
      ref.watch(effectiveTargetsProvider(key.date)).asData?.value ??
      ref.watch(baselineTargetsProvider);
  if (targets == null) return null;

  return goals.mealCalories(targets.kcal, pct);
});

// ── Minimum targets & floor limits ─────────────────────────────────────────

enum MinProteinMode {
  perLb('g/lb (bw)'),
  perKg('g/kg (bw)'),
  fixed('Fixed (g)');

  final String label;
  const MinProteinMode(this.label);
}

class MinimumTargetsState {
  final bool enabled;
  final MinProteinMode mode;
  final double proteinValue;
  final int? minCaloriesKcal;

  const MinimumTargetsState({
    this.enabled = false,
    this.mode = MinProteinMode.perLb,
    this.proteinValue = 1.0,
    this.minCaloriesKcal,
  });

  MinimumTargetsState copyWith({
    bool? enabled,
    MinProteinMode? mode,
    double? proteinValue,
    Object? minCaloriesKcal = _undefined,
  }) => MinimumTargetsState(
    enabled: enabled ?? this.enabled,
    mode: mode ?? this.mode,
    proteinValue: proteinValue ?? this.proteinValue,
    minCaloriesKcal: minCaloriesKcal == _undefined
        ? this.minCaloriesKcal
        : minCaloriesKcal as int?,
  );

  int? resolvedMinProteinG(double? weightKg) {
    if (!enabled) return null;
    switch (mode) {
      case MinProteinMode.perLb:
        if (weightKg == null || weightKg <= 0) return null;
        final weightLb = weightKg * 2.20462;
        return (weightLb * proteinValue).round();
      case MinProteinMode.perKg:
        if (weightKg == null || weightKg <= 0) return null;
        return (weightKg * proteinValue).round();
      case MinProteinMode.fixed:
        return proteinValue.round();
    }
  }

  int? get effectiveMinCaloriesKcal => enabled ? minCaloriesKcal : null;
}

const _undefined = Object();

class MinimumTargetsNotifier extends Notifier<MinimumTargetsState> {
  static const _enabledKey = 'min_targets_enabled';
  static const _modeKey = 'min_targets_mode';
  static const _proteinValKey = 'min_targets_protein_val';
  static const _kcalKey = 'min_targets_kcal';

  @override
  MinimumTargetsState build() {
    final p = ref.watch(sharedPreferencesProvider);
    final modeStr = p.getString(_modeKey) ?? 'perLb';
    final mode = MinProteinMode.values.firstWhere(
      (e) => e.name == modeStr,
      orElse: () => MinProteinMode.perLb,
    );
    final kcalVal = p.getInt(_kcalKey);
    return MinimumTargetsState(
      enabled: p.getBool(_enabledKey) ?? false,
      mode: mode,
      proteinValue: p.getDouble(_proteinValKey) ?? 1.0,
      minCaloriesKcal: kcalVal != null && kcalVal > 0 ? kcalVal : null,
    );
  }

  Future<void> setEnabled(bool enabled) async {
    await ref.read(sharedPreferencesProvider).setBool(_enabledKey, enabled);
    state = state.copyWith(enabled: enabled);
  }

  Future<void> setMode(MinProteinMode mode) async {
    await ref.read(sharedPreferencesProvider).setString(_modeKey, mode.name);
    state = state.copyWith(mode: mode);
  }

  Future<void> setProteinValue(double val) async {
    await ref.read(sharedPreferencesProvider).setDouble(_proteinValKey, val);
    state = state.copyWith(proteinValue: val);
  }

  Future<void> setMinCalories(int? kcal) async {
    final p = ref.read(sharedPreferencesProvider);
    if (kcal != null && kcal > 0) {
      await p.setInt(_kcalKey, kcal);
    } else {
      await p.remove(_kcalKey);
    }
    state = state.copyWith(minCaloriesKcal: kcal);
  }
}

final minimumTargetsProvider =
    NotifierProvider<MinimumTargetsNotifier, MinimumTargetsState>(
      MinimumTargetsNotifier.new,
    );
