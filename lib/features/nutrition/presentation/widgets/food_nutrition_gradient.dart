import 'package:flutter/material.dart';
import 'package:herculex/design_system/theme/colors.dart';
import 'package:herculex/features/nutrition/domain/food_insights.dart';

/// Presentation styling for food cards based on [FoodNutritionGrade].
class FoodNutritionStyle {
  final Gradient? gradient;
  final Color color;
  final Color borderColor;

  const FoodNutritionStyle({
    this.gradient,
    required this.color,
    required this.borderColor,
  });

  /// Resolves the subtle gradient, surface color, and border tint according to [grade].
  static FoodNutritionStyle resolve(
    BuildContext context,
    FoodNutritionGrade grade,
  ) {
    final baseSurface = AppColors.surfaceContainer;
    final defaultBorder = AppColors.outlineVariant.withValues(alpha: 0.3);

    switch (grade) {
      case FoodNutritionGrade.gold:
        const goldColor = Color(0xFFF59E0B);
        return FoodNutritionStyle(
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              Color.alphaBlend(goldColor.withValues(alpha: 0.16), baseSurface),
              baseSurface,
            ],
          ),
          color: baseSurface,
          borderColor: goldColor.withValues(alpha: 0.38),
        );

      case FoodNutritionGrade.green:
        const greenColor = Color(0xFF10B981);
        return FoodNutritionStyle(
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              Color.alphaBlend(greenColor.withValues(alpha: 0.14), baseSurface),
              baseSurface,
            ],
          ),
          color: baseSurface,
          borderColor: greenColor.withValues(alpha: 0.32),
        );

      case FoodNutritionGrade.red:
        const redColor = Color(0xFFEF4444);
        return FoodNutritionStyle(
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              Color.alphaBlend(redColor.withValues(alpha: 0.14), baseSurface),
              baseSurface,
            ],
          ),
          color: baseSurface,
          borderColor: redColor.withValues(alpha: 0.32),
        );

      case FoodNutritionGrade.normal:
        return FoodNutritionStyle(
          gradient: null,
          color: baseSurface,
          borderColor: defaultBorder,
        );
    }
  }
}
