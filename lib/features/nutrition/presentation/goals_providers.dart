import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import 'nutrition_providers.dart';

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
}

final goalWeightProvider =
    NotifierProvider<GoalWeightNotifier, double?>(GoalWeightNotifier.new);

// ── Weekly goal (positive = loss, negative = gain, in kg/week) ────────────────

class WeeklyGoalNotifier extends Notifier<double> {
  static const _key = 'goals_weekly_kg';

  @override
  double build() =>
      ref.watch(sharedPreferencesProvider).getDouble(_key) ?? 0.5;

  Future<void> set(double kgPerWeek) async {
    await ref.read(sharedPreferencesProvider).setDouble(_key, kgPerWeek);
    state = kgPerWeek;
  }
}

final weeklyGoalProvider =
    NotifierProvider<WeeklyGoalNotifier, double>(WeeklyGoalNotifier.new);

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
  bool build() =>
      ref.watch(sharedPreferencesProvider).getBool(_key) ?? true;

  Future<void> toggle() async {
    final next = !state;
    await ref.read(sharedPreferencesProvider).setBool(_key, next);
    state = next;
  }
}

final showNetCarbsByMealProvider =
    NotifierProvider<ShowNetCarbsNotifier, bool>(ShowNetCarbsNotifier.new);

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
  }) =>
      MealGoalsState(
        enabled: enabled ?? this.enabled,
        showAsCalories: showAsCalories ?? this.showAsCalories,
        breakfastPct: breakfastPct ?? this.breakfastPct,
        lunchPct: lunchPct ?? this.lunchPct,
        dinnerPct: dinnerPct ?? this.dinnerPct,
        snacksPct: snacksPct ?? this.snacksPct,
      );

  int mealCalories(int totalKcal, double pct) => (totalKcal * pct / 100).round();

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

final mealGoalsProvider =
    NotifierProvider<MealGoalsNotifier, MealGoalsState>(MealGoalsNotifier.new);

/// Calorie goal for one diary slot on one day (§3), or null when meal goals
/// are off, the day has no resolved target, or the slot is user-created.
/// Resolves against the *effective* daily target so carb-cycling and diet
/// schedules flow through to per-meal goals automatically.
typedef MealGoalKey = ({String mealKey, DateTime date});

final mealGoalKcalProvider =
    Provider.autoDispose.family<int?, MealGoalKey>((ref, key) {
  final goals = ref.watch(mealGoalsProvider);
  if (!goals.enabled) return null;

  final pct = goals.pctForSlot(key.mealKey);
  if (pct == null) return null;

  final targets = ref.watch(effectiveTargetsProvider(key.date)).asData?.value ??
      ref.watch(baselineTargetsProvider);
  if (targets == null) return null;

  return goals.mealCalories(targets.kcal, pct);
});
