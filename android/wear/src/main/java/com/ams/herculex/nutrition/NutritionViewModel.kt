package com.ams.herculex.nutrition

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import com.ams.herculex.sync.MacroStore
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

data class NutritionData(
    val calories: Int = 0,
    val protein: Int  = 0,
    val carbs: Int    = 0,
    val fats: Int     = 0,
    val water: Int    = 0,
)

data class NutritionGoals(
    val calorieGoal: Int = 2000,
    val proteinGoal: Int = 150,
    val carbsGoal: Int   = 200,
    val fatGoal: Int     = 65,
    val waterGoal: Int   = 2000,
)

class NutritionViewModel(application: Application) : AndroidViewModel(application) {

    private val _data  = MutableStateFlow(loadData())
    val data: StateFlow<NutritionData> = _data.asStateFlow()

    private val _goals = MutableStateFlow(loadGoals())
    val goals: StateFlow<NutritionGoals> = _goals.asStateFlow()

    // ── Public actions ───────────────────────────────────────────────────────

    fun addCalories(amount: Int) {
        MacroStore.addCalories(ctx(), amount)
        refresh()
    }

    fun addWater(amountMl: Int) {
        MacroStore.addWater(ctx(), amountMl)
        refresh()
    }

    fun logFood(calories: Int, protein: Int, carbs: Int, fats: Int) {
        MacroStore.addFood(ctx(), calories, protein, carbs, fats)
        refresh()
    }

    fun refresh() {
        _data.value  = loadData()
        _goals.value = loadGoals()
    }

    // ── Helpers ──────────────────────────────────────────────────────────────

    private fun ctx() = getApplication<Application>()

    private fun loadData() = NutritionData(
        calories = MacroStore.calories(ctx()),
        protein  = MacroStore.protein(ctx()),
        carbs    = MacroStore.carbs(ctx()),
        fats     = MacroStore.fats(ctx()),
        water    = MacroStore.water(ctx()),
    )

    private fun loadGoals() = NutritionGoals(
        calorieGoal = MacroStore.calorieGoal(ctx()),
        proteinGoal = MacroStore.proteinGoal(ctx()),
        carbsGoal   = MacroStore.carbsGoal(ctx()),
        fatGoal     = MacroStore.fatGoal(ctx()),
        waterGoal   = MacroStore.waterGoal(ctx()),
    )
}
