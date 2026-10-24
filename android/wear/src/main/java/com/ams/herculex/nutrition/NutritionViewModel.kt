package com.ams.herculex.nutrition

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.ams.herculex.complication.WearComplicationHelper
import com.ams.herculex.sync.FastingSnapshot
import com.ams.herculex.sync.FastingStore
import com.ams.herculex.sync.LoggedFoodEntry
import com.ams.herculex.sync.MacroStore
import com.ams.herculex.sync.QuickAddFoodItem
import com.ams.herculex.sync.QuickAddMealSlot
import com.ams.herculex.sync.QuickAddStore
import com.ams.herculex.sync.WearDataLayerSyncManager
import kotlinx.coroutines.launch
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlin.math.roundToInt

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
    val nutrientTrendsJson: String = "[]",
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

    private val _quickAddItems = MutableStateFlow(QuickAddStore.suggestedItems(application))
    val quickAddItems: StateFlow<List<QuickAddFoodItem>> = _quickAddItems.asStateFlow()

    private val _recentQuickAddItems = MutableStateFlow(QuickAddStore.recentItems(application))
    val recentQuickAddItems: StateFlow<List<QuickAddFoodItem>> = _recentQuickAddItems.asStateFlow()

    private val _recipeQuickAddItems = MutableStateFlow(QuickAddStore.recipeItems(application))
    val recipeQuickAddItems: StateFlow<List<QuickAddFoodItem>> = _recipeQuickAddItems.asStateFlow()

    private val _quickAddMealSlots = MutableStateFlow(QuickAddStore.mealSlots(application))
    val quickAddMealSlots: StateFlow<List<QuickAddMealSlot>> = _quickAddMealSlots.asStateFlow()

    private val _loggedEntries = MutableStateFlow(QuickAddStore.loggedEntries(application))
    val loggedEntries: StateFlow<List<LoggedFoodEntry>> = _loggedEntries.asStateFlow()

    private val _selectedLoggedEntry = MutableStateFlow<LoggedFoodEntry?>(null)
    val selectedLoggedEntry: StateFlow<LoggedFoodEntry?> = _selectedLoggedEntry.asStateFlow()

    private val _pendingQuickAddItem = MutableStateFlow<QuickAddFoodItem?>(null)
    val pendingQuickAddItem: StateFlow<QuickAddFoodItem?> = _pendingQuickAddItem.asStateFlow()

    /// Portion multiplier chosen on the "adjust amount" screen (1.0 = the
    /// item's default portion) — carried alongside [pendingQuickAddItem] so
    /// the meal-picker screen after it can apply the same scaling [logQuickAdd]
    /// does, without needing a nav argument.
    private val _pendingQuickAddMultiplier = MutableStateFlow(1.0)
    val pendingQuickAddMultiplier: StateFlow<Double> = _pendingQuickAddMultiplier.asStateFlow()

    init {
        com.ams.herculex.sync.SyncService.activeNutritionViewModel = this
    }

    override fun onCleared() {
        super.onCleared()
        if (com.ams.herculex.sync.SyncService.activeNutritionViewModel === this) {
            com.ams.herculex.sync.SyncService.activeNutritionViewModel = null
        }
    }

    // ── Public actions ───────────────────────────────────────────────────────

    /// Stashes the tapped quick-add item so the meal-picker screen (pushed
    /// right after this call) can read it without a nav argument.
    fun selectQuickAddItem(item: QuickAddFoodItem) {
        _pendingQuickAddItem.value = item
        _pendingQuickAddMultiplier.value = 1.0
    }

    /// Sets the portion multiplier chosen on the "adjust amount" screen.
    fun setPendingQuickAddMultiplier(multiplier: Double) {
        _pendingQuickAddMultiplier.value = multiplier
    }

    fun selectLoggedEntry(entry: LoggedFoodEntry) {
        _selectedLoggedEntry.value = entry
    }

    /// The meal a one-tap "+" quick-add should log to, skipping the meal
    /// picker entirely: the food's own last-used meal if the phone reported
    /// one, otherwise the first synced meal slot, otherwise "snack".
    fun defaultMealKeyFor(item: QuickAddFoodItem): String {
        return item.lastMealKey
            ?: _quickAddMealSlots.value.firstOrNull()?.key
            ?: "snack"
    }

    /// Re-reads the synced quick-add snapshot. Unlike [refresh] this isn't
    /// called after local mutations — it picks up a background DataClient
    /// push from the phone, so callers should invoke it when the Log Food
    /// screen appears.
    fun refreshQuickAdd() {
        _quickAddItems.value = QuickAddStore.suggestedItems(ctx())
        _recentQuickAddItems.value = QuickAddStore.recentItems(ctx())
        _recipeQuickAddItems.value = QuickAddStore.recipeItems(ctx())
        _quickAddMealSlots.value = QuickAddStore.mealSlots(ctx())
        _loggedEntries.value = QuickAddStore.loggedEntries(ctx())
        viewModelScope.launch {
            runCatching { syncManager.flushPendingRealtimeMessages() }
        }
    }

    /// Logs a quick-add item against [mealKey]: applies the macro delta
    /// locally (so the watch's own totals update immediately) and forwards
    /// the command to the phone, which is the source of truth for the food
    /// diary and will resolve [item.foodId] or [item.recipeId] against its
    /// catalogue.
    ///
    /// [multiplier] scales the item's default-portion macros/amount linearly
    /// (e.g. 1.5 = one and a half of the usual serving) — set via the
    /// "adjust amount" screen, or left at 1.0 for the one-tap "+" quick-add
    /// that just repeats the last-logged amount.
    fun logQuickAdd(item: QuickAddFoodItem, mealKey: String, multiplier: Double = 1.0) {
        val calories = (item.kcal * multiplier).roundToInt()
        val protein  = (item.protein * multiplier).roundToInt()
        val carbs    = (item.carbs * multiplier).roundToInt()
        val fats     = (item.fat * multiplier).roundToInt()
        val portionAmount = item.portionAmount * multiplier

        MacroStore.addFood(ctx(), calories, protein, carbs, fats)
        refresh()
        _pendingQuickAddItem.value = null
        _pendingQuickAddMultiplier.value = 1.0

        val formattedAmount = if (portionAmount % 1.0 == 0.0) {
            "%.0f".format(portionAmount)
        } else {
            "%.1f".format(portionAmount)
        }
        val tempId = -(System.currentTimeMillis() % 100000).toInt()
        val tempEntry = LoggedFoodEntry(
            id = tempId,
            name = item.name,
            mealKey = mealKey,
            portionAmount = portionAmount,
            portionUnit = item.portionUnit,
            portionText = "$formattedAmount ${item.portionUnit}",
            servings = multiplier,
            kcal = calories,
            protein = protein,
            carbs = carbs,
            fat = fats,
            foodId = item.foodId,
            recipeId = item.recipeId,
            loggedAtEpochMs = System.currentTimeMillis(),
        )
        val currentEntries = _loggedEntries.value.toMutableList()
        currentEntries.add(tempEntry)
        _loggedEntries.value = currentEntries

        val commandJson = QuickAddStore.createLogCommand(
            foodId = item.foodId,
            mealKey = mealKey,
            portionAmount = portionAmount,
            portionUnit = item.portionUnit,
            recipeId = item.recipeId,
        )
        viewModelScope.launch {
            syncManager.sendQuickAddCommand(commandJson)
        }
    }

    fun deleteLoggedEntry(entry: LoggedFoodEntry) {
        QuickAddStore.deleteLoggedEntryLocally(ctx(), entry.id)
        _loggedEntries.value = _loggedEntries.value.filter { it.id != entry.id }
        if (_selectedLoggedEntry.value?.id == entry.id) {
            _selectedLoggedEntry.value = null
        }
        MacroStore.adjustFood(
            ctx(),
            deltaCalories = -entry.kcal,
            deltaProtein = -entry.protein,
            deltaCarbs = -entry.carbs,
            deltaFats = -entry.fat,
        )
        refresh()
        val commandJson = QuickAddStore.createDeleteCommand(entry.id)
        viewModelScope.launch {
            syncManager.sendQuickAddCommand(commandJson)
        }
    }

    fun updateLoggedEntry(
        entry: LoggedFoodEntry,
        newMealKey: String,
        newAmount: Double,
        newUnit: String,
        newPortionText: String,
        newKcal: Int,
        newProtein: Int,
        newCarbs: Int,
        newFat: Int,
        newServings: Double,
    ) {
        val deltaCalories = newKcal - entry.kcal
        val deltaProtein  = newProtein - entry.protein
        val deltaCarbs    = newCarbs - entry.carbs
        val deltaFats     = newFat - entry.fat

        QuickAddStore.updateLoggedEntryLocally(
            context = ctx(),
            entryId = entry.id,
            newMealKey = newMealKey,
            newAmount = newAmount,
            newUnit = newUnit,
            newPortionText = newPortionText,
            newKcal = newKcal,
            newProtein = newProtein,
            newCarbs = newCarbs,
            newFat = newFat,
            newServings = newServings,
        )
        val updated = entry.copy(
            mealKey = newMealKey,
            portionAmount = newAmount,
            portionUnit = newUnit,
            portionText = newPortionText,
            kcal = newKcal,
            protein = newProtein,
            carbs = newCarbs,
            fat = newFat,
            servings = newServings,
        )
        _loggedEntries.value = _loggedEntries.value.map { if (it.id == entry.id) updated else it }
        if (_selectedLoggedEntry.value?.id == entry.id) {
            _selectedLoggedEntry.value = updated
        }
        MacroStore.adjustFood(
            ctx(),
            deltaCalories = deltaCalories,
            deltaProtein = deltaProtein,
            deltaCarbs = deltaCarbs,
            deltaFats = deltaFats,
        )
        refresh()
        val commandJson = QuickAddStore.createUpdateCommand(
            entryId = entry.id,
            mealKey = newMealKey,
            portionAmount = newAmount,
            portionUnit = newUnit,
            servings = newServings,
        )
        viewModelScope.launch {
            syncManager.sendQuickAddCommand(commandJson)
        }
    }

    fun addCalories(amount: Int) {
        MacroStore.addCalories(ctx(), amount)
        refresh()
        sendMacroCommand(MacroStore.createCommand(kind = "calories", calories = amount))
    }

    fun addWater(amountMl: Int) {
        MacroStore.addWater(ctx(), amountMl)
        refresh()
        sendMacroCommand(MacroStore.createCommand(kind = "water", waterMl = amountMl))
    }

    fun logFood(calories: Int, protein: Int, carbs: Int, fats: Int) {
        MacroStore.addFood(ctx(), calories, protein, carbs, fats)
        refresh()
        sendMacroCommand(
            MacroStore.createCommand(
                kind = "food",
                calories = calories,
                protein = protein,
                carbs = carbs,
                fats = fats,
            ),
        )
    }

    fun logRamblerVoice(text: String, mealKey: String) {
        val commandJson = org.json.JSONObject().apply {
            put("commandId", java.util.UUID.randomUUID().toString())
            put("text", text)
            put("mealKey", mealKey)
            put("createdAtEpochMs", System.currentTimeMillis())
        }.toString()
        viewModelScope.launch {
            syncManager.sendRamblerCommand(commandJson)
        }
    }

    fun refresh() {
        _data.value  = loadData()
        _goals.value = loadGoals()
        WearComplicationHelper.requestNutritionComplicationsUpdate(ctx())
    }

    fun startFast(targetSeconds: Long = 16L * 60L * 60L) {
        val now = System.currentTimeMillis()
        val localSnapshot = FastingSnapshot(
            hasActiveFast = true,
            startedAtEpochMs = now,
            targetSeconds = targetSeconds,
        )
        val json = FastingStore.snapshotToJson(ctx(), localSnapshot)
        FastingStore.saveSnapshot(ctx(), json)
        _data.value = _data.value.copy(fastingSnapshot = localSnapshot)
        WearComplicationHelper.requestFastingComplicationsUpdate(ctx())
        sendFastingCommand(
            FastingStore.createCommand(
                action = "start",
                targetSeconds = targetSeconds,
                startedAtEpochMs = now,
            )
        )
    }

    fun stopFast() {
        val current = _data.value.fastingSnapshot
        val startedAt = current.startedAtEpochMs
        val targetSeconds = current.targetSeconds
        val now = System.currentTimeMillis()
        val durationSeconds = current.elapsedSeconds(now)

        val localSnapshot = FastingSnapshot(
            hasActiveFast = false,
            startedAtEpochMs = null,
            targetSeconds = targetSeconds,
            lastFastDurationSeconds = if (startedAt != null) durationSeconds else null,
        )
        val json = FastingStore.snapshotToJson(ctx(), localSnapshot)
        FastingStore.saveSnapshot(ctx(), json)
        _data.value = _data.value.copy(fastingSnapshot = localSnapshot)
        WearComplicationHelper.requestFastingComplicationsUpdate(ctx())
        sendFastingCommand(
            FastingStore.createCommand(
                action = "stop",
                targetSeconds = targetSeconds,
                startedAtEpochMs = startedAt,
                endedAtEpochMs = now,
            )
        )
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
        nutrientTrendsJson = MacroStore.nutrientTrendsJson(ctx()),
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

    private fun sendMacroCommand(commandJson: String) {
        viewModelScope.launch {
            syncManager.sendMacroCommand(commandJson)
        }
    }
}
