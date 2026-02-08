# TrustedTime

[![pub package](https://img.shields.io/pub/v/trusted_time.svg)](https://pub.dev/packages/trusted_time)
[![Build Status](https://github.com/Sahad2701/trusted_time/actions/workflows/ci.yml/badge.svg)](https://github.com/Sahad2701/trusted_time/actions)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Platforms](https://img.shields.io/badge/platforms-Android%20%7C%20iOS%20%7C%20Web%20%7C%20Desktop-blue.svg)](https://pub.dev/packages/trusted_time)

**TrustedTime** is a high-integrity, production-grade time guardian for Flutter. It provides a tamper-proof UTC clock anchored to hardware monotonic oscillators, ensuring your app's temporal logic remains perfect even if the system clock is manipulated.

[Architecture](ARCHITECTURE.md) • [Contributing](CONTRIBUTING.md) • [Security](SECURITY.md) • [Changelog](CHANGELOG.md)

Unlike `DateTime.now()`, which depends on the user-modifiable system clock, TrustedTime synchronizes with trusted network time sources and anchors that time to the device’s **hardware monotonic clock** — ensuring timestamps remain correct even if users change their device time or go offline.

---

## Why TrustedTime?

Many apps rely on time for correctness and security:

* Trial expirations
* Subscription billing
* Ticket validity
* Rate limiting
* Audit logging
* Token expiration

Unfortunately, **system time is untrusted** — users can move it forward or backward at will.

TrustedTime solves this by providing a **secure virtual clock** that:

✅ Works offline after first sync
✅ Detects clock tampering automatically
✅ Persists across app restarts
✅ Has near-zero runtime overhead
✅ Works across Android, iOS, Web, and Desktop

---

## Platform Support

| Android | iOS | Web | macOS | Windows | Linux |
| :---: | :---: | :---: | :---: | :---: | :---: |
| ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

---

## Features

*   **Tamper-Proof Time**: Anchors network UTC to hardware monotonic uptime.
*   **Multi-Source Consensus**: Quorum-based resolution via NTP and HTTPS.
*   **Secure Persistence**: Encrypted state recovery across app restarts.
*   **High Performance**: Synchronous, zero-latency access with <1μs overhead.
*   **Offline Ready**: Continues providing trusted time without connectivity once anchored.
*   **Integrity Monitoring**: Real-time event streams for clock jumps and reboots.

---

## Installation

Add **TrustedTime** to your `pubspec.yaml` via CLI:

```bash
flutter pub add trusted_time
```

### Platform-Specific Setup

#### Android
Ensure your `AndroidManifest.xml` (usually found in `android/app/src/main/AndroidManifest.xml`) includes the Internet permission:

```xml
<uses-permission android:name="android.permission.INTERNET" />
```

#### iOS / macOS / Windows / Linux / Web
No additional setup or permissions are required. The library automatically leverages native APIs for monotonic timing and secure storage.

---

## Quick Start

### 1️⃣ Initialize once at app startup

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Await initialization to ensure hardware monotonic anchoring is established.
  await TrustedTime.initialize();
  runApp(MyApp());
}
```

---

### 2️⃣ Get trusted time anywhere

```dart
final now = TrustedTime.now();
final unixMs = TrustedTime.nowUnixMs();
final iso = TrustedTime.nowIso();
```

---

### 3️⃣ Check trust state

```dart
if (TrustedTime.isTrusted) {
  // Time is verified and safe to use
} else {
  // Still syncing or integrity lost
}
```

---

### 4️⃣ Listen for tampering

```dart
TrustedTime.onIntegrityLost.listen((_) {
  print('System clock changed or device rebooted');
});
```

---

### 5️⃣ Force resync if needed

```dart
await TrustedTime.forceResync();
```

---

## Common Use Cases

### Ticketing & Access Control

Prevent users from activating passes early or extending them by changing device time.

### Trials & Subscriptions

Ensure “7-day trials” are exactly 7 days — even if the user adjusts their clock or goes offline.

### Anti-Fraud & Compliance

Use trusted timestamps for audit logs, transaction signing, and security-critical workflows.

### Rate Limiting & Cooldowns

Prevent cooldown bypass attacks caused by local clock manipulation.

---

## How It Works (Simple Explanation)

TrustedTime establishes a **Trust Anchor**:

1. It queries multiple network time sources (NTP + HTTPS).
2. It filters bad or slow sources using a quorum algorithm.
3. It stores the verified network time alongside the device’s **monotonic uptime**.
4. From then on, it computes:

```
trustedNow = (currentUptime - uptimeAtSync) + networkTimeAtSync
```

Because **monotonic uptime cannot be changed by the user**, this clock remains accurate even if:

* The system time is modified
* The device goes offline
* The app is restarted

Only a device reboot resets uptime — which TrustedTime detects and automatically resynchronizes.

---

## Advanced Configuration

```dart
await TrustedTime.initialize(
  config: TrustedTimeConfig(
    refreshInterval: Duration(hours: 12),
    ntpServers: ['time.google.com', 'pool.ntp.org'],
    httpsSources: ['https://www.google.com', 'https://www.cloudflare.com'],
    maxLatency: Duration(seconds: 2),
    minimumQuorum: 2,
    persistState: true,
  ),
);
```

---

## Platform Behavior

### Android

* Uses `SystemClock.elapsedRealtime()` (hardware monotonic clock)
* Detects manual time and timezone changes automatically
* No setup required

### iOS

* Uses `ProcessInfo.systemUptime`
* Detects system clock changes automatically
* No setup required

### Web & Desktop

* Uses HTTPS time sources
* Uses browser/OS monotonic timers
* Works offline after sync

---

## Performance

| Operation           | Cost           |
| ------------------- | -------------- |
| `TrustedTime.now()` | **< 1μs**      |
| Initial sync        | ~100–500ms     |
| Memory overhead     | ~50 KB         |
| Background CPU      | Zero when idle |

TrustedTime performs **no background polling** and uses **zero timers** once synced.

---

## Security Model

TrustedTime protects against:

| Threat                       | Protected |
| ---------------------------- | --------- |
| Manual clock change          | ✅         |
| Offline replay               | ✅         |
| Trial extension              | ✅         |
| System time rollback         | ✅         |
| App restart abuse            | ✅         |
| Network MITM (single server) | ✅         |

Limitations:

* Requires internet on first launch
* Cannot protect against hardware-level clock manipulation

---

## Comparison

| Capability                 | `DateTime.now()` | `flutter_time_guard` | `flutter_kronos` | **TrustedTime** |
| -------------------------- | ---------------- | -------------------- | ---------------- | --------------- |
| Trusted timestamps         | ❌                | ❌                    | ⚠️ Basic         | ✅               |
| Offline after sync         | ❌                | ⚠️ Limited           | ✅                | ✅               |
| Detects clock tampering    | ❌                | ✅                    | ⚠️ Partial       | ✅               |
| Multi-source consensus     | ❌                | ❌                    | ❌                | ✅               |
| HTTPS fallback             | ❌                | ❌                    | ❌                | ✅               |
| Drift/uncertainty metadata | ❌                | ❌                    | ❌                | ✅               |
| Cross-platform             | ⚠️               | ⚠️                   | ❌                | ✅               |
| Zero-latency `now()`       | ❌                | ❌                    | ❌                | ✅               |

---

## License

MIT License.

---

## Credits

Inspired by:

* Google Spanner TrueTime model
* NTP RFC 5905

---