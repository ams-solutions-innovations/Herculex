/// Something everyone can picture, with a round-number mass. The masses are
/// typical values for a fun comparison, not reference data.
class WeightEquivalent {
  const WeightEquivalent(this.singular, this.plural, this.massKg);

  /// "a car" — used when the count rounds to one.
  final String singular;

  /// "cars".
  final String plural;
  final double massKg;
}

/// Objects for a single heavy set (tens to hundreds of kg).
const singleLiftEquivalents = <WeightEquivalent>[
  WeightEquivalent('a washing machine', 'washing machines', 70),
  WeightEquivalent('a giant panda', 'giant pandas', 100),
  WeightEquivalent('a gorilla', 'gorillas', 160),
  WeightEquivalent('a grizzly bear', 'grizzly bears', 270),
  WeightEquivalent('a grand piano', 'grand pianos', 400),
];

/// Objects for accumulated tonnage (a session, a week, a lifetime).
const tonnageEquivalents = <WeightEquivalent>[
  WeightEquivalent('a grand piano', 'grand pianos', 400),
  WeightEquivalent('a car', 'cars', 1500),
  WeightEquivalent('a rhino', 'rhinos', 2300),
  WeightEquivalent('an African elephant', 'African elephants', 6000),
  WeightEquivalent('a T. rex', 'T. rexes', 8000),
  WeightEquivalent('a double-decker bus', 'double-decker buses', 12000),
  WeightEquivalent('a humpback whale', 'humpback whales', 30000),
  WeightEquivalent('a blue whale', 'blue whales', 150000),
  WeightEquivalent('an empty Boeing 747', 'empty Boeing 747s', 180000),
  WeightEquivalent('the International Space Station', 'Space Stations', 420000),
];

/// [kg] expressed as a count of one [equivalent].
class WeightComparison {
  const WeightComparison(this.equivalent, this.count);

  final WeightEquivalent equivalent;
  final double count;

  /// "a car", "2.4 cars", "12 cars".
  String get phrase {
    if (count < 1.05) return equivalent.singular;
    final n = count >= 10
        ? count.round().toString()
        : count.toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '');
    return '$n ${equivalent.plural}';
  }

  /// The heaviest object [kg] covers at least once; null when [kg] is lighter
  /// than the lightest one.
  static WeightComparison? pick(double kg, List<WeightEquivalent> catalog) {
    if (!kg.isFinite || kg <= 0) return null;
    WeightEquivalent? best;
    for (final e in catalog) {
      if (kg >= e.massKg && (best == null || e.massKg > best.massKg)) best = e;
    }
    return best == null ? null : WeightComparison(best, kg / best.massKg);
  }
}
