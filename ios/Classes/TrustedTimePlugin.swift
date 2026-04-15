import Flutter
import UIKit
import BackgroundTasks

/// Entry point and event coordinator for the TrustedTime iOS plugin.
///
/// **Host app requirement**: To enable background sync, add the task identifier
/// to the host app's `Info.plist`:
/// ```xml
/// <key>BGTaskSchedulerPermittedIdentifiers</key>
/// <array>
///   <string>com.trustedtime.backgroundsync</string>
/// </array>
/// ```
/// Without this entry, `BGTaskScheduler.shared.register(...)` will fail
/// silently and background syncs will not fire.
public class TrustedTimePlugin: NSObject, FlutterPlugin {

    private var integrityEventSink: FlutterEventSink?
    private var clockObservers: [NSObjectProtocol] = []
    private let bgTaskId = "com.trustedtime.backgroundsync"
    private var bgRegistered = false

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = TrustedTimePlugin()
        
        FlutterMethodChannel(name: "trusted_time/monotonic", binaryMessenger: registrar.messenger())
            .setMethodCallHandler(instance.handle)
            
        FlutterMethodChannel(name: "trusted_time/background", binaryMessenger: registrar.messenger())
            .setMethodCallHandler(instance.handle)
            
        FlutterEventChannel(name: "trusted_time/integrity", binaryMessenger: registrar.messenger())
            .setStreamHandler(instance)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getUptimeMs":
            result(Int64(ProcessInfo.processInfo.systemUptime * 1000))
        case "enableBackgroundSync":
            let hours = (call.arguments as? [String: Any])?["intervalHours"] as? Int ?? 24
            registerBgSync(intervalHours: hours)
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    /// Registers the BGAppRefreshTask once, then schedules the next execution.
    ///
    /// Apple requires `register(forTaskWithIdentifier:)` to be called only
    /// during app launch. Subsequent calls replace the handler, which is
    /// harmless but wasteful. The `bgRegistered` flag prevents redundant
    /// registrations.
    private func registerBgSync(intervalHours: Int) {
        if !bgRegistered {
            BGTaskScheduler.shared.register(forTaskWithIdentifier: bgTaskId, using: nil) { [weak self] task in
                self?.scheduleNextBgSync(hours: intervalHours)
                task.setTaskCompleted(success: true)
            }
            bgRegistered = true
        }
        scheduleNextBgSync(hours: intervalHours)
    }

    private func scheduleNextBgSync(hours: Int) {
        let req = BGAppRefreshTaskRequest(identifier: bgTaskId)
        req.earliestBeginDate = Date(timeIntervalSinceNow: Double(hours) * 3600)
        try? BGTaskScheduler.shared.submit(req)
    }
}

extension TrustedTimePlugin: FlutterStreamHandler {

    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        integrityEventSink = events
        let nc = NotificationCenter.default
        
        clockObservers = [
            nc.addObserver(forName: .NSSystemClockDidChange, object: nil, queue: .main) { [weak self] _ in
                self?.emit(["type": "clockJumped"])
            },
            nc.addObserver(forName: .NSSystemTimeZoneDidChange, object: nil, queue: .main) { [weak self] _ in
                self?.emit(["type": "timezoneChanged"])
            },
        ]
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        clockObservers.forEach { NotificationCenter.default.removeObserver($0) }
        clockObservers.removeAll()
        integrityEventSink = nil
        return nil
    }

    private func emit(_ data: [String: Any]) {
        DispatchQueue.main.async { [weak self] in self?.integrityEventSink?(data) }
    }
}
