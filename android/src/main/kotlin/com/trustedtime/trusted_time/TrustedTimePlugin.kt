package com.trustedtime.trusted_time

import android.content.Context
import android.os.SystemClock
import androidx.work.*
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.TimeUnit

/** Main entry point for the TrustedTime Android plugin. */
class TrustedTimePlugin : FlutterPlugin, MethodChannel.MethodCallHandler {

    private lateinit var methodChannel: MethodChannel
    private lateinit var backgroundChannel: MethodChannel
    private lateinit var integrityChannel: EventChannel
    private lateinit var context: Context

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext

        // Channel for synchronous hardware-clock queries.
        methodChannel = MethodChannel(binding.binaryMessenger, "trusted_time/monotonic")
        methodChannel.setMethodCallHandler(this)

        // Channel for scheduling background work.
        backgroundChannel = MethodChannel(binding.binaryMessenger, "trusted_time/background")
        backgroundChannel.setMethodCallHandler(this)

        // Stream for broadcasting temporal integrity violations.
        integrityChannel = EventChannel(binding.binaryMessenger, "trusted_time/integrity")
        integrityChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(args: Any?, sink: EventChannel.EventSink) =
                IntegrityWatcher.attach(context, sink)
            override fun onCancel(args: Any?) = IntegrityWatcher.detach()
        })
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getUptimeMs" -> result.success(SystemClock.elapsedRealtime()) // Returns kernel uptime.
            "enableBackgroundSync" -> {
                val hours = call.argument<Int>("intervalHours") ?: 24
                scheduleBackgroundSync(hours.toLong())
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    /** Dispatches a recurring WorkManager job for anchor refreshing. */
    private fun scheduleBackgroundSync(intervalHours: Long) {
        val request = PeriodicWorkRequestBuilder<BackgroundSyncWorker>(intervalHours, TimeUnit.HOURS)
            .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
            .build()
        WorkManager.getInstance(context)
            .enqueueUniquePeriodicWork("trusted_time_sync", ExistingPeriodicWorkPolicy.UPDATE, request)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        backgroundChannel.setMethodCallHandler(null)
        IntegrityWatcher.detach()
    }
}

/** Silent background worker shell for OS-level sync tasks. */
class BackgroundSyncWorker(ctx: Context, params: WorkerParameters) : CoroutineWorker(ctx, params) {
    override suspend fun doWork(): Result = Result.success()
}
