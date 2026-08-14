import 'package:flutter/material.dart';

/// The four biological cycle phases.
enum CyclePhase {
  menstrual('menstrual', 'Menstrual Phase', 'Rest & Recovery', Icons.water_drop),
  follicular('follicular', 'Follicular Phase', 'Power & Progress', Icons.bolt),
  ovulatory('ovulatory', 'Ovulatory Phase', 'Peak Strength', Icons.local_fire_department),
  luteal('luteal', 'Luteal Phase', 'Steady-State & Endurance', Icons.spa);

  final String id;
  final String title;
  final String subtitle;
  final IconData icon;

  const CyclePhase(this.id, this.title, this.subtitle, this.icon);

  static CyclePhase fromId(String id) {
    return CyclePhase.values.firstWhere(
      (p) => p.id.toLowerCase() == id.toLowerCase(),
      orElse: () => CyclePhase.follicular,
    );
  }
}

/// Represents the training and nutrition adjustment recommendation for a cycle phase.
class CycleAdjustmentResult {
  final CyclePhase phase;
  final double volumeFactor; // e.g. 0.8 for -20%, 1.1 for +10%
  final String statusLabel;
  final String trainingRecommendation;
  final String nutritionRecommendation;
  final int dayOfCycle;
  final int totalCycleDays;
  final int daysUntilNextPeriod;
  final bool isManualOverride;

  const CycleAdjustmentResult({
    required this.phase,
    required this.volumeFactor,
    required this.statusLabel,
    required this.trainingRecommendation,
    required this.nutritionRecommendation,
    required this.dayOfCycle,
    required this.totalCycleDays,
    required this.daysUntilNextPeriod,
    this.isManualOverride = false,
  });
}

/// Pure domain predictor for menstrual cycle phases.
class CyclePredictor {
  /// Computes the zero-indexed day of the cycle (0 .. avgCycleDays-1).
  static int computeDayOfCycle({
    required DateTime date,
    required DateTime lastPeriodStart,
    int avgCycleDays = 28,
  }) {
    final cleanDate = DateTime(date.year, date.month, date.day);
    final cleanStart = DateTime(
      lastPeriodStart.year,
      lastPeriodStart.month,
      lastPeriodStart.day,
    );

    final diffDays = cleanDate.difference(cleanStart).inDays;
    if (diffDays < 0) return 0;

    final cycleDays = avgCycleDays > 0 ? avgCycleDays : 28;
    return diffDays % cycleDays;
  }

  /// Calculates the predicted [CyclePhase] given cycle parameters.
  static CyclePhase predictPhase({
    required DateTime date,
    required DateTime lastPeriodStart,
    int avgCycleDays = 28,
    int avgPeriodDays = 5,
  }) {
    final dayOfCycle = computeDayOfCycle(
      date: date,
      lastPeriodStart: lastPeriodStart,
      avgCycleDays: avgCycleDays,
    );

    final periodDays = avgPeriodDays > 0 ? avgPeriodDays : 5;

    // Phase distribution:
    // 1. Menstrual: Day 0 to avgPeriodDays - 1
    // 2. Follicular: Day avgPeriodDays to approx day 11
    // 3. Ovulatory: Approx days 12 to 15
    // 4. Luteal: Day 16 to end of cycle
    if (dayOfCycle < periodDays) {
      return CyclePhase.menstrual;
    } else if (dayOfCycle < 12) {
      return CyclePhase.follicular;
    } else if (dayOfCycle < 16) {
      return CyclePhase.ovulatory;
    } else {
      return CyclePhase.luteal;
    }
  }

  /// Calculates days remaining until the next predicted period start.
  static int daysUntilNextPeriod({
    required DateTime date,
    required DateTime lastPeriodStart,
    int avgCycleDays = 28,
  }) {
    final dayOfCycle = computeDayOfCycle(
      date: date,
      lastPeriodStart: lastPeriodStart,
      avgCycleDays: avgCycleDays,
    );
    final cycleDays = avgCycleDays > 0 ? avgCycleDays : 28;
    return (cycleDays - dayOfCycle) % cycleDays;
  }
}

/// Provides physiological training and nutrition suggestions based on cycle phase.
class CycleAwareAdjuster {
  static CycleAdjustmentResult suggest({
    required CyclePhase phase,
    required int dayOfCycle,
    required int totalCycleDays,
    required int daysUntilNextPeriod,
    bool isManualOverride = false,
  }) {
    switch (phase) {
      case CyclePhase.menstrual:
        return CycleAdjustmentResult(
          phase: phase,
          volumeFactor: 0.8,
          statusLabel: isManualOverride ? "MANUAL OVERRIDE (VOLUME -20%)" : "VOLUME REDUCED 20%",
          trainingRecommendation:
              "Energy and iron stores are lower. Prioritize technique work, deload volume, mobility, or low-impact cardio.",
          nutritionRecommendation:
              "Increase iron-rich foods, magnesium, and hydration. Anti-inflammatory foods can help ease cramping.",
          dayOfCycle: dayOfCycle,
          totalCycleDays: totalCycleDays,
          daysUntilNextPeriod: daysUntilNextPeriod,
          isManualOverride: isManualOverride,
        );

      case CyclePhase.follicular:
        return CycleAdjustmentResult(
          phase: phase,
          volumeFactor: 1.1,
          statusLabel: isManualOverride ? "MANUAL OVERRIDE (VOLUME +10%)" : "VOLUME BOOSTED +10%",
          trainingRecommendation:
              "Estrogen is rising and insulin sensitivity is optimal. Prime time for progressive overload, hypertrophy, and high-intensity lifts.",
          nutritionRecommendation:
              "Body utilizes carbs efficiently during this phase. Support workouts with complex carbohydrates and lean proteins.",
          dayOfCycle: dayOfCycle,
          totalCycleDays: totalCycleDays,
          daysUntilNextPeriod: daysUntilNextPeriod,
          isManualOverride: isManualOverride,
        );

      case CyclePhase.ovulatory:
        return CycleAdjustmentResult(
          phase: phase,
          volumeFactor: 1.0,
          statusLabel: isManualOverride ? "MANUAL OVERRIDE (PEAK INTENSITY)" : "PEAK INTENSITY",
          trainingRecommendation:
              "Peak estrogen and testosterone levels maximize strength. Ideal window for attempting 1RM attempts and heavy compound lifts.",
          nutritionRecommendation:
              "Focus on fiber and antioxidants (cruciferous vegetables, berries) to support healthy estrogen metabolism.",
          dayOfCycle: dayOfCycle,
          totalCycleDays: totalCycleDays,
          daysUntilNextPeriod: daysUntilNextPeriod,
          isManualOverride: isManualOverride,
        );

      case CyclePhase.luteal:
        return CycleAdjustmentResult(
          phase: phase,
          volumeFactor: 0.85,
          statusLabel: isManualOverride ? "MANUAL OVERRIDE (VOLUME -15%)" : "VOLUME REDUCED 15%",
          trainingRecommendation:
              "Progesterone rises, increasing body temperature and metabolic demand. Emphasize steady-state cardio, moderate resistance, and active recovery.",
          nutritionRecommendation:
              "Metabolism increases slightly (~100-200 kcal). Prioritize healthy fats, complex carbs, and magnesium to mitigate cravings.",
          dayOfCycle: dayOfCycle,
          totalCycleDays: totalCycleDays,
          daysUntilNextPeriod: daysUntilNextPeriod,
          isManualOverride: isManualOverride,
        );
    }
  }
}
