import Flutter
import UIKit

/**
 * TrustedTimePlugin - Native iOS implementation for TrustedTime.
 *
 * This plugin provides the hardware-backed monotonic clock reference needed 
 * to defy system wall-clock manipulation. On iOS, we leverage `ProcessInfo.systemUptime`
 * which is a highly accurate hardware counter that is unaffected by user changes
 * to the Date & Time settings.
 *
 * Design Note: Unlike Android, iOS restricts background broadcast reception for 
 * many time-related events. We mitigate this by observing `NSSystemClockDidChange`
 * while the app is active and relying on uptime-delta validation in the Dart layer.
 */
public class TrustedTimePlugin: NSObject, FlutterPlugin {
    
    /// The FlutterMethodChannel for communication with Dart
    private static var channel: FlutterMethodChannel?
    
    /**
     * Registers the plugin with the Flutter engine.
     * Called automatically by Flutter when the plugin is loaded.
     *
     * - Parameter registrar: The plugin registrar provided by Flutter
     */
    public static func register(with registrar: FlutterPluginRegistrar) {
        channel = FlutterMethodChannel(
            name: "trusted_time",
            binaryMessenger: registrar.messenger()
        )
        
        let instance = TrustedTimePlugin()
        registrar.addMethodCallDelegate(instance, channel: channel!)
        
        // Start observing system clock changes
        ClockObserver.start(channel: channel!)
    }
    
    /**
     * Handles method calls from Flutter.
     *
     * Supported methods:
     * - getPlatformVersion: Returns iOS version string
     * - getUptimeMs: Returns monotonic uptime in milliseconds
     *
     * - Parameters:
     *   - call: The method call from Flutter
     *   - result: The result callback to send data back to Flutter
     */
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getPlatformVersion":
            result("iOS " + UIDevice.current.systemVersion)
            
        case "getUptimeMs":
            // systemUptime is the most reliable monotonic clock on iOS.
            // It represents seconds since the last kernel boot.
            // Converting to Int64 milliseconds for cross-platform parity with Android.
            let uptimeSeconds = ProcessInfo.processInfo.systemUptime
            let uptimeMs = Int64(uptimeSeconds * 1000)
            result(uptimeMs)
            
        default:
            result(FlutterMethodNotImplemented)
        }
    }
}
