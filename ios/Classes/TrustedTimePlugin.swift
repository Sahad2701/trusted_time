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
    private var bgIntervalHours = 24

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
            bgIntervalHours = hours
            registerBgSync()
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    /// Registers the BGAppRefreshTask once, then schedules the next execution.
    /// The interval is read from [bgIntervalHours] so subsequent calls to
    /// `enableBackgroundSync` with different intervals take effect in the
    /// handler closure.
    private func registerBgSync() {
        if !bgRegistered {
            BGTaskScheduler.shared.register(forTaskWithIdentifier: bgTaskId, using: nil) { [weak self] task in
                guard let self = self else {
                    task.setTaskCompleted(success: true)
                    return
                }
                self.performBackgroundCheck(task: task)
            }
            bgRegistered = true
        }
        scheduleNextBgSync()
    }

    /// Performs a lightweight HTTPS HEAD check (parity with Android worker)
    /// to validate connectivity, then schedules the next background refresh.
    private func performBackgroundCheck(task: BGTask) {
        let url = URL(string: "https://www.google.com")!
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 10

        let dataTask = URLSession.shared.dataTask(with: request) { [weak self] _, _, _ in
            self?.scheduleNextBgSync()
            task.setTaskCompleted(success: true)
        }

        task.expirationHandler = {
            dataTask.cancel()
            self.scheduleNextBgSync()
            task.setTaskCompleted(success: false)
        }

        dataTask.resume()
    }

    private func scheduleNextBgSync() {
        let req = BGAppRefreshTaskRequest(identifier: bgTaskId)
        req.earliestBeginDate = Date(timeIntervalSinceNow: Double(bgIntervalHours) * 3600)
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
