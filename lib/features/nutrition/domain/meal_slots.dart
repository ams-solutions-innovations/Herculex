import 'package:flutter/material.dart';

/// User-visible diary meal section. [key] is stored in FoodEntries so renaming
/// a slot does not rewrite historical logs.
class MealSlot {
  final String key;
  final String label;

  const MealSlot({required this.key, required this.label});

  bool get isBuiltIn => builtInKeys.contains(key);

  IconData get icon => switch (key) {
    'breakfast' => Icons.free_breakfast_outlined,
    'lunch' => Icons.lunch_dining,
    'dinner' => Icons.dinner_dining,
    'snack' => Icons.cookie_outlined,
    _ => Icons.restaurant_outlined,
  };

  Map<String, dynamic> toJson() => {'key': key, 'label': label};

  factory MealSlot.fromJson(Map<String, dynamic> json) => MealSlot(
    key: json['key']?.toString() ?? 'custom',
    label: json['label']?.toString() ?? 'Meal',
  );

  static const builtInKeys = {'breakfast', 'lunch', 'dinner', 'snack'};
  static const defaults = <MealSlot>[
    MealSlot(key: 'breakfast', label: 'Breakfast'),
    MealSlot(key: 'lunch', label: 'Lunch'),
    MealSlot(key: 'dinner', label: 'Dinner'),
    MealSlot(key: 'snack', label: 'Snacks'),
  ];
}
