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

        methodChannel = MethodChannel(binding.binaryMessenger, "trusted_time/monotonic")
        methodChannel.setMethodCallHandler(this)

        backgroundChannel = MethodChannel(binding.binaryMessenger, "trusted_time/background")
        backgroundChannel.setMethodCallHandler(this)

        integrityChannel = EventChannel(binding.binaryMessenger, "trusted_time/integrity")
        integrityChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(args: Any?, sink: EventChannel.EventSink) =
                IntegrityWatcher.attach(context, sink)
            override fun onCancel(args: Any?) = IntegrityWatcher.detach(context)
        })
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getUptimeMs" -> result.success(SystemClock.elapsedRealtime())
            "enableBackgroundSync" -> {
                val hours = call.argument<Int>("intervalHours") ?: 24
                scheduleBackgroundSync(hours.toLong())
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

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
        IntegrityWatcher.detach(context)
    }
}

/**
 * Background worker that performs a lightweight HTTPS HEAD check to validate
 * connectivity and confirm the device can reach time servers.
 * 
 * **ANDROID LIMITATION**: This worker only performs connectivity validation.
 * The actual clock drift correction and anchor refresh happens on the Dart side
 * during the next application foreground launch. This is a known limitation
 * that will be addressed in a future release using headless FlutterEngine.
 * 
 * The worker's primary purpose is to keep the WorkManager schedule alive and
 * ensure network availability for the Dart engine's next sync cycle.
 */
class BackgroundSyncWorker(ctx: Context, params: WorkerParameters) : CoroutineWorker(ctx, params) {
    override suspend fun doWork(): Result {
        val url = java.net.URL("https://www.google.com")
        var conn: java.net.HttpURLConnection? = null
        return try {
            conn = url.openConnection() as java.net.HttpURLConnection
            conn.requestMethod = "HEAD"
            conn.connectTimeout = 5000
            conn.readTimeout = 5000
            conn.connect()
            Result.success()
        } catch (_: Exception) {
            Result.retry()
        } finally {
            conn?.disconnect()
        }
    }
}
