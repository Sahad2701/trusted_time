# trusted_time

[![pub package](https://img.shields.io/pub/v/trusted_time.svg)](https://pub.dev/packages/trusted_time)
[![Build Status](https://github.com/Sahad2701/trusted_time/actions/workflows/ci.yml/badge.svg)](https://github.com/Sahad2701/trusted_time/actions)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A tamper-proof UTC clock for Flutter. `trusted_time` anchors network-verified time to the device's hardware monotonic uptime, so your app's timestamps remain accurate even when the system clock is changed by the user, the device goes offline, or the network is unreliable.

---

## Features

- **Tamper-proof** — anchored to the hardware monotonic oscillator, not the system wall clock
- **Multi-source consensus** — queries NTP servers and HTTPS endpoints in parallel; uses Marzullo's algorithm to find the most probable true time and discard outliers
- **NTS support** — optional Network Time Security (RFC 8915) for cryptographically authenticated time
- **Integrity monitoring** — automatically detects system clock jumps and device reboots and re-syncs
- **Background sync** — keeps the anchor fresh while the app is backgrounded (Android WorkManager, iOS BGAppRefreshTask, desktop Timer)
- **Offline safe** — projects time from the last known anchor using the monotonic clock when the network is unavailable
- **All platforms** — Android, iOS, macOS, Windows, Linux, Web

---

## Platform support

| Platform | Monotonic clock | Background sync | Time sources | Integrity events |
|----------|----------------|----------------|-------------|-----------------|
| Android  | `elapsedRealtime()` | WorkManager | NTP, HTTPS, NTS | BroadcastReceiver |
| iOS      | `systemUptime` | BGAppRefreshTask | NTP, HTTPS, NTS | NotificationCenter |
| macOS    | `systemUptime` | Timer.periodic | NTP, HTTPS, NTS | NotificationCenter |
| Windows  | `GetTickCount64()` | Timer.periodic | NTP, HTTPS, NTS | WM_TIMECHANGE |
| Linux    | `CLOCK_BOOTTIME` | Timer.periodic | NTP, HTTPS, NTS | timerfd |
| Web/WASM | `performance.now()` | — | HTTPS only | visibilitychange |

> **Android background sync note:** The WorkManager job validates network connectivity only. The trust anchor is refreshed on the next foreground app launch. This is intentional — full headless anchor refresh is planned for v2.1.0.

> **Web/WASM note:** Browsers don't support UDP/TCP sockets, so Web platforms use HTTPS `Date` headers from multiple endpoints. The library automatically configures Web-compatible sources when running in browsers or WASM.

---

## Installation

```yaml
dependencies:
  trusted_time: ^2.0.0
```

---

## Setup

### Android

Add the `INTERNET` permission to `android/app/src/main/AndroidManifest.xml`:

```xml
<manifest ...>
    <uses-permission android:name="android.permission.INTERNET" />
    ...
</manifest>
```

If you call `enableBackgroundSync()`, WorkManager is used automatically. No additional manifest entries are required — WorkManager registers its own components.

### iOS

If you call `enableBackgroundSync()`, add the background task identifier to your `ios/Runner/Info.plist`:

```xml
<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
    <string>com.trustedtime.backgroundsync</string>
</array>
```

Also add the Background Modes capability in Xcode (`Signing & Capabilities → + Capability → Background Modes`) and enable **Background fetch**.

### macOS

Add the network entitlement to `macos/Runner/DebugProfile.entitlements` and `macos/Runner/Release.entitlements`:

```xml
<key>com.apple.security.network.client</key>
<true/>
```

### Windows, Linux, Web

No additional setup required.

---

## Usage

### Initialize at app startup

Call `initialize()` once before `runApp`. It restores the last persisted anchor from secure storage and begins the first network sync in the background.

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await TrustedTime.initialize();
  runApp(const MyApp());
}
```

You can pass a `TrustedTimeConfig` to customise sources, sync intervals, and security requirements:

```dart
await TrustedTime.initialize(
  config: const TrustedTimeConfig(
    ntpServers: ['time.cloudflare.com', 'time.google.com', 'pool.ntp.org'],
    refreshInterval: Duration(hours: 6),
    backgroundSyncInterval: Duration(hours: 12),
    minGroupCount: 2,
  ),
);
```

### Get the current time

```dart
// Synchronous — no I/O, typically completes in under 50µs
final now = TrustedTime.now();

// Unix milliseconds — avoids DateTime allocation
final ms = TrustedTime.nowUnixMs();

// ISO-8601 string
final iso = TrustedTime.nowIso();

// Local time in a specific IANA timezone (immune to device timezone manipulation)
final tokyo = TrustedTime.trustedLocalTimeIn('Asia/Tokyo');
```

`now()` throws `TrustedTimeNotReadyException` if called before the engine has established its first anchor. Check `TrustedTime.isTrusted` before calling if you need to handle the unready state.

### Check trust status

```dart
if (TrustedTime.isTrusted) {
  final now = TrustedTime.now();
} else {
  // Still starting up, or sync failed
  final estimate = TrustedTime.nowEstimated();
}

// Qualitative confidence grade
final grade = TrustedTime.confidence; // ConfidenceLevel.low / medium / high

// Decaying freshness score (1.0 = just synced, approaches 0.0 over time)
final score = TrustedTime.confidenceScore;
if (score < 0.5) {
  await TrustedTime.forceResync();
}
```

### Enforce security requirements

```dart
// Require NTS-authenticated time for high-value operations
try {
  final secureNow = TrustedTime.getTime(requireSecure: true);
  // secureNow is backed by NTS-authenticated consensus
} on TrustedTimeSecurityException catch (e) {
  // NTS unavailable — fall back to consensus-only time or block the operation
}

// Require a minimum confidence level
try {
  final now = TrustedTime.getTime(minConfidence: ConfidenceLevel.high);
} on TrustedTimeSecurityException catch (e) {
  // Confidence too low
}
```

### Listen for integrity events

The engine monitors for system clock jumps and device reboots. When an anomaly is detected, it emits an event, invalidates the current anchor, and begins an immediate resync.

```dart
TrustedTime.onIntegrityLost.listen((event) {
  switch (event.reason) {
    case TamperReason.systemClockJumped:
      // System clock was changed while the app was running
    case TamperReason.deviceRebooted:
      // Device rebooted — monotonic counter reset
    case TamperReason.timezoneChanged:
      // Timezone changed — UTC time unaffected but local time may differ
  }
});
```

### Enable background sync

```dart
await TrustedTime.enableBackgroundSync(
  interval: const Duration(hours: 12),
);
```

On Android this schedules a WorkManager `PeriodicWorkRequest`. On iOS it registers a `BGAppRefreshTask`. On desktop it uses a `Timer.periodic` within the Dart isolate. Web is not supported.

### NTS (Network Time Security)

Pass `ntsServers` in the config to enable RFC 8915 authenticated time. NTS is opt-in and off by default — apps that do not configure it have zero overhead from the feature.

```dart
await TrustedTime.initialize(
  config: const TrustedTimeConfig(
    ntsServers: ['time.cloudflare.com', 'nts.netnod.se'],
  ),
);

// Check whether the current anchor is NTS-authenticated
print(TrustedTime.isSecure);     // true / false
print(TrustedTime.authLevel);    // NtsAuthLevel.verified / advisory / none
```

> **NTS implementation note:** This version uses a pure-Dart NTS-KE implementation. Full AEAD verification (AES-SIV-CMAC-256) requires native TLS exporter access that is not yet available in Dart's `SecureSocket` API. Samples negotiated via NTS are labelled `NtsAuthLevel.advisory` — they confirm the server is NTS-aware but do not provide full cryptographic authentication. Verified NTS is planned for v2.1.0 via an FFI path. See [ADR 0003](docs/adr/0003-nts-pure-dart-vs-rust.md) for the full rationale.

### Observability

Register a `SyncObserver` to receive structured metrics from every sync cycle:

```dart
class MySyncObserver implements SyncObserver {
  @override
  void onMetricsReported(SyncMetrics metrics) {
    print('Latency: ${metrics.latencyMs}ms');
    print('Uncertainty: ±${metrics.uncertaintyMs}ms');
    print('Participants: ${metrics.participantCount}');
    print('Confidence: ${metrics.confidence}');
  }

  @override
  void onSourceFailed(String sourceId, Object error) {
    print('Source $sourceId failed: $error');
  }

  // ... other callbacks
}

TrustedTime.registerObserver(MySyncObserver());
```

---

## Testing

Use `TrustedTime.overrideForTesting` to inject a deterministic mock in unit and widget tests. Tests do not need network access.

```dart
void main() {
  setUp(() {
    TrustedTime.overrideForTesting(TrustedTimeMock(
      now: DateTime.utc(2026, 1, 1, 12, 0, 0),
      isTrusted: true,
      confidence: ConfidenceLevel.high,
    ));
  });

  tearDown(() {
    TrustedTime.resetOverride();
  });

  test('uses trusted time for timestamp', () {
    final ts = TrustedTime.now();
    expect(ts.year, 2026);
  });
}
```

---

## Configuration reference

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `ntpServers` | `List<String>` | Cloudflare, Google, pool.ntp.org | NTP server hostnames |
| `httpsSources` | `List<String>` | Several HTTPS endpoints | HTTPS `Date` header sources |
| `ntsServers` | `List<String>` | `[]` | NTS server hostnames (opt-in) |
| `ntsPort` | `int` | `4460` | NTS-KE port |
| `refreshInterval` | `Duration` | `12h` | How often to re-sync in the foreground |
| `backgroundSyncInterval` | `Duration?` | `null` | If set, enables background sync at this interval |
| `maxLatency` | `Duration` | `3s` | Per-source query timeout |
| `minimumQuorum` | `int` | `2` | Minimum sources required for consensus |
| `minQuorumRatio` | `double` | `0.6` | Fraction of responding sources required |
| `minGroupCount` | `int` | `2` | Minimum distinct provider groups required |
| `maxAllowedUncertaintyMs` | `int` | `10000` | Sources above this uncertainty are excluded |
| `persistState` | `bool` | `true` | Persist anchor to secure storage across launches |
| `earlyExit` | `bool` | `true` | Return as soon as a stable quorum is reached |
| `oscillatorDriftFactor` | `double` | `0.001` | Used for offline time estimation error calculation |

---

## Security model

| Threat | Status | Mechanism |
|--------|--------|-----------|
| System clock manipulation by user | ✅ Protected | Monotonic anchoring |
| Device reboot (clock reset) | ✅ Detected | Uptime comparison on warm start |
| Single rogue NTP server | ✅ Mitigated | Marzullo consensus + quorum floor |
| Correlated provider failure | ✅ Mitigated | Group diversity requirement |
| On-path NTP spoofing (MITM) | ⚠️ Advisory | NTS advisory mode (full AEAD in v2.1.0) |
| Offline drift | ⚠️ Estimated | Monotonic projection with drift factor |

---

## How it works

When `initialize()` is called:

1. The last persisted `TrustAnchor` is loaded from encrypted platform storage (Android Keystore / iOS Keychain / Windows DPAPI / Linux libsecret).
2. If the anchor is valid (device has not rebooted since it was written), time is available immediately — no network round-trip needed.
3. A background sync begins: NTP, HTTPS, and NTS sources are queried in parallel. As samples arrive they are fed into Marzullo's algorithm. Once a stable, group-diverse quorum is reached, a new anchor is written.

After initialization, `TrustedTime.now()` is a pure arithmetic operation it adds the elapsed monotonic time since the anchor was captured to the anchor's UTC value. There is no I/O and no platform channel call per invocation.

The integrity monitor runs continuously. On Android and iOS it listens for system broadcast events (`TIME_SET`, `TIMEZONE_CHANGED`, `NSSystemClockDidChange`). On Windows it subclasses a message window for `WM_TIMECHANGE`. On Linux it uses a `timerfd` with `TFD_TIMER_CANCEL_ON_SET` to detect kernel clock changes with zero idle CPU cost. When a jump is detected the anchor is invalidated and an immediate resync begins.

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


## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). All PRs require one approval and must pass the full CI matrix (Android, iOS, macOS, Windows, Linux across two Flutter versions) before merging.

## License

MIT see [LICENSE](LICENSE).
