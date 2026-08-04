package com.ams.herculex.nowbar

data class OngoingWorkoutSurfaceSnapshot(
    val surfaceId: String,
    val category: String,
    val sessionId: Long,
    val targetSetId: Long?,
    val startedAtEpochMillis: Long,
    val collapsed: CollapsedSurface,
    val expanded: ExpandedSurface,
    val privacy: SurfacePrivacy,
) {
    /**
     * A copy with [CollapsedSurface.elapsedLabel] blanked, for equality checks that
     * should ignore the continuously-ticking elapsed time.
     */
    fun withoutElapsedLabel(): OngoingWorkoutSurfaceSnapshot {
        return copy(collapsed = collapsed.copy(elapsedLabel = ""))
    }

    /** Whether [actionId] may only be executed once the device is unlocked. */
    fun requiresUnlock(actionId: String): Boolean {
        if (actionId in privacy.requiresUnlock) return true
        return expanded.actions.any { action -> action.id == actionId && action.requiresUnlock }
    }

    companion object {
        fun fromMap(raw: Map<*, *>): Result<OngoingWorkoutSurfaceSnapshot> {
            return runCatching {
                OngoingWorkoutSurfaceSnapshot(
                    surfaceId = raw.requiredString("surfaceId"),
                    category = raw.requiredString("category"),
                    sessionId = raw.requiredLong("sessionId"),
                    targetSetId = raw.optionalLong("targetSetId"),
                    startedAtEpochMillis = raw.requiredLong("startedAtEpochMillis"),
                    collapsed = CollapsedSurface.fromMap(raw.requiredMap("collapsed")),
                    expanded = ExpandedSurface.fromMap(raw.requiredMap("expanded")),
                    privacy = SurfacePrivacy.fromMap(raw.requiredMap("privacy")),
                )
            }
        }
    }
}

data class CollapsedSurface(
    val title: String,
    val subtitle: String,
    val value: String,
    val elapsedLabel: String,
) {
    companion object {
        fun fromMap(raw: Map<*, *>): CollapsedSurface {
            return CollapsedSurface(
                title = raw.requiredString("title"),
                subtitle = raw.optionalString("subtitle"),
                value = raw.optionalString("value"),
                elapsedLabel = raw.optionalString("elapsedLabel"),
            )
        }
    }
}

data class ExpandedSurface(
    val title: String,
    val rows: List<SurfaceRow>,
    val controls: List<SurfaceControl>,
    val actions: List<SurfaceAction>,
) {
    companion object {
        fun fromMap(raw: Map<*, *>): ExpandedSurface {
            return ExpandedSurface(
                title = raw.requiredString("title"),
                rows = raw.requiredMapList("rows").map(SurfaceRow::fromMap),
                controls = raw.optionalMapList("controls").map(SurfaceControl::fromMap),
                actions = raw.requiredMapList("actions").map(SurfaceAction::fromMap),
            )
        }
    }
}

data class SurfaceRow(
    val id: String,
    val label: String,
    val value: String,
) {
    companion object {
        fun fromMap(raw: Map<*, *>): SurfaceRow {
            return SurfaceRow(
                id = raw.requiredString("id"),
                label = raw.requiredString("label"),
                value = raw.requiredString("value"),
            )
        }
    }
}

data class SurfaceControl(
    val id: String,
    val type: String,
    val label: String,
    val value: Double,
    val valueUnit: String,
    val displayValue: String,
    val minValue: Double,
    val maxValue: Double,
    val step: Double,
    val stepLabel: String,
    val incrementActionId: String,
    val decrementActionId: String,
    val requiresUnlock: Boolean,
    val risk: String,
) {
    companion object {
        fun fromMap(raw: Map<*, *>): SurfaceControl {
            return SurfaceControl(
                id = raw.requiredString("id"),
                type = raw.requiredString("type"),
                label = raw.requiredString("label"),
                value = raw.requiredDouble("value"),
                valueUnit = raw.requiredString("valueUnit"),
                displayValue = raw.requiredString("displayValue"),
                minValue = raw.requiredDouble("minValue"),
                maxValue = raw.requiredDouble("maxValue"),
                step = raw.requiredDouble("step"),
                stepLabel = raw.requiredString("stepLabel"),
                incrementActionId = raw.requiredString("incrementActionId"),
                decrementActionId = raw.requiredString("decrementActionId"),
                requiresUnlock = raw.optionalBoolean("requiresUnlock"),
                risk = raw.optionalString("risk"),
            )
        }
    }
}

data class SurfaceAction(
    val id: String,
    val label: String,
    val requiresUnlock: Boolean,
    val risk: String,
) {
    companion object {
        fun fromMap(raw: Map<*, *>): SurfaceAction {
            return SurfaceAction(
                id = raw.requiredString("id"),
                label = raw.requiredString("label"),
                requiresUnlock = raw.optionalBoolean("requiresUnlock"),
                risk = raw.optionalString("risk"),
            )
        }
    }
}

data class SurfacePrivacy(
    val lockScreenVisibility: String,
    val requiresUnlock: List<String>,
    val allowedWhileLocked: List<String>,
) {
    companion object {
        fun fromMap(raw: Map<*, *>): SurfacePrivacy {
            return SurfacePrivacy(
                lockScreenVisibility = raw.requiredString("lockScreenVisibility"),
                requiresUnlock = raw.optionalStringList("requiresUnlock"),
                allowedWhileLocked = raw.optionalStringList("allowedWhileLocked"),
            )
        }
    }
}

private fun Map<*, *>.requiredString(key: String): String {
    return this[key] as? String
        ?: throw IllegalArgumentException("Missing or invalid string field '$key'.")
}

private fun Map<*, *>.optionalString(key: String): String {
    return this[key] as? String ?: ""
}

private fun Map<*, *>.optionalBoolean(key: String): Boolean {
    return this[key] as? Boolean ?: false
}

private fun Map<*, *>.requiredLong(key: String): Long {
    return when (val value = this[key]) {
        is Int -> value.toLong()
        is Long -> value
        is Number -> value.toLong()
        else -> throw IllegalArgumentException("Missing or invalid numeric field '$key'.")
    }
}

private fun Map<*, *>.requiredDouble(key: String): Double {
    return when (val value = this[key]) {
        is Int -> value.toDouble()
        is Long -> value.toDouble()
        is Float -> value.toDouble()
        is Double -> value
        is Number -> value.toDouble()
        else -> throw IllegalArgumentException("Missing or invalid numeric field '$key'.")
    }
}

private fun Map<*, *>.optionalLong(key: String): Long? {
    return when (val value = this[key]) {
        null -> null
        is Int -> value.toLong()
        is Long -> value
        is Number -> value.toLong()
        else -> throw IllegalArgumentException("Invalid numeric field '$key'.")
    }
}

private fun Map<*, *>.requiredMap(key: String): Map<*, *> {
    return this[key] as? Map<*, *>
        ?: throw IllegalArgumentException("Missing or invalid object field '$key'.")
}

private fun Map<*, *>.requiredMapList(key: String): List<Map<*, *>> {
    val rawList = this[key] as? List<*>
        ?: throw IllegalArgumentException("Missing or invalid list field '$key'.")
    return rawList.mapIndexed { index, value ->
        value as? Map<*, *>
            ?: throw IllegalArgumentException("Invalid object at '$key[$index]'.")
    }
}

private fun Map<*, *>.optionalMapList(key: String): List<Map<*, *>> {
    val rawList = this[key] as? List<*> ?: return emptyList()
    return rawList.mapIndexed { index, value ->
        value as? Map<*, *>
            ?: throw IllegalArgumentException("Invalid object at '$key[$index]'.")
    }
}

private fun Map<*, *>.optionalStringList(key: String): List<String> {
    val rawList = this[key] as? List<*> ?: return emptyList()
    return rawList.mapIndexed { index, value ->
        value as? String
            ?: throw IllegalArgumentException("Invalid string at '$key[$index]'.")
    }
}
