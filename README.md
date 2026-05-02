# TrustedTime

[![pub package](https://img.shields.io/pub/v/trusted_time.svg)](https://pub.dev/packages/trusted_time)
[![Build Status](https://github.com/Sahad2701/trusted_time/actions/workflows/ci.yml/badge.svg)](https://github.com/Sahad2701/trusted_time/actions)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Platforms](https://img.shields.io/badge/platforms-Android%20%7C%20iOS%20%7C%20macOS%20%7C%20Windows%20%7C%20Linux%20%7C%20Web-blue.svg)](https://pub.dev/packages/trusted_time)

**TrustedTime** is an absolute top-tier, production-grade time integrity subsystem for Flutter. It provides a self-healing, tamper-proof UTC clock anchored to hardware monotonic oscillators, ensuring your app's temporal logic remains immune to manipulation, network spoofing, and long-running drift.

[Architecture](ARCHITECTURE.md) • [Security](SECURITY.md) • [Technical Audit](docs/V2_0_0_TECHNICAL_AUDIT.md) • [Changelog](CHANGELOG.md)

---

## 💎 Elite-Tier Features

*   **Self-Healing Consensus**: Adaptive thresholds (3x median filtering) and exponential source health scoring isolate unreliable authorities in real-time.
*   **Probabilistic Trust**: Qualitative trust grades (`ConfidenceLevel`) and decaying `confidenceScore` model temporal uncertainty over time.
*   **Adversarial Robustness**: Group-diverse quorum requirements prevent "Median Poisoning" attacks from correlated network sources.
*   **NTS (RFC 8915)**: Cryptographically authenticated time synchronization (hand-rolled Pure-Dart TLS 1.3 + AEAD) for protection against MITM time-spoofing.
*   **Integrity Feedback Loop**: Automatic state purge and high-priority resync upon detection of system clock jumps or reboots.
*   **Enterprise Observability**: Machine-readable `SyncMetrics` with structured confidence breakdowns for pro-grade monitoring.

---

## Quick Start

### 1️⃣ Initialize once at app startup

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await TrustedTime.initialize();
  runApp(MyApp());
}
```

### 2️⃣ Get trusted time anywhere

```dart
// Synchronous, <1µs, zero-IO
final now = TrustedTime.now();
```

### 3️⃣ Explicit Security Intent

```dart
// Require cryptographically secure (NTS) time for high-value transactions
try {
  final secureNow = TrustedTime.getTime(requireSecure: true);
} on TrustedTimeSecurityException catch (e) {
  // Handle fallback to consensus-only time
}
```

### 4️⃣ Monitor Confidence

```dart
// Check qualitative confidence grade
final grade = TrustedTime.confidence; // low, medium, high

// Check decaying freshness score (0.0 to 1.0)
if (TrustedTime.confidenceScore < 0.5) {
  await TrustedTime.forceResync();
}
```

---

## How It Works: The Integrity Subsystem

TrustedTime establishes an **Absolute Trust Anchor** by linking network-verified UTC to the device's **Monotonic Hardware Uptime**.

1.  **Racing Parallelism**: Queries multiple authorities (NTP, HTTPS, NTS) concurrently.
2.  **Incremental Consensus**: Recomputes Marzullo overlaps as each sample arrives, exiting early once a stable, group-diverse quorum is reached.
3.  **Monotonic Anchoring**: Links the result to the OS uptime. Since uptime cannot be manipulated by users, the resulting virtual clock remains correct even if the system time is changed or the device goes offline.
4.  **Adaptive Monitoring**: Continually compares monotonic delta vs. wall-clock delta, accelerating its check frequency if an anomaly is detected.

---

## Platform Support

| Android | iOS | Web | macOS | Windows | Linux |
| :---: | :---: | :---: | :---: | :---: | :---: |
| ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

*   **Android**: `WorkManager` background sync + `SystemClock.elapsedRealtime()`.
*   **iOS/macOS**: `BGAppRefreshTask` + `ProcessInfo.systemUptime`.
*   **Windows**: 64-bit `GetTickCount64()` + `WM_TIMECHANGE` subclassing.
*   **Linux**: `CLOCK_BOOTTIME` + `timerfd` monitoring.
*   **Web**: High-resolution `performance.now()` (immune to `Date` changes).

---

## Security Model

TrustedTime is the only Flutter library that provides an **honest and transparent security model**:

| Threat | Protection | Implementation |
| :--- | :--- | :--- |
| **System Clock Change** | ✅ Complete | Monotonic anchoring |
| **Replay Attacks** | ✅ Complete | Monotonic drift detection |
| **Median Poisoning** | ✅ Robust | Group-aware diversity |
| **Network MITM** | ✅ Secure | NTS (RFC 8915) AEAD |
| **Imprecise Sources** | ✅ Self-Healing | Adaptive 3x Median Filtering |

---

## Performance

| Metric | Value |
| :--- | :--- |
| **`TrustedTime.now()`** | **< 1μs** (Zero I/O, Zero Alloc) |
| **Memory Footprint** | ~50 KB |
| **Idle CPU Usage** | **0%** (Interrupt-driven platform hooks) |
| **Sync Latency** | ~100–300ms (Racing parallelism early exit) |

---

## Comparison

| Capability | `DateTime.now()` | `flutter_kronos` | **TrustedTime v2.0** |
| :--- | :---: | :---: | :---: |
| Tamper-Proof | ❌ | ⚠️ | ✅ |
| Offline Safe | ❌ | ✅ | ✅ |
| Consensus | ❌ | ❌ | ✅ |
| NTS (Security) | ❌ | ❌ | ✅ |
| Confidence Decay | ❌ | ❌ | ✅ |
| Adaptive Filtering | ❌ | ❌ | ✅ |
| Group Diversity | ❌ | ❌ | ✅ |
| Zero-IO `now()` | ✅ | ❌ | ✅ |
