import Foundation
import FlutterMacOS

/**
 * ClockObserver - Detects when the user manually changes the system clock on iOS.
 *
 * This class observes the NSSystemClockDidChange notification, which is posted
 * by the system when the user manually adjusts the device time or timezone.
 *
 * When a clock change is detected, it notifies the Flutter layer that the system
 * clock has been tampered with, allowing TrustedTime to invalidate its trust
 * and force a resync.
 *
 */
class ClockObserver {
    
    /**
     * Starts observing system clock changes.
     *
     * This method registers an observer for NSSystemClockDidChange notifications.
     * When the notification fires, it invokes the 'onClockTampered' method on
     * the Flutter side via the MethodChannel.
     *
     * - Parameter channel: The FlutterMethodChannel to communicate with Dart
     */
    static func start(channel: FlutterMethodChannel) {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name.NSSystemClockDidChange,
            object: nil,
            queue: .main
        ) { _ in
            // Notify Flutter that the system clock has been changed
            channel.invokeMethod("onClockTampered", arguments: nil)
        }
    }
}
