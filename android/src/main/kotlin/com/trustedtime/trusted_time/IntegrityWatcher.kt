package com.trustedtime.trusted_time

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
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
        // Double-attach guard: clean up any previous subscription first.
        detach(context)

        sink = eventSink
        lastWallMs = System.currentTimeMillis()
        lastUptimeMs = SystemClock.elapsedRealtime()

        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_TIME_CHANGED)
            addAction(Intent.ACTION_TIMEZONE_CHANGED)
        }

        receiver = object : BroadcastReceiver() {
            override fun onReceive(ctx: Context, intent: Intent) {
                when (intent.action) {
                    Intent.ACTION_TIME_CHANGED -> {
                        val now = System.currentTimeMillis()
                        val uptime = SystemClock.elapsedRealtime()
                        val driftMs = kotlin.math.abs(now - (lastWallMs + (uptime - lastUptimeMs)))
                        lastWallMs = now
                        lastUptimeMs = uptime
                        emit(mapOf("type" to "clockJumped", "driftMs" to driftMs))
                    }
                    Intent.ACTION_TIMEZONE_CHANGED -> emit(mapOf("type" to "timezoneChanged"))
                }
            }
        }

        // API 33+ requires RECEIVER_NOT_EXPORTED for implicit-intent receivers
        // that should not be accessible to other apps.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            context.registerReceiver(receiver, filter)
        }
    }

    /** Cleans up the background receiver. */
    fun detach(context: Context) {
        receiver?.let {
            try { context.unregisterReceiver(it) } catch (_: Exception) {}
        }
        receiver = null
        sink = null
    }

    private fun emit(data: Map<String, Any>) = sink?.success(data)
}
