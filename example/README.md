# TrustedTime Example

This project demonstrates how to implement **high-integrity timekeeping** in a real-world Flutter application using the `trusted_time` plugin.

## Key Features of this Example

- **Real-time secure clock**: Sub-millisecond synchronous time updates.
- **Trial & License Verification**: Logic for verifying if a subscription has expired using trusted UTC.
- **Clock Tamper Detection**: Visual feedback when the system clock is manually adjusted or the device reboots.
- **Manual Resync**: Demonstrates triggering a new network quorum on demand.
- **Modern UI**: Full Material 3 implementation with responsive status indicators.

## Getting Started

1.  **Clone the repository**:
    ```bash
    git clone https://github.com/Sahad2701/trusted_time.git
    cd trusted_time/example
    ```

2.  **Install dependencies**:
    ```bash
    flutter pub get
    ```

3.  **Run on your device**:
    ```bash
    flutter run
    ```

## Best Practices Demonstrated

- **Early Initialization**: Calling `TrustedTime.initialize()` in `main()` to establish the trust anchor during app-boot.
- **Synchronous Safety**: Accessing `TrustedTime.now()` anywhere in the widget tree without needing a `FutureBuilder`.
- **Integrity Management**: Handling `onIntegrityLost` events to protect sensitive UI states during a re-sync.