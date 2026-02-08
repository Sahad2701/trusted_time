package com.example.trusted_time

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * BootReceiver - Detects when the device is rebooted.
 *
 * This receiver listens for the BOOT_COMPLETED system broadcast, which is
 * sent after the device finishes booting.
 *
 * When a reboot is detected, it notifies the Flutter layer that the system
 * uptime has been reset. This is critical because TrustedTime relies on
 * monotonic uptime, which resets to zero on reboot. The plugin must detect
 * this and force a network resync to re-establish trusted time.
 *
 * Required Permission: RECEIVE_BOOT_COMPLETED (declared in AndroidManifest.xml)
 *
 * @author TrustedTime Contributors
 * @version 1.0.0
 */
class BootReceiver : BroadcastReceiver() {
    
    /**
     * Called when the device finishes booting.
     *
     * @param context The application context
     * @param intent The BOOT_COMPLETED broadcast intent
     */
    override fun onReceive(context: Context?, intent: Intent?) {
        if (intent?.action == Intent.ACTION_BOOT_COMPLETED) {
            // Notify Flutter that the device has rebooted
            // This will trigger a resync since uptime has been reset
            TrustedTimePlugin.notifyClockTampered()
        }
    }
}
