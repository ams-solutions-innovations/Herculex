package com.ams.herculex.workout

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import androidx.core.content.ContextCompat
import androidx.health.services.client.HealthServices
import androidx.health.services.client.MeasureCallback
import androidx.health.services.client.data.Availability
import androidx.health.services.client.data.DataPointContainer
import androidx.health.services.client.data.DataType
import androidx.health.services.client.data.DataTypeAvailability
import androidx.health.services.client.data.DeltaDataType
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Live heart rate via Health Services `MeasureClient` — the Wear OS standard,
 * so it works on every watch (Galaxy Watch, Pixel Watch, ...) rather than
 * relying on a vendor SDK. Emits bpm, or -1 when there is no reading.
 */
class HeartRateMonitor(context: Context) {

    companion object {
        private const val TAG = "HeartRateMonitor"

        /** Wear OS 6 (API 36) replaced BODY_SENSORS with the health permission. */
        const val READ_HEART_RATE_PERMISSION = "android.permission.health.READ_HEART_RATE"

        fun requiredPermission(): String =
            if (Build.VERSION.SDK_INT >= 36) READ_HEART_RATE_PERMISSION
            else Manifest.permission.BODY_SENSORS

        fun hasPermission(context: Context): Boolean =
            ContextCompat.checkSelfPermission(context, requiredPermission()) ==
                PackageManager.PERMISSION_GRANTED
    }

    private val appContext = context.applicationContext
    private val measureClient = HealthServices.getClient(appContext).measureClient

    private val _bpm = MutableStateFlow(-1)
    val bpm: StateFlow<Int> = _bpm.asStateFlow()

    private var registered = false

    private val callback = object : MeasureCallback {
        override fun onAvailabilityChanged(
            dataType: DeltaDataType<*, *>,
            availability: Availability,
        ) {
            // Sensor lost contact / still warming up: show "-" rather than a stale bpm.
            if (availability != DataTypeAvailability.AVAILABLE) _bpm.value = -1
        }

        override fun onDataReceived(data: DataPointContainer) {
            val latest = data.getData(DataType.HEART_RATE_BPM).lastOrNull() ?: return
            _bpm.value = latest.value.toInt().takeIf { it > 0 } ?: -1
        }

        override fun onRegistrationFailed(throwable: Throwable) {
            Log.w(TAG, "Heart rate registration failed", throwable)
            registered = false
        }
    }

    /** Starts measuring. No-op without permission or when already running. */
    fun start() {
        if (registered || !hasPermission(appContext)) return
        try {
            measureClient.registerMeasureCallback(DataType.HEART_RATE_BPM, callback)
            registered = true
        } catch (e: Exception) {
            Log.w(TAG, "Could not start heart rate measurement", e)
        }
    }

    fun stop() {
        if (!registered) return
        registered = false
        _bpm.value = -1
        try {
            measureClient.unregisterMeasureCallbackAsync(DataType.HEART_RATE_BPM, callback)
        } catch (e: Exception) {
            Log.w(TAG, "Could not stop heart rate measurement", e)
        }
    }
}
