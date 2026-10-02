import 'dart:math' as math;

import 'package:herculex/features/nutrition/domain/diet_phase.dart';
import 'package:herculex/features/physique/domain/physique_tuning.dart';

/// Phase pacing: the existing [DietPhaseCalculator] preset, capped by a
/// percent-bodyweight-per-week ceiling (D-04). No new tempo model.
abstract final class PhysiqueTempoPolicy {
  static double presetWeeklyKg({
    required DietPhase phase,
    required int maintenanceKcal,
  }) => switch (phase) {
    DietPhase.cut =>
      maintenanceKcal *
          DietPhaseCalculator.defaultCutPct /
          100 /
          PhysiqueTuning.kcalPerKgPerWeek,
    DietPhase.bulk =>
      maintenanceKcal *
          DietPhaseCalculator.defaultBulkPct /
          100 /
          PhysiqueTuning.kcalPerKgPerWeek,
    DietPhase.maingain =>
      DietPhaseCalculator.defaultMaingainSurplusKcal /
          PhysiqueTuning.kcalPerKgPerWeek,
    DietPhase.maintain || DietPhase.recomp => 0.0,
  };

  static double ceilingPct(DietPhase phase) => switch (phase) {
    DietPhase.cut => PhysiqueTuning.cutCeilingPctPerWeek,
    DietPhase.bulk => PhysiqueTuning.bulkCeilingPctPerWeek,
    DietPhase.maingain => PhysiqueTuning.maingainCeilingPctPerWeek,
    DietPhase.maintain || DietPhase.recomp => 0.0,
  };

  static double weeklyKg({
    required DietPhase phase,
    required double bodyweightKg,
    required int maintenanceKcal,
    int? maxDeltaKcalCap,
  }) {
    if (phase == DietPhase.maintain || phase == DietPhase.recomp) return 0;
    var value = math.min(
      presetWeeklyKg(phase: phase, maintenanceKcal: maintenanceKcal),
      bodyweightKg * ceilingPct(phase) / 100,
    );
    if (maxDeltaKcalCap != null) {
      value = math.min(
        value,
        maxDeltaKcalCap / PhysiqueTuning.kcalPerKgPerWeek,
      );
    }
    return value;
  }

  /// True when the returned pace is strictly below the preset.
  static bool isCapped({
    required DietPhase phase,
    required double bodyweightKg,
    required int maintenanceKcal,
    int? maxDeltaKcalCap,
  }) {
    if (phase == DietPhase.maintain || phase == DietPhase.recomp) return false;
    final preset = presetWeeklyKg(
      phase: phase,
      maintenanceKcal: maintenanceKcal,
    );
    final actual = weeklyKg(
      phase: phase,
      bodyweightKg: bodyweightKg,
      maintenanceKcal: maintenanceKcal,
      maxDeltaKcalCap: maxDeltaKcalCap,
    );
    return actual < preset - 1e-9;
  }

  static int plannedWeeks({required double deltaKg, required double weeklyKg}) {
    if (weeklyKg <= 0) return 0;
    // Guard against float noise such as 6 / 0.5000000001.
    return ((deltaKg.abs() / weeklyKg) - 1e-9).ceil();
  }
}
