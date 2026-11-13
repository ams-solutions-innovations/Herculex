import 'package:herculex/features/supplements/domain/supplement.dart';

/// A ready-made supplement the user picks instead of typing one in.
///
/// Presets are the only way supplements enter the app besides "custom": no
/// scanning, no lookups. Each preset has a stable [key], so Labs sees "creatine"
/// as one product no matter how the user edits the name or dose.
class SupplementPreset {
  final String key;
  final String name;

  /// One line shown under the name in the picker.
  final String blurb;

  final double doseAmount;
  final String doseUnit;

  /// What one default dose contributes to the diary's micronutrient totals.
  final Map<String, double> nutrients;

  /// Creatine-style loading phase defaults. Null when the preset has none.
  final double? loadingDoseAmount;
  final int? loadingDays;

  const SupplementPreset({
    required this.key,
    required this.name,
    required this.blurb,
    required this.doseAmount,
    required this.doseUnit,
    this.nutrients = const {},
    this.loadingDoseAmount,
    this.loadingDays,
  });

  bool get supportsLoading => loadingDoseAmount != null;

  /// Deterministic id: adding the same preset twice can be detected, and the
  /// Labs identity (`supplement:<name> [<id>]`) is the same on every device.
  String get supplementId => 'preset_$key';

  Supplement toSupplement() => Supplement(
    id: supplementId,
    name: name,
    presetKey: key,
    doseAmount: doseAmount,
    doseUnit: doseUnit,
    nutrients: nutrients,
  );

  static SupplementPreset? byKey(String? key) {
    if (key == null) return null;
    for (final p in supplementPresets) {
      if (p.key == key) return p;
    }
    return null;
  }
}

/// Order is the order shown in the picker.
const supplementPresets = <SupplementPreset>[
  SupplementPreset(
    key: 'creatine',
    name: 'Creatine',
    blurb: 'Monohydrate · optional loading phase',
    doseAmount: 5,
    doseUnit: 'g',
    loadingDoseAmount: 20,
    loadingDays: 7,
  ),
  SupplementPreset(
    key: 'omega3',
    name: 'Omega-3',
    blurb: 'Fish oil · EPA + DHA',
    doseAmount: 1,
    doseUnit: 'g',
    nutrients: {'omega_3': 1},
  ),
  SupplementPreset(
    key: 'multivitamin',
    name: 'Multivitamin',
    blurb: 'Daily all-round cover',
    doseAmount: 1,
    doseUnit: 'capsule',
  ),
  SupplementPreset(
    key: 'zma',
    name: 'ZMA',
    blurb: 'Zinc + magnesium + B6 · before bed',
    doseAmount: 3,
    doseUnit: 'capsule',
    nutrients: {'zinc': 30, 'magnesium': 450},
  ),
  SupplementPreset(
    key: 'vitamin_d',
    name: 'Vitamin D3',
    blurb: '1000 IU',
    doseAmount: 25,
    doseUnit: 'µg',
    nutrients: {'vitamin_d': 25},
  ),
  SupplementPreset(
    key: 'magnesium',
    name: 'Magnesium',
    blurb: 'Glycinate / citrate',
    doseAmount: 300,
    doseUnit: 'mg',
    nutrients: {'magnesium': 300},
  ),
  SupplementPreset(
    key: 'zinc',
    name: 'Zinc',
    blurb: 'Daily mineral',
    doseAmount: 15,
    doseUnit: 'mg',
    nutrients: {'zinc': 15},
  ),
  SupplementPreset(
    key: 'vitamin_c',
    name: 'Vitamin C',
    blurb: 'Ascorbic acid',
    doseAmount: 500,
    doseUnit: 'mg',
    nutrients: {'vitamin_c': 500},
  ),
  SupplementPreset(
    key: 'vitamin_b12',
    name: 'Vitamin B12',
    blurb: 'Cobalamin',
    doseAmount: 250,
    doseUnit: 'µg',
    nutrients: {'vitamin_b12': 250},
  ),
  SupplementPreset(
    key: 'caffeine',
    name: 'Caffeine',
    blurb: 'Pre-workout',
    doseAmount: 200,
    doseUnit: 'mg',
    nutrients: {'caffeine': 200},
  ),
  SupplementPreset(
    key: 'ashwagandha',
    name: 'Ashwagandha',
    blurb: 'Stress · sleep',
    doseAmount: 600,
    doseUnit: 'mg',
  ),
  SupplementPreset(
    key: 'melatonin',
    name: 'Melatonin',
    blurb: 'Sleep onset',
    doseAmount: 1,
    doseUnit: 'mg',
  ),
];
