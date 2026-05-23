# Changelog

## [2.1.0]

### Breaking Changes

- **`NtsAuthLevel.advisory` removed** (deprecated since v2.0.3).
  Any exhaustive `switch` or `if` branch handling `.advisory` will fail at compile
  time — simply delete the case. Code that previously treated `.advisory` as a
  weak-auth signal should use `NtsAuthLevel.none` for unauthenticated sources and
  `NtsAuthLevel.verified` for RFC 8915-authenticated ones.

  **Persisted anchor migration**: `TrustAnchor.fromJson` safely remaps the old
  three-variant ordinals to the new two-variant layout. Old `advisory` (index 1)
  decodes as `none`; old `verified` (index 2) decodes as `verified`. No data loss,
  no misidentification as verified.

### Dependencies

- **`nts` `^1.3.1` → `^5.0.0`**: Picks up the hand-written stable DTO layer,
  the `NtsClient` session API, and per-query `serverStratum` on `NtsTimeSample`.
  `RustLib` was renamed to `NtsRustLib` — handled internally; no consumer changes needed.
  NTS server stratum is now automatically fed into source quality scoring.
- **`flutter_secure_storage` `^10.0.0`** (lower bound unchanged — all 10.x are
  API-compatible; consumers on any 10.x version are unaffected).
- **`http` `">=1.0.0 <2.0.0"` → `^1.3.0`**: Tightens the lower bound to a known-good
  version. Consumers already on 1.3.x+ are unaffected.
- **`timezone` `">=0.9.0 <1.0.0"` → `">=0.9.0 <0.12.0"`**: Widens to cover the
  current latest (0.11.0). Consumers on 0.9.x–0.11.x are all satisfied.

### Added

- **Adaptive Clock Drift Compensation** (`DriftCalibrator`): The engine now tracks
  per-device oscillator drift across successive trust anchors and computes a
  device-specific drift rate using median filtering. This rate replaces the static
  `oscillatorDriftFactor` in `nowEstimated()` once a 30-minute observation window
  has been accumulated. The calibrator enforces a 100 ppm sanity cap — measurements
  above this threshold are discarded and the static fallback is retained. Drift state
  is cleared on integrity violations (clock jump, reboot).

- **Dynamic Time Source Quality Scoring** (`SourceQualityTracker`): The sync engine
  now ranks sources each cycle based on a weighted score combining RTT/uncertainty
  (40%), consensus participation rate (40%), and NTP stratum (20%). Higher-quality
  sources are queried first to improve early-exit latency.

  **Starvation guard**: Sources that haven't been queried within 5 consecutive cycles
  are force-included regardless of their rank, keeping their quality estimates fresh
  and preventing permanent exclusion of lower-ranked sources.

  NTP stratum hints can be registered via `SourceQualityTracker.setStratum()` when
  a source's stratum is known externally (e.g. via SNMP or NTP extension fields).

### Tests

- `test/drift_calibrator_test.dart`: 6 tests covering the observation window gate,
  synthetic drift measurement, 100 ppm rejection, outlier filtering via median, and
  reset behaviour.
- `test/source_quality_tracker_test.dart`: 10 tests covering ranking by participation,
  uncertainty, and stratum; the full starvation lifecycle; deduplication; and
  out-of-range stratum handling.
- `test/nts_auth_level_migration_test.dart`: 6 tests verifying the two-variant enum
  shape and the v2.0.x → v2.1.0 `fromJson` ordinal migration (none, advisory→none,
  verified, out-of-range).

---

## [2.0.3]

### Changed
- **Breaking**: Bumped minimum SDK requirements to Dart 3.10.0 / Flutter 3.38.0 for Native Assets support.
- **NTS RFC 8915 Compliance**: Migrated from pure-Dart NTS implementation to [`package:nts`](https://pub.dev/packages/nts).
  - Now uses Rust-based TLS 1.3 with proper RFC 5705 keying material exporters.
  - Full AES-SIV-CMAC-256 AEAD authentication (previously advisory-only).
  - `NtsAuthLevel.advisory` is now deprecated; use `NtsAuthLevel.verified` for cryptographic guarantees.
  - Thanks to `nick-llewellyn` for the technical guidance on RFC 5705 constraints.

### Improved
Thanks to `nick-llewellyn` for the correctness audit enhancing the Marzullo consensus implementation:

- **Robust source counting**: Enhanced `participantCount` to use multiset-based unique source tracking. Multiple overlapping samples from a single source now correctly contribute one participant to the quorum.
- **Improved sweep algorithm**: The Marzullo sweep now optimizes on unique source diversity rather than raw interval overlap, yielding higher-quality consensus when sources provide multiple samples.
- **Precision safeguards**: Added minimum 1ms floor to `uncertaintyMs`. Narrow intervals now report realistic precision instead of implying sub-millisecond accuracy.
- **Input validation**: `SyncEngine` now filters samples with negative uncertainty before processing, protecting the monotonic clock reference from malformed measurements.
- **Enhanced anchor integrity**: Anchor creation now validates against `ConsensusResult.participants`, ensuring only samples overlapping the consensus window influence the trusted time estimate.

### Fixed
- **HTTP Security**: Updated `http` package constraints to resolve pub.dev security advisory decoding issues.
- **Pub.dev Compatibility**: Fixed `FormatException: advisoriesUpdated must be a String` error during dependency resolution.
- **Quorum Messaging**: Improved error messages to show accurate counts of eligible vs rejected samples with proper pluralization.

## [2.0.2]

### Fixed
- **Documentation**: Comprehensive enhancement of all public API dartdoc comments with detailed descriptions.
  - Replaced 8+ placeholder "Documented." comments with full documentation
  - Enhanced `TrustedTimeMock` constructor and method documentation
  - Added detailed docs for `TrustAnchor`, `SyncMetrics`, `ConsensusResult`
  - Documented exception classes and configuration classes
  - Improved public API coverage for pub.dev scoring

## [2.0.1]

### Fixed
- **Dependency Resolution**: Loosened constraints for `web`, `http`, and `timezone` to resolve pub.dev analyzer conflicts.
- **Documentation**: Enhanced dartdocs for public symbols to improve pub.dev score.

## [2.0.0]

### Added
- **Probabilistic Trust Modeling**: Introduced `ConfidenceLevel` (Low, Medium, High) and `confidenceScore` with exponential decay to model temporal uncertainty over time.
- **Self-Healing Consensus Engine**: 
    - **Adaptive Thresholds**: Dynamic sample filtering based on 3x median uncertainty.
    - **Exponential Source Cooldown**: Failure-count based blacklisting ($2^{failureCount}$ min) to isolate consistently unreliable authorities.
    - **Consensus Stability Guard**: Incremental processing now requires $N=2$ (or $N=3$ under high variance) consecutive matching intervals before early-exit.
- **NTS (RFC 8915) Authenticated Time**: Pure-Dart implementation of Network Time Security for tamper-proof NTP synchronization (Cryptographic Preview).
- **Enterprise Observability**: 
    - Introduced `SyncMetrics` for machine-readable telemetry (latency, uncertainty, diversity, depth).
    - Added structured **Confidence Breakdown** for deep-field debugging of trust establishment.
- **Strict Security Intent API**: New `TrustedTime.getTime({bool requireSecure})` for fail-fast cryptographic guarantees.
- **Capability Discovery**: Added `supportsSecureTime` to allow graceful application fallback when NTS is unavailable.
- **Robust Desktop Support**: Verified native implementations for macOS, Windows, and Linux, ensuring consistent monotonic clock behavior across all six Flutter platforms.
- **Intelligent Background Sync**: Scheduler-backed synchronization on mobile (WorkManager for Android, BGTaskScheduler for iOS) with safe `Timer`-based fallbacks for desktop.

### Changed
- **Domain Refactor**: Split `TimeSample` into `TimeInterval` (pure mathematical primitive) and `TimeSample` (enriched telemetry wrapper).
- **Integrity Feedback Loop**: Anomaly detection now triggers immediate state purge (cache invalidation) and high-priority synchronization.
- **Hardened Consensus**: Strictly enforced group-diversity requirements to mitigate median-poisoning and correlated failures.
- **Architecture Decisions**: Published comprehensive ADRs (0001-0004) covering monotonic strategy, Marzullo consensus, NTS implementation, and background sync.
- **Unified Darwin Layout**: Migrated iOS and macOS native implementations to a shared SwiftPM-ready directory for perfect pub.dev compliance.

### Fixed
- **Marzullo Engine Correctness**: 
  - Fixed tie-breaking to use closed-interval semantics (depth counting).
  - Corrected `participantCount` to report unique source IDs instead of raw overlap depth.
  - Implemented 1ms uncertainty floor to prevent downstream calculation errors.
- **Platform Hardening**: 
  - Windows: Migrated to `GetTickCount64` and subclassed `WM_TIMECHANGE` for robust integrity monitoring.
  - Linux: Switched to `CLOCK_BOOTTIME` and `timerfd` to correctly track time during system suspend.
  - Thread Safety: Re-affirmed and enforced main-thread dispatching for all Darwin platform event channels.

## 1.2.1

**Critical enhancements**
- iOS/macOS: Enhanced channel initialization avoiding naming mismatch
- Android: Optimized `BroadcastReceiver` lifecycle to efficiently detach
- Android: Upgraded `BackgroundSyncWorker` to perform HTTPS connectivity check
- `SyncClock.elapsedSinceAnchorMs()` upgraded to use Dart `Stopwatch` (monotonic) instead of wall-clock delta
- Linux: Implemented proper `get_platform_version()` parsing to resolve implicit logic
- Example integration test upgraded to effectively await `TrustedTime.initialize()`

**High-priority enhancements**
- iOS BGTask handler upgraded to perform HTTPS HEAD check (parity with Android worker)
- iOS BGTask closure stabilized to capture dynamic interval value
- Windows native test enhanced building with explicit constructor
- Example widget test stabilized to match actual app UI

**Engine improvements**
- Serialized sync via `Completer` introduced to prevent concurrent `_performSync()` calls
- Integrity events (`systemClockJumped`, `deviceRebooted`) configured to invalidate trust and optimally trigger resync
- Automatic retry engine introduced with configurable delay on sync failure
- Background sync optimally enabled on both warm-restore and cold-start paths
- `dispose()` architecture enhanced to clear `SyncClock` static state, preventing cross-test leakage
- `initialize()` short-circuits engine init immediately when test mock is active
- `timezoneChanged` streamlined as an intentional non-resync event (UTC is timezone-independent)
- All `debugPrint` calls optimized and guarded by `kDebugMode` for release builds

**Algorithm & sources optimizations**
- Marzullo tie-breaking upgraded: lower endpoints prioritize over upper at equal times
- `bestEnd` intelligently resets when finding new maximum overlap depth
- `HttpsSource`: Implemented robust HEAD→GET fallback architecture on 405 or missing Date header
- Comprehensive HTTP date parser expanded (RFC 7231 + RFC 850 formats)
- NTP source optimized via conditional imports (`dart:io` guard) for deep web compatibility
- `TrustedTimeConfig.operator==` and `hashCode` stabilized to comprehensively include `additionalSources`

**Platform native architecture**
- Android: Migrated `RECEIVER_NOT_EXPORTED` flags properly for API 33+ implicit-intent receivers
- Android: Deprecated and removed unused `SharedPreferences` writes from background worker
- Android: Standardized `build.gradle` structure alongside `AndroidManifest.xml`
- iOS: `BGTaskScheduler.register` initialization restricted optimally to run once via `bgRegistered` flag
- iOS: `Info.plist` properly documents `BGTaskSchedulerPermittedIdentifiers` requirement tracking
- Windows: Deprecated legacy `"trusted_time"` method channel registration safely
- Linux: Deprecated legacy `"trusted_time"` method channel registration safely
- Web: Registered `MethodChannel` handlers gracefully for monotonic and background channels

**Cleanup & Standardization**
- Deprecated 7 dead platform abstraction files
- Streamlined bundle, removing `plugin_platform_interface` dependency
- Reverted misleading `Package.swift` SPM target for CocoaPods plugin standard
- Stripped committed `test_results.txt` and `logcat_full.txt` logs fully prioritizing Git cleanliness
- Renamed `sync_engine_test.dart` → `models_test.dart` to logically match content
- Broadened SDK constraints scaling accessibility: `sdk: >=3.4.0`, `flutter: >=3.19.0`

**Validation Pipeline Enhancement**
- Scaled 54 total tests across 9 test files (up from 8 tests originally)
- Instated `TrustedTimeEstimate` tests (isReasonable, toString)
- Instated `IntegrityMonitor` tests (reboot detection, multiple attach, double dispose)
- Instated `TrustedTimeConfig` equality tests covering `additionalSources`
- Instated `SyncClock.reset()` verification structure
- Adjusted timing bounds dynamically in SyncClock tests for CI reliability scaling

**CI & Documentation**
- CI workflow modernized to deeply analyze example app alongside plugin
- `SECURITY.md` validation tables strictly updated
- `CHANGELOG.md` properly reflects comprehensive audit validations

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
