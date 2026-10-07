package com.ams.herculex.complication

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/// Redraws complications and tiles when the calendar day changes.
///
/// `MacroStore` already zeroes yesterday's totals on read once the day key
/// moves on, but nothing asked the complications to read again, so they kept
/// showing yesterday's macros until the phone's next push. Midnight, a clock
/// change, a timezone change and a reboot are the moments the day key can move
/// without a sync, so each one triggers a refresh.
class DayChangeReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        WearComplicationHelper.requestAllComplicationsUpdate(context)
    }
}
