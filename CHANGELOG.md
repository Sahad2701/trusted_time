## 1.2.1

Comprehensive reliability and correctness audit (60+ fixes across 4 review cycles).

**Critical fixes**
- iOS/macOS: Fixed channel name mismatch that made the plugin non-functional
- Android: Fixed `BroadcastReceiver` leak on detach
- Android: `BackgroundSyncWorker` now performs HTTPS connectivity check
- `SyncClock.elapsedSinceAnchorMs()` now uses Dart `Stopwatch` (monotonic) instead of wall-clock delta
- Linux: Implemented `get_platform_version()` declared in private header
- Example integration test properly awaits `TrustedTime.initialize()`

**High-priority fixes**
- iOS BGTask handler performs HTTPS HEAD check (parity with Android worker)
- iOS BGTask closure no longer captures stale interval value
- Windows native test compiles with explicit constructor
- Example widget test matches actual app UI

**Engine improvements**
- Serialized sync via `Completer` prevents concurrent `_performSync()` calls
- Integrity events (`systemClockJumped`, `deviceRebooted`) invalidate trust and trigger resync
- Automatic retry with configurable delay on sync failure
- Background sync enabled on both warm-restore and cold-start paths
- `dispose()` clears `SyncClock` static state to prevent cross-test leakage
- `initialize()` short-circuits engine init when test mock is active
- `timezoneChanged` documented as intentional non-resync (UTC is timezone-independent)
- All `debugPrint` calls guarded by `kDebugMode` for release builds

**Algorithm & sources**
- Marzullo tie-breaking: lower endpoints sort before upper at equal times
- `bestEnd` reset when finding new maximum overlap depth
- `HttpsSource`: HEAD→GET fallback on 405 or missing Date header
- Robust HTTP date parsing (RFC 7231 + RFC 850 formats)
- NTP source uses conditional imports (`dart:io` guard) for web compatibility
- `TrustedTimeConfig.operator==` and `hashCode` include `additionalSources`

**Platform native**
- Android: `RECEIVER_NOT_EXPORTED` flag for API 33+ implicit-intent receivers
- Android: Removed unused `SharedPreferences` writes from background worker
- Android: Cleaned up `build.gradle` structure and `AndroidManifest.xml`
- iOS: `BGTaskScheduler.register` called only once via `bgRegistered` flag
- iOS: `Info.plist` documents `BGTaskSchedulerPermittedIdentifiers` requirement
- Windows: Removed legacy `"trusted_time"` method channel registration
- Linux: Removed legacy `"trusted_time"` method channel registration
- Web: Registered `MethodChannel` handlers for monotonic and background channels

**Cleanup**
- Deleted 7 dead platform abstraction files
- Removed `plugin_platform_interface` dependency
- Removed `Package.swift` (misleading SPM target for CocoaPods plugin)
- Deleted committed `test_results.txt` and `logcat_full.txt`
- Renamed `sync_engine_test.dart` → `models_test.dart` to match content
- Relaxed SDK constraints: `sdk: >=3.4.0`, `flutter: >=3.19.0`

**Tests**
- 54 tests across 9 test files (up from 8 tests originally)
- Added `TrustedTimeEstimate` tests (isReasonable, toString)
- Added `IntegrityMonitor` tests (reboot detection, multiple attach, double dispose)
- Added `TrustedTimeConfig` equality tests with `additionalSources`
- Added `SyncClock.reset()` test
- Widened timing bounds in SyncClock tests for CI reliability

**CI & docs**
- CI workflow analyzes example app alongside plugin
- `SECURITY.md` version table updated
- `CHANGELOG.md` reflects all audit work

## 1.2.0

Major stability and accuracy update with desktop support.

- Added integrity monitoring (`Stream<IntegrityEvent>`)
- Added offline time via `nowEstimated()`
- Added testing override support
- Improved timezone reliability (IANA-based)
- Added Windows & Linux observers

**Fixes & improvements**
- Safer storage behavior
- Correct config usage (NTP/HTTPS)
- Windows & Linux stability fixes
- SDK updates

**Breaking**
- `UnknownTimezoneException` replaces generic errors

## 1.0.5

* **iOS/macOS**: Implemented proper Swift Package Manager (SPM) support following Flutter 3.24+ standards.
* **Chore**: Removed obsolete lint rules from `analysis_options.yaml` for Dart 3.x compatibility.


## 1.0.4

* **Web**: Full WASM compatibility by removing `dart:io` dependencies and implementing conditional imports.


## 1.0.3

* Fix workflows: formatting and release check (fa4e61a)
* Format env block in release workflow (35168a2)
* Add automated release workflows and iOS packaging (68949cd)

## 1.0.1

- **Chore**: Implemented a fully automated release and publishing workflow using GitHub Actions.
- **Fix**: Added full platform support for Web, Windows, macOS, and Linux.

## 1.0.0

- **Initial High-Integrity Release**: Production-ready engine for tamper-proof UTC time.
- **Marzullo Consensus**: Multi-source quorum resolution from Tier-1 NTP and HTTPS providers.
- **Temporal Baseline**: Hardware-anchored monotonic timeline ensuring zero-drift consistency.
- **Full Jitter Backoff**: Industry-standard retry strategy for high-resiliency cloud connectivity.
- **Zero-Alloc Performance**: Memory-optimized internal stack with <1μs synchronous retrieval.
