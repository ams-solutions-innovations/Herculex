/// The dieting phase a set of daily targets is written for (§5).
///
/// Picking a phase in the target editor rewrites the numbers rather than just
/// labelling them, so the saved target already reflects the deficit or
/// surplus — nothing downstream has to know a phase was involved.
enum DietPhase {
  maintain('Maintain'),
  cut('Cut'),
  bulk('Bulk');

  const DietPhase(this.label);
  final String label;

  /// Confirmation-button text: "Save Cut", "Save Bulk", "Save Target".
  String get saveLabel =>
      this == DietPhase.maintain ? 'Save Target' : 'Save $label';
}

/// A calorie/macro set, as produced by the phase maths.
class PhaseTargets {
  final int kcal;
  final int proteinG;
  final int carbsG;
  final int fatG;

  const PhaseTargets({
    required this.kcal,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
  });
}

/// Applies a dieting phase to a maintenance baseline.
class DietPhaseCalculator {
  /// Default calorie shift, as a share of maintenance. A 20 % cut and a 10 %
  /// surplus are the conventional starting points: aggressive enough to move
  /// the scale, mild enough not to shed muscle or add excess fat.
  static const defaultCutPct = 20.0;
  static const defaultBulkPct = 10.0;

  /// Grams of protein per kg of bodyweight. Protein is held high in a cut —
  /// it's the macro that protects lean mass in a deficit — and merely
  /// adequate in a bulk, leaving room for the carbs that fuel training.
  static const cutProteinPerKg = 2.2;
  static const maintainProteinPerKg = 1.8;
  static const bulkProteinPerKg = 1.8;

  /// Share of calories from fat. Kept above ~20 % in a cut for hormonal
  /// health; the rest of the budget goes to carbs.
  static const cutFatShare = 0.25;
  static const maintainFatShare = 0.275;
  static const bulkFatShare = 0.25;

  /// Rewrites [baselineKcal] and the macro split for [phase].
  ///
  /// [bodyweightKg] drives protein; without it protein falls back to a share
  /// of calories so the function still returns something sensible.
  /// [pctOverride] replaces the default shift when the user has tuned it.
  static PhaseTargets apply({
    required DietPhase phase,
    required int baselineKcal,
    double? bodyweightKg,
    double? pctOverride,
  }) {
    final shift = switch (phase) {
      DietPhase.maintain => 0.0,
      DietPhase.cut => -(pctOverride ?? defaultCutPct),
      DietPhase.bulk => (pctOverride ?? defaultBulkPct),
    };
    final kcal = (baselineKcal * (1 + shift / 100)).round().clamp(0, 20000);
    if (kcal <= 0) {
      return const PhaseTargets(kcal: 0, proteinG: 0, carbsG: 0, fatG: 0);
    }

    final proteinPerKg = switch (phase) {
      DietPhase.cut => cutProteinPerKg,
      DietPhase.bulk => bulkProteinPerKg,
      DietPhase.maintain => maintainProteinPerKg,
    };
    final fatShare = switch (phase) {
      DietPhase.cut => cutFatShare,
      DietPhase.bulk => bulkFatShare,
      DietPhase.maintain => maintainFatShare,
    };

    // Protein first, then fat, then carbs take whatever is left.
    var protein = bodyweightKg != null
        ? (bodyweightKg * proteinPerKg).round()
        : (kcal * 0.30 / 4).round();

    final fatKcal = kcal * fatShare;
    var fat = (fatKcal / 9).round();

    var carbsKcal = kcal - protein * 4 - fatKcal;
    if (carbsKcal < 0) {
      // A very low calorie target can't fund the protein and fat targets at
      // once. Trim fat to its floor first, then protein, so carbs never go
      // negative and the macros still sum to the calorie figure.
      final minFatKcal = kcal * 0.20;
      fat = (minFatKcal / 9).round();
      carbsKcal = kcal - protein * 4 - minFatKcal;
      if (carbsKcal < 0) {
        protein = ((kcal - minFatKcal) / 4).floor().clamp(0, 100000);
        carbsKcal = 0;
      }
    }

    return PhaseTargets(
      kcal: kcal,
      proteinG: protein,
      carbsG: (carbsKcal / 4).round().clamp(0, 100000),
      fatG: fat,
    );
  }
}
