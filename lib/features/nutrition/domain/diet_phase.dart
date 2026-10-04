import 'package:herculex/features/nutrition/domain/phase_eligibility.dart';

/// The dieting phase a set of daily targets is written for (§5).
///
/// Picking a phase in the target editor rewrites the numbers rather than just
/// labelling them, so the saved target already reflects the deficit or
/// surplus — nothing downstream has to know a phase was involved.
enum DietPhase {
  maintain('Vzdrževanje'),
  maingain('Čista rast'),
  cut('Redukcija'),
  bulk('Masa'),
  recomp('Rekompozicija');

  const DietPhase(this.label);
  final String label;

  /// Confirmation-button text: «Shrani Redukcija» itd., «Shrani cilj» za vzdrževanje.
  String get saveLabel => switch (this) {
    DietPhase.maintain => 'Shrani cilj',
    _ => 'Shrani: $label',
  };

  /// One-line explanation of what this phase does to calories and macros.
  String get subtitle => switch (this) {
    DietPhase.cut =>
      'Kalorični primanjkljaj za izgubo maščobe z veliko beljakovinami za zaščito mišične mase (2,2 g beljakovin/kg).',
    DietPhase.bulk =>
      'Kalorični presežek z veliko ogljikovimi hidrati za največjo moč in rast mišic.',
    DietPhase.maingain =>
      'Majhen, nadzorovan presežek z 2,2 g/kg beljakovin za postopno, pretežno čisto rast mišic.',
    DietPhase.maintain =>
      'Brez kalorične razlike (TDEE) in 1,8 g/kg beljakovin za stabilno težo in okrevanje.',
    DietPhase.recomp =>
      'Rekompozicija telesa: brez kalorične razlike (TDEE) z 2,2 g/kg beljakovin za gradnjo mišic in izgubo maščobe pri stabilni teži.',
  };
}

/// Pace preset for weekly weight adjustment or surplus/deficit.
class DietPaceOption {
  final double weeklyKg;
  final int kcalDelta;
  final String label;
  final String description;

  const DietPaceOption({
    required this.weeklyKg,
    required this.kcalDelta,
    required this.label,
    required this.description,
  });
}

/// A calorie/macro set, as produced by the phase maths.
class PhaseTargets {
  final int kcal;
  final int proteinG;
  final int carbsG;
  final int fatG;
  final int deltaKcal;

  const PhaseTargets({
    required this.kcal,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    this.deltaKcal = 0,
  });
}

/// Applies a dieting phase to a maintenance baseline.
class DietPhaseCalculator {
  /// Default calorie shift, as a share of maintenance. A 20 % cut and a 10 %
  /// surplus are the conventional starting points: aggressive enough to move
  /// the scale, mild enough not to shed muscle or add excess fat.
  static const defaultCutPct = 20.0;
  static const defaultBulkPct = 10.0;
  static const defaultMaingainSurplusKcal = 150;

  /// Grams of protein per kg of bodyweight. Protein is held high in a cut and
  /// maingain — it's the macro that protects lean mass in a deficit and fuels
  /// recomp in a lean state — and adequate in a bulk, leaving room for carbs.
  static const cutProteinPerKg = 2.2;
  static const maingainProteinPerKg = 2.2;
  static const maintainProteinPerKg = 1.8;
  static const bulkProteinPerKg = 1.8;
  static const recompProteinPerKg = 2.2;

  /// Share of calories from fat. Kept above ~20-25 % for hormonal
  /// health; the rest of the budget goes to carbs.
  static const cutFatShare = 0.25;
  static const maingainFatShare = 0.25;
  static const maintainFatShare = 0.275;
  static const bulkFatShare = 0.25;
  static const recompFatShare = 0.25;

  /// Standard pace presets for each dieting phase.
  static List<DietPaceOption> paceOptionsFor(DietPhase phase) =>
      switch (phase) {
        DietPhase.cut => const [
          DietPaceOption(
            weeklyKg: 0.25,
            kcalDelta: -250,
            label: '0,25 kg/ted (blago)',
            description: 'Minimalen primanjkljaj za ohranitev največje moči.',
          ),
          DietPaceOption(
            weeklyKg: 0.50,
            kcalDelta: -500,
            label: '0,50 kg/ted (standardno)',
            description: 'Standardni priporočeni tempo za izgubo maščobe.',
          ),
          DietPaceOption(
            weeklyKg: 0.75,
            kcalDelta: -750,
            label: '0,75 kg/ted (hitro)',
            description: 'Hitra izguba maščobe z velikim vnosom beljakovin.',
          ),
          DietPaceOption(
            weeklyKg: 1.00,
            kcalDelta: -1000,
            label: '1,00 kg/ted (agresivno)',
            description: 'Največji tempo (do 1 kg na teden).',
          ),
        ],
        DietPhase.bulk => const [
          DietPaceOption(
            weeklyKg: 0.25,
            kcalDelta: 250,
            label: '0,25 kg/ted (čisto)',
            description: 'Čist presežek z minimalnim pridobivanjem maščobe.',
          ),
          DietPaceOption(
            weeklyKg: 0.50,
            kcalDelta: 500,
            label: '0,50 kg/ted (standardno)',
            description: 'Optimalen tempo za gradnjo mišic in moči.',
          ),
          DietPaceOption(
            weeklyKg: 0.75,
            kcalDelta: 750,
            label: '0,75 kg/ted (hitro)',
            description: 'Hitro pridobivanje teže in okrevanje.',
          ),
          DietPaceOption(
            weeklyKg: 1.00,
            kcalDelta: 1000,
            label: '1,00 kg/ted (agresivno)',
            description: 'Velik presežek za največjo maso.',
          ),
        ],
        DietPhase.maingain => const [
          DietPaceOption(
            weeklyKg: 0.05,
            kcalDelta: 75,
            label: 'Minimalno (+75 kcal)',
            description: 'Najmanjši presežek za skoraj povsem čisto rast.',
          ),
          DietPaceOption(
            weeklyKg: 0.15,
            kcalDelta: 150,
            label: 'Čisto (+150 kcal)',
            description: 'Počasna čista rast mišic z minimalno maščobe.',
          ),
          DietPaceOption(
            weeklyKg: 0.25,
            kcalDelta: 250,
            label: 'Progresivno (+250 kcal)',
            description: 'Enakomeren napredek v moči in hipertrofiji.',
          ),
        ],
        DietPhase.maintain => const [
          DietPaceOption(
            weeklyKg: 0.0,
            kcalDelta: 0,
            label: 'Vzdrževanje (0 kcal)',
            description: 'Popolno kalorično ravnovesje (TDEE).',
          ),
        ],
        DietPhase.recomp => const [
          DietPaceOption(
            weeklyKg: 0.0,
            kcalDelta: 0,
            label: 'Rekompozicija (0 kcal)',
            description:
                'Rekompozicija telesa pri stabilni teži z 2,2 g/kg beljakovin.',
          ),
        ],
      };

  /// Rewrites [baselineKcal] and the macro split for [phase].
  ///
  /// [bodyweightKg] drives protein; without it protein falls back to a share
  /// of calories so the function still returns something sensible.
  /// [pctOverride] replaces the default shift percentage when specified.
  /// [weeklyRateKg] allows explicit kg/week pacing (e.g. 0.5 kg/w = 500 kcal).
  /// [calorieDeltaOverride] allows explicit kcal adjustment (e.g. -500, +150).
  /// [minProteinG] and [minCaloriesKcal] enforce lower bounds for protein and calorie targets.
  /// [eligibility] clamps the calorie delta for restricted members (under 18,
  /// unknown age, low-confidence assessment); null leaves behaviour unchanged.
  static PhaseTargets apply({
    required DietPhase phase,
    required int baselineKcal,
    double? bodyweightKg,
    double? pctOverride,
    double? weeklyRateKg,
    int? calorieDeltaOverride,
    int? minProteinG,
    int? minCaloriesKcal,
    PhaseEligibility? eligibility,
  }) {
    int delta = 0;
    if (calorieDeltaOverride != null) {
      delta = calorieDeltaOverride;
    } else if (pctOverride != null) {
      final sign = phase == DietPhase.cut
          ? -1.0
          : (phase == DietPhase.maintain ? 0.0 : 1.0);
      delta = (baselineKcal * (sign * pctOverride / 100)).round();
    } else if (weeklyRateKg != null) {
      final sign = phase == DietPhase.cut
          ? -1.0
          : (phase == DietPhase.maintain ? 0.0 : 1.0);
      delta = (sign * weeklyRateKg * 1000).round();
    } else {
      delta = switch (phase) {
        DietPhase.maintain => 0,
        DietPhase.recomp => 0,
        DietPhase.maingain => defaultMaingainSurplusKcal,
        DietPhase.cut => -(baselineKcal * (defaultCutPct / 100)).round(),
        DietPhase.bulk => (baselineKcal * (defaultBulkPct / 100)).round(),
      };
    }

    if (eligibility != null) delta = eligibility.clampDelta(phase, delta);

    var kcal = (baselineKcal + delta).clamp(0, 20000);
    if (minCaloriesKcal != null && minCaloriesKcal > 0) {
      if (kcal < minCaloriesKcal) {
        kcal = minCaloriesKcal;
      }
    }

    if (kcal <= 0) {
      return const PhaseTargets(
        kcal: 0,
        proteinG: 0,
        carbsG: 0,
        fatG: 0,
        deltaKcal: 0,
      );
    }

    final proteinPerKg = switch (phase) {
      DietPhase.cut => cutProteinPerKg,
      DietPhase.maingain => maingainProteinPerKg,
      DietPhase.bulk => bulkProteinPerKg,
      DietPhase.maintain => maintainProteinPerKg,
      DietPhase.recomp => recompProteinPerKg,
    };
    final fatShare = switch (phase) {
      DietPhase.cut => cutFatShare,
      DietPhase.maingain => maingainFatShare,
      DietPhase.bulk => bulkFatShare,
      DietPhase.maintain => maintainFatShare,
      DietPhase.recomp => recompFatShare,
    };

    // Protein first, then fat, then carbs take whatever is left.
    var protein = bodyweightKg != null
        ? (bodyweightKg * proteinPerKg).round()
        : (kcal * 0.30 / 4).round();

    if (minProteinG != null && minProteinG > 0) {
      if (protein < minProteinG) {
        protein = minProteinG;
      }
    }

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
      deltaKcal: delta,
    );
  }
}
