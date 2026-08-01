class NutrientDefinition {
  final String id;
  final String label;
  final String unit;
  final double? dailyTarget;

  const NutrientDefinition(this.id, this.label, this.unit, {this.dailyTarget});
}

/// Stable IDs shared by the JSON catalogue, totals and user preferences.
const trackedNutrients = <NutrientDefinition>[
  NutrientDefinition('fiber', 'Fiber', 'g', dailyTarget: 28),
  NutrientDefinition('sugars', 'Sugars', 'g', dailyTarget: 30),
  NutrientDefinition('saturated_fat', 'Saturated Fat', 'g', dailyTarget: 20),
  NutrientDefinition('trans_fat', 'Trans Fat', 'g', dailyTarget: 2),
  NutrientDefinition('sodium', 'Sodium', 'mg', dailyTarget: 2300),
  NutrientDefinition('potassium', 'Potassium', 'mg', dailyTarget: 4700),
  NutrientDefinition('cholesterol', 'Cholesterol', 'mg', dailyTarget: 300),
  NutrientDefinition('calcium', 'Calcium', 'mg', dailyTarget: 1000),
  NutrientDefinition('iron', 'Iron', 'mg', dailyTarget: 18),
  NutrientDefinition('magnesium', 'Magnesium', 'mg', dailyTarget: 420),
  NutrientDefinition('zinc', 'Zinc', 'mg', dailyTarget: 11),
  NutrientDefinition('vitamin_a', 'Vitamin A', 'µg', dailyTarget: 900),
  NutrientDefinition('vitamin_b12', 'Vitamin B12', 'µg', dailyTarget: 2.4),
  NutrientDefinition('vitamin_c', 'Vitamin C', 'mg', dailyTarget: 90),
  NutrientDefinition('vitamin_d', 'Vitamin D', 'µg', dailyTarget: 20),
  NutrientDefinition('vitamin_e', 'Vitamin E', 'mg', dailyTarget: 15),
  NutrientDefinition('vitamin_k', 'Vitamin K', 'µg', dailyTarget: 120),
  NutrientDefinition('folate', 'Folate', 'µg', dailyTarget: 400),
  NutrientDefinition('omega_3', 'Omega 3', 'g', dailyTarget: 1.6),
  NutrientDefinition('caffeine', 'Caffeine', 'mg', dailyTarget: 400),
];

