import Flutter
import UIKit
import BackgroundTasks

/** Entry point and event coordinator for the TrustedTime iOS plugin. */
public class TrustedTimePlugin: NSObject, FlutterPlugin {

    private var integrityEventSink: FlutterEventSink?
    private var clockObservers: [NSObjectProtocol] = []
    private let bgTaskId = "com.trustedtime.backgroundsync"

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = TrustedTimePlugin()
        
        // Channel for hardware process info uptime.
        FlutterMethodChannel(name: "trusted_time/monotonic", binaryMessenger: registrar.messenger())
            .setMethodCallHandler(instance.handle)
            
        // Channel for Apple BackgroundTasks registration.
        FlutterMethodChannel(name: "trusted_time/background", binaryMessenger: registrar.messenger())
            .setMethodCallHandler(instance.handle)
            
        // Stream for Darwin-level temporal notifications.
        FlutterEventChannel(name: "trusted_time/integrity", binaryMessenger: registrar.messenger())
            .setStreamHandler(instance)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getUptimeMs":
            // Returns kernel-level monotonic uptime in milliseconds.
            result(Int64(ProcessInfo.processInfo.systemUptime * 1000))
        case "enableBackgroundSync":
            let hours = (call.arguments as? [String: Any])?["intervalHours"] as? Int ?? 24
            registerBgSync(intervalHours: hours)
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    /** Submits the BGAppRefreshTask to the iOS scheduling system. */
    private func registerBgSync(intervalHours: Int) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: bgTaskId, using: nil) { [weak self] task in
            self?.scheduleNextBgSync(hours: intervalHours)
            task.setTaskCompleted(success: true)
        }
        scheduleNextBgSync(hours: intervalHours)
    }

    /** Calculates the earliest start date for the next background refresh. */
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
        
        // Listen for standard Darwin temporal change notifications.
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

    /** Forwards the native notification down into the Flutter isolate. */
    private func emit(_ data: [String: Any]) {
        DispatchQueue.main.async { [weak self] in self?.integrityEventSink?(data) }
    }
}
