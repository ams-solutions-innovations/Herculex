import 'package:flutter/material.dart';

enum Meal {
  breakfast,
  lunch,
  dinner,
  snack;

  String get label => switch (this) {
        Meal.breakfast => 'Breakfast',
        Meal.lunch => 'Lunch',
        Meal.dinner => 'Dinner',
        Meal.snack => 'Snacks',
      };

  IconData get icon => switch (this) {
        Meal.breakfast => Icons.free_breakfast_outlined,
        Meal.lunch => Icons.lunch_dining,
        Meal.dinner => Icons.dinner_dining,
        Meal.snack => Icons.cookie_outlined,
      };

  static Meal fromName(String name) =>
      Meal.values.firstWhere((m) => m.name == name, orElse: () => Meal.snack);
}

String dateIso(DateTime d) {
  final y = d.year.toString().padLeft(4, '0');
  final m = d.month.toString().padLeft(2, '0');
  final dd = d.day.toString().padLeft(2, '0');
  return '$y-$m-$dd';
}

DateTime parseDateIso(String s) {
  final parts = s.split('-');
  return DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
}
