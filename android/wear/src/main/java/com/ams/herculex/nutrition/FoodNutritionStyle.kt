package com.ams.herculex.nutrition

import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import com.ams.herculex.sync.QuickAddFoodItem

/**
 * Nutrition grade determining background gradient highlights:
 * - [GOLD]: High protein efficiency (≥ 10g protein / 100 kcal)
 * - [GREEN]: Low calories (≤ 50 kcal / 100g or portion ≤ 60 kcal)
 * - [RED]: Bad macros (unfavourable ratio dominated by fat/carbs with negligible protein)
 * - [NORMAL]: Balanced / normal macros (no special highlight)
 */
enum class FoodNutritionGrade {
    GOLD,
    GREEN,
    RED,
    NORMAL,
}

object FoodInsights {
    /**
     * Evaluates food macros to determine its nutrition highlight grade,
     * mirroring the logic on the phone app (FoodInsights.gradeFor).
     */
    fun gradeFor(
        name: String? = null,
        kcal: Double,
        proteinG: Double,
        carbsG: Double,
        fatG: Double,
        kcalPer100g: Double? = null,
    ): FoodNutritionGrade {
        if (name == "—" || (kcal <= 0 && proteinG <= 0 && carbsG <= 0 && fatG <= 0)) {
            return FoodNutritionGrade.NORMAL
        }

        // 1. Gold gradient: ≥ 10g protein per 100 kcal
        // "ce ima hrana 10g beljakovin na 100kcal je to zlat gradient"
        if (kcal > 0 && ((proteinG / kcal) * 100.0 >= 10.0 || proteinG * 10.0 >= kcal)) {
            return FoodNutritionGrade.GOLD
        }

        val totalMacroKcal = proteinG * 4.0 + carbsG * 4.0 + fatG * 9.0
        val totalEnergyKcal = if (kcal > 0) kcal else totalMacroKcal
        val proteinShare = if (totalEnergyKcal > 0) (proteinG * 4.0) / totalEnergyKcal else 0.0
        val carbsShare = if (totalEnergyKcal > 0) (carbsG * 4.0) / totalEnergyKcal else 0.0
        val fatShare = if (totalEnergyKcal > 0) (fatG * 9.0) / totalEnergyKcal else 0.0

        // Bad macros detection:
        // "ce so slabi makroti je rdec gradient"
        val isBadMacros = totalEnergyKcal > 0 && (
            (fatShare >= 0.55 && proteinShare < 0.08) ||
            (fatShare >= 0.38 && carbsShare >= 0.40 && proteinShare < 0.08) ||
            (carbsShare >= 0.85 && proteinShare < 0.04 && kcal >= 80)
        )

        // 2. Green gradient: Low calories
        // "ce so nizke kalorije je zelen"
        val isLowCalorie = !isBadMacros && (
            (kcalPer100g != null && kcalPer100g > 0 && kcalPer100g <= 50.0) ||
            (kcal <= 60 && fatShare < 0.45)
        )

        if (isLowCalorie) {
            return FoodNutritionGrade.GREEN
        }

        if (isBadMacros) {
            return FoodNutritionGrade.RED
        }

        // 4. Normal: No gradient
        // "pa ce je normalno pa ga ni"
        return FoodNutritionGrade.NORMAL
    }
}

/**
 * Visual presentation style for food rows on Wear OS based on [FoodNutritionGrade].
 */
data class FoodNutritionStyle(
    val grade: FoodNutritionGrade,
    val backgroundBrush: Brush,
    val containerColor: Color,
    val borderColor: Color,
    val plusBadgeColor: Color,
    val contentColor: Color = Color.White,
    val secondaryColor: Color = Color(0xFFA0AABF),
) {
    companion object {
        private val BaseSurface = Color(0xFF202636)
        private val DefaultBorder = Color(0xFF323B52)

        fun resolve(food: QuickAddFoodItem): FoodNutritionStyle {
            val grade = FoodInsights.gradeFor(
                name = food.name,
                kcal = food.kcal.toDouble(),
                proteinG = food.protein.toDouble(),
                carbsG = food.carbs.toDouble(),
                fatG = food.fat.toDouble(),
                kcalPer100g = food.effectiveKcalPer100g,
            )
            return resolve(grade)
        }

        fun resolve(entry: com.ams.herculex.sync.LoggedFoodEntry): FoodNutritionStyle {
            val kcalPer100g = if (entry.portionUnit.equals("g", ignoreCase = true) && entry.portionAmount > 0) {
                (entry.kcal.toDouble() / entry.portionAmount) * 100.0
            } else null
            val grade = FoodInsights.gradeFor(
                name = entry.name,
                kcal = entry.kcal.toDouble(),
                proteinG = entry.protein.toDouble(),
                carbsG = entry.carbs.toDouble(),
                fatG = entry.fat.toDouble(),
                kcalPer100g = kcalPer100g,
            )
            return resolve(grade)
        }

        fun resolve(grade: FoodNutritionGrade): FoodNutritionStyle {
            return when (grade) {
                FoodNutritionGrade.GOLD -> {
                    // Gold gradient: subtle warm gold tone on left, fading to base dark surface
                    val goldAccent = Color(0xFFF59E0B)
                    val startColor = Color(0xFF4C3A1E)
                    FoodNutritionStyle(
                        grade = grade,
                        backgroundBrush = Brush.horizontalGradient(
                            listOf(startColor, BaseSurface)
                        ),
                        containerColor = startColor,
                        borderColor = goldAccent.copy(alpha = 0.45f),
                        plusBadgeColor = Color(0xFF38290E),
                        secondaryColor = Color(0xFFD6C8AF),
                    )
                }
                FoodNutritionGrade.GREEN -> {
                    // Green gradient: subtle emerald tone on left, fading to base dark surface
                    val greenAccent = Color(0xFF10B981)
                    val startColor = Color(0xFF193D30)
                    FoodNutritionStyle(
                        grade = grade,
                        backgroundBrush = Brush.horizontalGradient(
                            listOf(startColor, BaseSurface)
                        ),
                        containerColor = startColor,
                        borderColor = greenAccent.copy(alpha = 0.42f),
                        plusBadgeColor = Color(0xFF123426),
                        secondaryColor = Color(0xFFA5D6A7),
                    )
                }
                FoodNutritionGrade.RED -> {
                    // Red gradient: subtle crimson/red tone on left, fading to base dark surface
                    val redAccent = Color(0xFFEF4444)
                    val startColor = Color(0xFF482227)
                    FoodNutritionStyle(
                        grade = grade,
                        backgroundBrush = Brush.horizontalGradient(
                            listOf(startColor, BaseSurface)
                        ),
                        containerColor = startColor,
                        borderColor = redAccent.copy(alpha = 0.42f),
                        plusBadgeColor = Color(0xFF3B151A),
                        secondaryColor = Color(0xFFE5B5B5),
                    )
                }
                FoodNutritionGrade.NORMAL -> {
                    FoodNutritionStyle(
                        grade = grade,
                        backgroundBrush = Brush.horizontalGradient(
                            listOf(BaseSurface, BaseSurface)
                        ),
                        containerColor = BaseSurface,
                        borderColor = DefaultBorder,
                        plusBadgeColor = Color(0xFF141926),
                        secondaryColor = Color(0xFFA0AABF),
                    )
                }
            }
        }
    }
}
