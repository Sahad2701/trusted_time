package com.example.trusted_time

import android.os.SystemClock
import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import android.os.Handler
import android.os.Looper

/**
 * TrustedTimePlugin - Native Android implementation for TrustedTime Flutter plugin.
 *
 * This plugin serves as the low-level bridge to the Android hardware clocks. 
 * While the wall clock (System.currentTimeMillis()) can be easily manipulated by users,
 * this plugin leverages the monotonic 'Elapsed Realtime' clock which is hardware-backed 
 * and independent of user-controlled time settings.
 *
 * Key Features:
 * - Monotonic Uptime: Provides access to time since boot, including deep sleep.
 * - Broadcast Monitoring: Listens for system events that invalidate the time trust.
 * - Reboot Resilience: Helps the Dart layer detect when hardware counters have reset.
 */
class TrustedTimePlugin : FlutterPlugin, MethodCallHandler {
    
    /// The MethodChannel that will handle communication between Flutter and native Android
    private var channel: MethodChannel? = null

    companion object {
        /// Static reference to the channel for use by broadcast receivers
        @Volatile
        private var staticChannel: MethodChannel? = null

        /**
         * Notifies Flutter that the system clock has been tampered with.
         * Called by ClockChangeReceiver and BootReceiver.
         */
        fun notifyClockTampered() {
            Handler(Looper.getMainLooper()).post {
                try {
                    staticChannel?.invokeMethod("onClockTampered", null)
                } catch (e: Exception) {
                    // Channel might not be ready or engine is detaching
                    // Silently fail to avoid crashes
                }
            }
        }
    }

    /**
     * Called when the plugin is attached to the Flutter engine.
     * Sets up the MethodChannel for communication.
     */
    override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "trusted_time")
        channel?.setMethodCallHandler(this)
        staticChannel = channel
    }

    /**
     * Handles method calls from Flutter.
     *
     * Supported methods:
     * - getPlatformVersion: Returns Android version string
     * - getUptimeMs: Returns monotonic uptime in milliseconds (includes deep sleep)
     */
    override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
        when (call.method) {
            "getPlatformVersion" -> {
                result.success("Android ${android.os.Build.VERSION.RELEASE}")
            }
            "getUptimeMs" -> {
                // We use elapsedRealtime() instead of uptimeMillis().
                // uptimeMillis() stops when the CPU enters deep sleep, which would 
                // introduce drift. elapsedRealtime() continues counting in sleep modes,
                // providing the most reliable monotonic reference available on Android.
                val uptimeMs = SystemClock.elapsedRealtime()
                result.success(uptimeMs)
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    /**
     * Called when the plugin is detached from the Flutter engine.
     * Cleans up the MethodChannel.
     */
    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        staticChannel = null
    }
}
