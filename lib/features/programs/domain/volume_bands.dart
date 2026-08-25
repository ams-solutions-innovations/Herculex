/// Weekly working-set bands per muscle group, used by the builder's volume
/// guardrail.
///
/// The bands start from published population priors and shrink toward what the
/// user has actually sustained as evidence accumulates. A brand-new user gets a
/// sane program on day one; a user with a year of history gets their own
/// ceiling rather than a textbook's.
library;

/// How a week's planned volume reads against the band.
enum VolumeVerdict {
  /// Below the minimum that reliably drives adaptation.
  low('Light', 'Below the volume that usually drives progress'),

  /// The productive middle.
  good('On target', 'In the productive range'),

  /// Above the adaptive sweet spot but still recoverable.
  high('Hard', 'High — sustainable for a block, not forever'),

  /// Past what can be recovered from.
  tooMuch('Over', 'More than you are likely to recover from');

  const VolumeVerdict(this.label, this.blurb);

  /// Shown on the bar. Deliberately plain language — the user should never
  /// have to learn what MEV stands for.
  final String label;
  final String blurb;
}

/// The minimum-effective / adaptive-maximum / recoverable-maximum triple for
/// one muscle group, in weekly working sets.
class VolumeBand {
  const VolumeBand({
    required this.minimum,
    required this.adaptive,
    required this.maximum,
    this.personalized = false,
  });

  /// Below this, progress is unlikely (MEV).
  final int minimum;

  /// Top of the productive range (MAV).
  final int adaptive;

  /// Beyond this, recovery fails (MRV).
  final int maximum;

  /// True once the user's own history carries more weight than the prior.
  final bool personalized;

  VolumeVerdict verdict(num weeklySets) {
    if (weeklySets < minimum) return VolumeVerdict.low;
    if (weeklySets <= adaptive) return VolumeVerdict.good;
    if (weeklySets <= maximum) return VolumeVerdict.high;
    return VolumeVerdict.tooMuch;
  }

  /// 0 … 1 position on the bar, saturating just past [maximum] so an absurd
  /// number still renders.
  double fill(num weeklySets) {
    if (maximum <= 0) return 0.0;
    return (weeklySets / (maximum * 1.15)).clamp(0.0, 1.0).toDouble();
  }
}

/// What the user has demonstrably tolerated for a muscle group.
class VolumeTolerance {
  const VolumeTolerance({
    required this.weeksObserved,
    required this.sustainedSets,
  });

  /// Distinct training weeks the estimate is based on.
  final int weeksObserved;

  /// The highest weekly set count held for two or more consecutive weeks
  /// without a drop in performance on that group's lifts.
  final double sustainedSets;
}

abstract final class VolumeBands {
  /// Population priors for the 19 tracked groups, as
  /// `(minimum, adaptive, maximum)` weekly working sets.
  ///
  /// These are starting points, not truth — they exist so a user with no
  /// history still gets a program that is neither pointless nor injurious.
  static const priors = <String, (int, int, int)>{
    'Chest': (8, 16, 22),
    'Back': (10, 18, 25),
    'Lats': (10, 18, 25),
    'Traps': (4, 12, 20),
    'Front Delts': (4, 10, 14),
    'Side Delts': (8, 18, 26),
    'Rear Delts': (6, 16, 25),
    'Biceps': (8, 16, 22),
    'Triceps': (6, 14, 20),
    'Forearms': (4, 10, 16),
    'Abs': (6, 16, 25),
    'Obliques': (4, 12, 20),
    'Neck': (3, 8, 12),
    'Quads': (8, 16, 20),
    'Hamstrings': (6, 14, 20),
    'Glutes': (4, 12, 16),
    'Calves': (8, 16, 22),
    'Adductors': (4, 10, 16),
    'Abductors': (4, 10, 16),
  };

  /// Fallback for a group with no prior — deliberately wide.
  static const _fallback = (6, 14, 20);

  /// Weeks of personal data at which history and prior carry equal weight.
  /// Low enough to adapt within a block, high enough that one deload week does
  /// not rewrite the band.
  static const shrinkageWeeks = 4;

  /// Below this many observed weeks the band is still labelled generic.
  static const _personalizedAfterWeeks = 6;

  static VolumeBand forGroup(String group, {VolumeTolerance? tolerance}) {
    final prior = priors[group] ?? _fallback;

    if (tolerance == null || tolerance.weeksObserved <= 0) {
      return VolumeBand(
        minimum: prior.$1,
        adaptive: prior.$2,
        maximum: prior.$3,
      );
    }

    // The personal signal is a ceiling; the shape of the band around it keeps
    // the prior's proportions.
    final n = tolerance.weeksObserved;
    final blend = n / (n + shrinkageWeeks);
    final personalMax = tolerance.sustainedSets;
    final priorMax = prior.$3.toDouble();
    final maximum = priorMax * (1 - blend) + personalMax * blend;

    final minRatio = prior.$1 / priorMax;
    final adaptiveRatio = prior.$2 / priorMax;

    return VolumeBand(
      minimum: (maximum * minRatio).round().clamp(1, 60),
      adaptive: (maximum * adaptiveRatio).round().clamp(2, 70),
      maximum: maximum.round().clamp(3, 80),
      personalized: n >= _personalizedAfterWeeks,
    );
  }

  /// Convenience for the builder's guardrail pass.
  static Map<String, VolumeVerdict> verdicts(
    Map<String, num> weeklySetsByGroup, {
    Map<String, VolumeTolerance> tolerances = const {},
  }) {
    return {
      for (final e in weeklySetsByGroup.entries)
        e.key: forGroup(e.key, tolerance: tolerances[e.key]).verdict(e.value),
    };
  }
}
