#if os(iOS)
import Flutter
import UIKit
import BackgroundTasks
#elseif os(macOS)
import FlutterMacOS
import Foundation
#endif

/// Unified entry point and event coordinator for the TrustedTime Darwin (iOS/macOS) plugin.
///
/// **Host app requirement (iOS)**: To enable background sync, add the task identifier
/// to the host app's `Info.plist`:
/// ```xml
/// <key>BGTaskSchedulerPermittedIdentifiers</key>
/// <array>
///   <string>com.trustedtime.backgroundsync</string>
/// </array>
/// ```
public class TrustedTimePlugin: NSObject, FlutterPlugin {

    private var integrityEventSink: FlutterEventSink?
    private var clockObservers: [NSObjectProtocol] = []
    
    #if os(iOS)
    private let bgTaskId = "com.trustedtime.backgroundsync"
    private var bgRegistered = false
    private var bgIntervalHours = 24
    private let probeUrl = "https://www.google.com"
    private var backgroundChannel: FlutterMethodChannel?
    #endif

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = TrustedTimePlugin()
        
        #if os(iOS)
        let messenger = registrar.messenger()
        #elseif os(macOS)
        let messenger = registrar.messenger
        #endif
        
        let monotonicChannel = FlutterMethodChannel(name: "trusted_time/monotonic", binaryMessenger: messenger)
        monotonicChannel.setMethodCallHandler(instance.handle)
            
        let backgroundChannel = FlutterMethodChannel(name: "trusted_time/background", binaryMessenger: messenger)
        backgroundChannel.setMethodCallHandler(instance.handle)
        #if os(iOS)
        instance.backgroundChannel = backgroundChannel
        #endif
            
        let integrityChannel = FlutterEventChannel(name: "trusted_time/integrity", binaryMessenger: messenger)
        integrityChannel.setStreamHandler(instance)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getUptimeMs":
            result(Int64(ProcessInfo.processInfo.systemUptime * 1000))
        case "enableBackgroundSync":
            #if os(iOS)
            let hours = (call.arguments as? [String: Any])?["intervalHours"] as? Int ?? 24
            bgIntervalHours = hours
            registerBgSync()
            result(nil)
            #else
            result(nil)
            #endif
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    #if os(iOS)
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

    private func performBackgroundCheck(task: BGTask) {
        guard let url = URL(string: probeUrl) else {
            task.setTaskCompleted(success: true)
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 10

        let dataTask = URLSession.shared.dataTask(with: request) { [weak self] _, _, _ in
            DispatchQueue.main.async {
                self?.backgroundChannel?.invokeMethod("onBackgroundSync", arguments: nil)
                self?.scheduleNextBgSync()
                task.setTaskCompleted(success: true)
            }
        }

        task.expirationHandler = { [weak self] in
            dataTask.cancel()
            self?.scheduleNextBgSync()
            task.setTaskCompleted(success: false)
        }

        dataTask.resume()
    }

    private func scheduleNextBgSync() {
        let req = BGAppRefreshTaskRequest(identifier: bgTaskId)
        req.earliestBeginDate = Date(timeIntervalSinceNow: Double(bgIntervalHours) * 3600)
        try? BGTaskScheduler.shared.submit(req)
    }
    #endif
}

extension TrustedTimePlugin: FlutterStreamHandler {

    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        integrityEventSink = events
        let nc = NotificationCenter.default
        
        #if os(iOS)
        let clockChange = Notification.Name.NSSystemClockDidChange
        let tzChange = Notification.Name.NSSystemTimeZoneDidChange
        #elseif os(macOS)
        let clockChange = Notification.Name.NSSystemClockDidChange
        let tzChange = Notification.Name.NSSystemTimeZoneDidChange
        #endif

        clockObservers = [
            nc.addObserver(forName: clockChange, object: nil, queue: .main) { [weak self] _ in
                self?.emit(["type": "clockJumped"])
            },
            nc.addObserver(forName: tzChange, object: nil, queue: .main) { [weak self] _ in
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
