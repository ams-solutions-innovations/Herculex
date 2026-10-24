package com.ams.herculex.nutrition

import com.ams.herculex.sync.QuickAddFoodItem
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Test

class FoodNutritionStyleTest {

    @Test
    fun testHighProteinYieldsGoldGrade() {
        // e.g. Protein Mousse with 20g protein and 150 kcal (or 264 kcal with 30g protein)
        val food = QuickAddFoodItem(
            foodId = 1,
            name = "Mousse Proteica",
            kcal = 150,
            protein = 20,
            carbs = 8,
            fat = 2,
            portionAmount = 200.0,
            portionUnit = "g",
            portionLabel = "200 g",
        )
        val style = FoodNutritionStyle.resolve(food)
        assertEquals(FoodNutritionGrade.GOLD, style.grade)
        assertNotNull(style.backgroundBrush)
    }

    @Test
    fun testLowCalorieYieldsGreenGrade() {
        // e.g. Cucumber or diet item: 15 kcal per 100g
        val food = QuickAddFoodItem(
            foodId = 2,
            name = "Cucumber",
            kcal = 15,
            protein = 1,
            carbs = 3,
            fat = 0,
            portionAmount = 100.0,
            portionUnit = "g",
            portionLabel = "100 g",
        )
        val style = FoodNutritionStyle.resolve(food)
        assertEquals(FoodNutritionGrade.GREEN, style.grade)
    }

    @Test
    fun testBadMacrosYieldsRedGrade() {
        // e.g. Junk snack: 450 kcal, 28g fat, 50g carbs, 1g protein
        val food = QuickAddFoodItem(
            foodId = 3,
            name = "Chocolate Donut",
            kcal = 450,
            protein = 2,
            carbs = 50,
            fat = 28,
            portionAmount = 1.0,
            portionUnit = "piece",
            portionLabel = "1 piece",
        )
        val style = FoodNutritionStyle.resolve(food)
        assertEquals(FoodNutritionGrade.RED, style.grade)
    }

    @Test
    fun testBalancedFoodYieldsNormalGrade() {
        // e.g. Whole milk 3.5%: 64 kcal, 3g protein, 5g carbs, 4g fat per 100ml
        val food = QuickAddFoodItem(
            foodId = 4,
            name = "Land Mleko 3,5%",
            kcal = 64,
            protein = 3,
            carbs = 5,
            fat = 4,
            portionAmount = 100.0,
            portionUnit = "ml",
            portionLabel = "100.0 ml",
        )
        val style = FoodNutritionStyle.resolve(food)
        assertEquals(FoodNutritionGrade.NORMAL, style.grade)
    }

    @Test
    fun testEffectiveKcalPer100gCalculation() {
        val foodWithGrams = QuickAddFoodItem(
            foodId = 5,
            name = "Greek Yogurt",
            kcal = 120,
            protein = 15,
            carbs = 6,
            fat = 0,
            portionAmount = 200.0,
            portionUnit = "g",
            portionLabel = "200 g",
        )
        assertEquals(60.0, foodWithGrams.effectiveKcalPer100g!!, 0.01)

        val foodWithServing = QuickAddFoodItem(
            foodId = 6,
            name = "Snack Bar",
            kcal = 200,
            protein = 10,
            carbs = 20,
            fat = 5,
            portionAmount = 1.0,
            portionUnit = "serving",
            portionLabel = "1 serving",
            kcalPer100g = 400.0,
        )
        assertEquals(400.0, foodWithServing.effectiveKcalPer100g!!, 0.01)
    }

    @Test
    fun testLoggedFoodEntryResolvesCorrectGrades() {
        val highProteinEntry = com.ams.herculex.sync.LoggedFoodEntry(
            id = 101,
            name = "Chicken Breast",
            mealKey = "lunch",
            portionAmount = 150.0,
            portionUnit = "g",
            portionText = "150g",
            servings = 1.0,
            kcal = 165,
            protein = 31,
            carbs = 0,
            fat = 3,
        )
        assertEquals(FoodNutritionGrade.GOLD, FoodNutritionStyle.resolve(highProteinEntry).grade)

        val badMacroEntry = com.ams.herculex.sync.LoggedFoodEntry(
            id = 102,
            name = "Butter Croissant",
            mealKey = "breakfast",
            portionAmount = 1.0,
            portionUnit = "piece",
            portionText = "1 piece",
            servings = 1.0,
            kcal = 410,
            protein = 5,
            carbs = 45,
            fat = 24,
        )
        assertEquals(FoodNutritionGrade.RED, FoodNutritionStyle.resolve(badMacroEntry).grade)

        val lowCalorieEntry = com.ams.herculex.sync.LoggedFoodEntry(
            id = 103,
            name = "Salad Mix",
            mealKey = "dinner",
            portionAmount = 200.0,
            portionUnit = "g",
            portionText = "200g",
            servings = 1.0,
            kcal = 35,
            protein = 2,
            carbs = 4,
            fat = 0,
        )
        assertEquals(FoodNutritionGrade.GREEN, FoodNutritionStyle.resolve(lowCalorieEntry).grade)

        val balancedEntry = com.ams.herculex.sync.LoggedFoodEntry(
            id = 104,
            name = "Kava + med",
            mealKey = "breakfast",
            portionAmount = 1.0,
            portionUnit = "serv",
            portionText = "1 serv",
            servings = 1.0,
            kcal = 156,
            protein = 5,
            carbs = 24,
            fat = 5,
        )
        assertEquals(FoodNutritionGrade.NORMAL, FoodNutritionStyle.resolve(balancedEntry).grade)
    }
}
