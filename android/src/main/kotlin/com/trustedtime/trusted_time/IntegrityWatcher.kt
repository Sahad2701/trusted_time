package com.trustedtime.trusted_time

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.SystemClock
import io.flutter.plugin.common.EventChannel

/** Reactive monitor for system-level clock and timezone modifications. */
object IntegrityWatcher {

    private var receiver: BroadcastReceiver? = null
    private var sink: EventChannel.EventSink? = null
    private var lastWallMs: Long = 0
    private var lastUptimeMs: Long = 0

    /** Connects the Android BroadcastReceiver to the Flutter EventSink. */
    fun attach(context: Context, eventSink: EventChannel.EventSink) {
        sink = eventSink
        lastWallMs = System.currentTimeMillis()
        lastUptimeMs = SystemClock.elapsedRealtime()

        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_TIME_CHANGED) // Triggered on manual clock jump.
            addAction(Intent.ACTION_TIMEZONE_CHANGED) // Triggered on region change.
        }

        receiver = object : BroadcastReceiver() {
            override fun onReceive(ctx: Context, intent: Intent) {
                when (intent.action) {
                    Intent.ACTION_TIME_CHANGED -> {
                        val now = System.currentTimeMillis()
                        val uptime = SystemClock.elapsedRealtime()
                        // Calculate magnitude of jump vs monotonic baseline.
                        val driftMs = kotlin.math.abs(now - (lastWallMs + (uptime - lastUptimeMs)))
                        lastWallMs = now
                        lastUptimeMs = uptime
                        emit(mapOf("type" to "clockJumped", "driftMs" to driftMs))
                    }
                    Intent.ACTION_TIMEZONE_CHANGED -> emit(mapOf("type" to "timezoneChanged"))
                }
            }
        }

        context.registerReceiver(receiver, filter)
    }

    /** Cleans up the background receiver. */
    fun detach() {
        receiver = null
        sink = null
    }

    private fun emit(data: Map<String, Any>) = sink?.success(data)
}
