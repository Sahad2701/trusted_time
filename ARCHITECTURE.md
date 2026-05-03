# TrustedTime Architecture: Definitive Design Specification (v2.0.0)

This document is the definitive source of truth for the TrustedTime engine's design, internal state machine, API contract, and failure modes. It is intended for core contributors, platform embedders, and security auditors. All code reviews must reference this document to validate behavior.

## 1. Operational State Machine (First-Class Concept)

The engine is a deterministic finite state machine. Its state governs its API contract. Any transition must be an atomic operation.

| State        | Description                                                             | `getTime()` API Contract       | `sync()` Behavior                                    |
| ------------ | ----------------------------------------------------------------------- | ------------------------------ | ---------------------------------------------------- |
| `UNANCHORED` | Initial state or after integrity panic. No trusted time is available.   | Returns `TrustedTimeResult.unavailable()` (never throws). | Performs full quorum-seeking sync.                   |
| `ANCHORING`  | Initial sync in progress, no quorum achieved yet.                       | Returns last available result or `unavailable()`.            | Active; new sync calls are coalesced.                |
| `ANCHORED`   | Healthy state. A valid monotonic anchor exists with a confidence score. | Returns `TrustedTimeResult.available(time, confidence)`.   | Background refresh based on confidence decay.        |
| `DEGRADED`   | Anchor exists but confidence is below critical threshold (e.g., <0.4).   | Returns `TrustedTimeResult.degraded(time, confidence)`.    | Proactive, high-priority sync pending.               |
| `PANIC`      | Catastrophic failure detected. All state is purged.                    | Returns `TrustedTimeResult.unavailable()`.                   | Transitions to `UNANCHORED` after cooldown.            |

## 2. Core Philosophy: Monotonic Anchoring

The engine's foundational invariant: **Verified UTC is anchored to monotonic uptime, never the system wall clock.**

- **The Inviolable Formula:** `CurrentTrustedTime = (CurrentUptime - U_sync) + T_network`
- **Monotonicity Guarantee:** The OS monotonic clock is used as the `Anchor`. It is impervious to user or network time changes. It resets only on reboot, which is a guaranteed transition to the `UNANCHORED` state.
- **Performance Contract:** The `getTime()` operation under the `ANCHORED` state performs exactly one arithmetic calculation based on a cached anchor. It must not perform I/O, locking, or platform channel calls. Latency is bounded to <1µs.

## 3. Domain Model & Immutable Primitives

We enforce strict separation of concerns between mathematical truth and operational metadata. All domain objects are immutable value types.

- **`TrustedAnchor` (Internal Cache):** A pure value holding the foundational tuple: `(monotonicUptimeAtSync: int, networkTimeAtSync: int)`.
- **`TrustedTimeResult` (Public API):** A sealed class hierarchy returned by `getTime()`.
    - `TrustedTimeAvailable`: Contains `DateTime trustedTime`, `ConfidenceScore score`.
    - `TrustedTimeDegraded`: Contains `DateTime estimatedTime`, `ConfidenceScore score`, `DegradationReason reason`.
    - `TrustedTimeUnavailable`: Contains `UnavailabilityReason reason` (e.g., `noConnectivity`, `panicked`, `initializing`).
- **`ConfidenceScore`:** A value object encapsulating a `double` bounded between `0.1` and `1.0`. Its decay is modeled using a configurable half-life, not inside this object.
- **Invariant:** All raw network times are parsed into signed 64-bit integer milliseconds (`Int64`). Every interval `[start, end]` must have `start <= end`. Validation happens at the FFI boundary and factory constructors.

## 4. High-Integrity Consensus Engine (Marzullo's Evolution)

The consensus algorithm is the heart of trust establishment. It operates on an input set of `WeightedSample` objects.

### 4.1. Adversarial Fortification
- **Group-Aware Quorum:** The `QuorumPolicy` demands a minimum number of distinct groups (configurable, default: 2) in the agreeable set. This directly neutralizes data-center or AS-level poisoning attacks. A supermajority of samples from a single group is not a valid quorum.
- **Adaptive MAD Filtering:** Outlier rejection is not based on static thresholds. For each candidate interval, its uncertainty (`end - start`) is compared to the Median Absolute Deviation (MAD) of all intervals in the current selection. An interval is excluded if its uncertainty > `3 * median_uncertainty`. This adapts to live network jitter.
- **False-Positive Stability Guard:** A quorum's output `[start, end]` interval is only accepted if it overlaps with the *previous* sync cycle's accepted interval. This prevents a transient loss of diversity from being mistaken for convergence. This guard is bypassed if the engine is in `UNANCHORED` state (cold start).

### 4.2. Confidence Output
The final merged `TimeInterval`'s width and the quorum depth are inputs to a `ConfidenceEvaluator`. It outputs a `ConfidenceScore` derived from:
- **Overlap Depth:** Ratio of samples agreeing on the final interval vs. total valid samples.
- **Group Diversity:** Ratio of distinct groups in the quorum vs. total groups queried.
- **Temporal Stability:** Low-variance uncertainty across multiple successful sync cycles increases the score.

## 5. Self-Healing Sync Strategy

The `SyncEngine` manages the life cycle from `UNANCHORED` to `ANCHORED` and defends against degradation.

- **Racing with Incremental Resolution:** All configured `TimeSource` objects are queried concurrently. The consensus algorithm re-evaluates the available samples on every single callback. A valid quorum triggers an **Early Exit**, canceling all pending source queries to conserve power and bandwidth immediately.
- **Source Cooldown Manager:** Failed sources are not blacklisted permanently. Their `failureScore` is incremented using an exponential backoff: `cooldownDuration = min(2^failureCount * base_cooldown, max_cooldown)`. A source is not queried if it's in its active cooldown window.
- **Integrity Feedback Loop:** The `IntegrityMonitor` continuously watches for OS time changes. Upon detecting a wall-clock discontinuity (not a monotonic jump), it does not guess. It triggers an immediate, non-reversible transition to the `PANIC` state, purges the anchor cache, and after a configurable `panicCooldown`, directs the state machine to `UNANCHORED` to restart the sync process.

## 6. Platform Strategy: Secure-by-Design Bridge

The platform interface is an abstract, testable boundary (`TimeSourceInterface`). The native implementation is a thin, secure adapter.

- **Pure-Dart NTS:** The core implementation of RFC 8915 (Network Time Security) is Pure Dart using `dart:typed_data` and `dart:isolate` for cryptographic operations, ensuring it is platform-agnostic and auditable.
- **Secure Dart-Native Bridge:** The platform channel for time change detection is not a raw event stream.
    1.  **Detection Agent (Native):** Uses the most reliable signal available: Android's `ACTION_TIME_CHANGED` broadcast (API-level aware) or iOS's `NSSystemClockDidChangeNotification`. It measures the monotonic clock *immediately* in native code and passes this single integer value to Dart. **No platform-enforced main thread dispatching is relied upon for this signal.**
    2.  **Verification Agent (Dart):** Receives the notification and the native monotonic timestamp. It independently re-reads the current monotonic clock and compares the difference. If the elapsed time since the signal is implausibly large (e.g., >100ms), it is flagged as a potential false-positive/system suspension and does not trigger a panic. This double-checking eliminates the "lean glue" risk.
- **Thread Contract (Darwin):** For non-time-critical API calls originating from Flutter to native (e.g., logging), Darwin-specific code must dispatch to the main thread. The critical time detection path described above is lock-free and thread-safe by design, operating exclusively on integer comparisons.
