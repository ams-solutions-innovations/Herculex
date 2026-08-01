import '../../workouts/domain/one_rep_max.dart';
import 'training_snapshot.dart';

/// Best performance for one (equipment variant | accessory combo | gym) slice
/// of an exercise's history (V2 §1, §5, §10).
class PerformanceRecord {
  final String label;
  final double bestWeightKg;
  final int bestWeightReps;
  final double? bestE1RmKg;
  final int setCount;
  final double? rawWeightKg;

  const PerformanceRecord({
    required this.label,
    required this.bestWeightKg,
    required this.bestWeightReps,
    required this.bestE1RmKg,
    required this.setCount,
    this.rawWeightKg,
  });
}

/// Per-exercise PR/1RM breakdowns over a [TrainingSnapshot]. All numbers use
/// effective load, so weighted pull-ups, bands, and chains rank correctly.
class VariantPerformance {
  /// PRs grouped by equipment variant ("Barbell: 120kg", "Smith: 100kg", …).
  static List<PerformanceRecord> byEquipment(
      TrainingSnapshot snapshot, int exerciseId) {
    return _group(
      snapshot,
      exerciseId,
      (rs) => rs.equipmentVariant,
    );
  }

  /// PRs grouped by accessory combination ("Raw", "Belt", "Belt + Knee
  /// Sleeves", …) — §5's headline analytics requirement.
  static List<PerformanceRecord> byAccessoryCombo(
      TrainingSnapshot snapshot, int exerciseId) {
    return _group(
      snapshot,
      exerciseId,
      (rs) => rs.accessoryCombo,
    );
  }

  /// PRs grouped by gym, for machine-comparison across locations (§10).
  static List<PerformanceRecord> byGym(
      TrainingSnapshot snapshot, int exerciseId,
      {required String Function(int? gymId) gymName}) {
    return _group(
      snapshot,
      exerciseId,
      (rs) => gymName(rs.session.gymId),
    );
  }

  static List<PerformanceRecord> _group(
    TrainingSnapshot snapshot,
    int exerciseId,
    String Function(ResolvedSet) keyOf,
  ) {
    final byKey = <String, List<ResolvedSet>>{};
    for (final rs in snapshot.sets) {
      if (rs.exercise.id != exerciseId) continue;
      if (rs.set.reps <= 0 || rs.effectiveKg <= 0) continue;
      byKey.putIfAbsent(keyOf(rs), () => []).add(rs);
    }

    final records = <PerformanceRecord>[];
    for (final e in byKey.entries) {
      ResolvedSet? bestWeight;
      double? bestE1Rm;
      for (final rs in e.value) {
        if (bestWeight == null || rs.effectiveKg > bestWeight.effectiveKg) {
          bestWeight = rs;
        }
        final est =
            OneRepMax.estimate(weightKg: rs.effectiveKg, reps: rs.set.reps);
        if (est != null && (bestE1Rm == null || est > bestE1Rm)) {
          bestE1Rm = est;
        }
      }
      records.add(PerformanceRecord(
        label: e.key,
        bestWeightKg: bestWeight!.effectiveKg,
        bestWeightReps: bestWeight.set.reps,
        bestE1RmKg: bestE1Rm,
        setCount: e.value.length,
        rawWeightKg: bestWeight.set.weightKg,
      ));
    }

    records.sort((a, b) =>
        (b.bestE1RmKg ?? b.bestWeightKg).compareTo(a.bestE1RmKg ?? a.bestWeightKg));
    return records;
  }
}
