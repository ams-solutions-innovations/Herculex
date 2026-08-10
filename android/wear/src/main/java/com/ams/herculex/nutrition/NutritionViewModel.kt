package com.ams.herculex.nutrition

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.ams.herculex.sync.FastingSnapshot
import com.ams.herculex.sync.FastingStore
import com.ams.herculex.sync.MacroStore
import com.ams.herculex.sync.QuickAddFoodItem
import com.ams.herculex.sync.QuickAddMealSlot
import com.ams.herculex.sync.QuickAddStore
import com.ams.herculex.sync.WearDataLayerSyncManager
import kotlinx.coroutines.launch
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

data class NutritionData(
    val calories: Int = 0,
    val protein: Int  = 0,
    val carbs: Int    = 0,
    val fats: Int     = 0,
    val water: Int    = 0,
    val fasting: String = "0h 0m",
    val fastingSnapshot: FastingSnapshot = FastingSnapshot(),
    val weeklyTonnage: Float = 0f,
    val weeklySets: Int = 0,
    val weeklyVolumeJson: String = "[]",
)

data class NutritionGoals(
    val calorieGoal: Int = 2000,
    val proteinGoal: Int = 150,
    val carbsGoal: Int   = 200,
    val fatGoal: Int     = 65,
    val waterGoal: Int   = 2000,
)

class NutritionViewModel(application: Application) : AndroidViewModel(application) {
    private val syncManager = WearDataLayerSyncManager(application)

    private val _data  = MutableStateFlow(loadData())
    val data: StateFlow<NutritionData> = _data.asStateFlow()

    private val _goals = MutableStateFlow(loadGoals())
    val goals: StateFlow<NutritionGoals> = _goals.asStateFlow()

    private val _quickAddItems = MutableStateFlow(QuickAddStore.items(application))
    val quickAddItems: StateFlow<List<QuickAddFoodItem>> = _quickAddItems.asStateFlow()

    private val _quickAddMealSlots = MutableStateFlow(QuickAddStore.mealSlots(application))
    val quickAddMealSlots: StateFlow<List<QuickAddMealSlot>> = _quickAddMealSlots.asStateFlow()

    private val _pendingQuickAddItem = MutableStateFlow<QuickAddFoodItem?>(null)
    val pendingQuickAddItem: StateFlow<QuickAddFoodItem?> = _pendingQuickAddItem.asStateFlow()

    // ── Public actions ───────────────────────────────────────────────────────

    /// Stashes the tapped quick-add item so the meal-picker screen (pushed
    /// right after this call) can read it without a nav argument.
    fun selectQuickAddItem(item: QuickAddFoodItem) {
        _pendingQuickAddItem.value = item
    }

    /// Re-reads the synced quick-add snapshot. Unlike [refresh] this isn't
    /// called after local mutations — it picks up a background DataClient
    /// push from the phone, so callers should invoke it when the Log Food
    /// screen appears.
    fun refreshQuickAdd() {
        _quickAddItems.value = QuickAddStore.items(ctx())
        _quickAddMealSlots.value = QuickAddStore.mealSlots(ctx())
    }

    /// Logs a quick-add item against [mealKey]: applies the macro delta
    /// locally (so the watch's own totals update immediately) and forwards
    /// the command to the phone, which is the source of truth for the food
    /// diary and will resolve [item.foodId] against its catalogue.
    fun logQuickAdd(item: QuickAddFoodItem, mealKey: String) {
        MacroStore.addFood(ctx(), item.kcal, item.protein, item.carbs, item.fat)
        refresh()
        _pendingQuickAddItem.value = null
        val commandJson = QuickAddStore.createLogCommand(
            foodId = item.foodId,
            mealKey = mealKey,
            portionAmount = item.portionAmount,
            portionUnit = item.portionUnit,
        )
        viewModelScope.launch {
            syncManager.sendQuickAddCommand(commandJson)
        }
    }

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

    fun startFast(targetSeconds: Long = 16L * 60L * 60L) {
        val now = System.currentTimeMillis()
        val localSnapshot = FastingSnapshot(
            hasActiveFast = true,
            startedAtEpochMs = now,
            targetSeconds = targetSeconds,
        )
        val json = FastingStore.snapshotToJson(localSnapshot)
        FastingStore.saveSnapshot(ctx(), json)
        _data.value = _data.value.copy(fastingSnapshot = localSnapshot)
        sendFastingCommand(FastingStore.createCommand("start", targetSeconds))
    }

    fun stopFast() {
        val localSnapshot = FastingSnapshot(
            hasActiveFast = false,
            startedAtEpochMs = null,
            targetSeconds = 16L * 60L * 60L,
        )
        val json = FastingStore.snapshotToJson(localSnapshot)
        FastingStore.saveSnapshot(ctx(), json)
        _data.value = _data.value.copy(fastingSnapshot = localSnapshot)
        sendFastingCommand(FastingStore.createCommand("stop"))
    }

    // ── Helpers ──────────────────────────────────────────────────────────────

    private fun ctx() = getApplication<Application>()

    private fun loadData() = NutritionData(
        calories = MacroStore.calories(ctx()),
        protein  = MacroStore.protein(ctx()),
        carbs    = MacroStore.carbs(ctx()),
        fats     = MacroStore.fats(ctx()),
        water    = MacroStore.water(ctx()),
        fasting  = MacroStore.fasting(ctx()),
        fastingSnapshot = FastingStore.snapshot(ctx()),
        weeklyTonnage = MacroStore.weeklyTonnage(ctx()),
        weeklySets = MacroStore.weeklySets(ctx()),
        weeklyVolumeJson = MacroStore.weeklyVolumeJson(ctx()),
    )

    private fun loadGoals() = NutritionGoals(
        calorieGoal = MacroStore.calorieGoal(ctx()),
        proteinGoal = MacroStore.proteinGoal(ctx()),
        carbsGoal   = MacroStore.carbsGoal(ctx()),
        fatGoal     = MacroStore.fatGoal(ctx()),
        waterGoal   = MacroStore.waterGoal(ctx()),
    )

    private fun sendFastingCommand(commandJson: String) {
        viewModelScope.launch {
            syncManager.sendFastingCommand(commandJson)
        }
    }
}
