package com.example.trusted_time

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * ClockChangeReceiver - Detects when the user manually changes the system clock.
 *
 * This receiver listens for two system broadcasts:
 * - ACTION_TIME_CHANGED: Triggered when the user manually sets the time
 * - ACTION_TIMEZONE_CHANGED: Triggered when the user changes the timezone
 *
 * When either event occurs, it notifies the Flutter layer that the system
 * clock has been tampered with, allowing TrustedTime to invalidate its
 * trust and force a resync.
 *
 * @author TrustedTime Contributors
 * @version 1.0.0
 */
class ClockChangeReceiver : BroadcastReceiver() {
    
    /**
     * Called when a clock change broadcast is received.
     *
     * @param context The application context
     * @param intent The broadcast intent (TIME_CHANGED or TIMEZONE_CHANGED)
     */
    override fun onReceive(context: Context?, intent: Intent?) {
        when (intent?.action) {
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED -> {
                // Notify Flutter that the clock has been tampered with
                TrustedTimePlugin.notifyClockTampered()
            }
        }
    }
}
