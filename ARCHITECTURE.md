# TrustedTime Architecture

This document provides a technical deep-dive into the internals of the TrustedTime engine. It is intended for contributors and security auditors.

## The Core Problem: Clock Tampering

In mobile ecosystems, the system clock (`DateTime.now()`) is a "Wall Clock" that can be modified by the user at any time. This makes it unsuitable for:
- Licensing checks (trial extensions).
- Ticketing (using a ticket before it's valid).
- Security logging (anti-replay).

## The Solution: Monotonic Anchoring

TrustedTime establishes a **Trust Anchor** by linking a verified UTC network time to the device's **Monotonic Hardware Uptime**.

### 1. Monotonic Uptime
Every modern CPU has a monotonic counter (hardware oscillator) that starts at 0 when the device boots and increments continuously.
- **Android**: `SystemClock.elapsedRealtime()`
- **iOS**: `ProcessInfo.processInfo.systemUptime`
- **Web**: `window.performance.now()`

Crucially, **monotonic uptime cannot be changed by the user.**

### 2. The Anchor Formula
When the engine synchronizes with the network, it captures two values at the exact same moment:
1. `T_network`: The verified UTC time.
2. `U_sync`: The device's monotonic uptime.

The relationship is then defined as:
`CurrentTrustedTime = (CurrentUptime - U_sync) + T_network`

## Network Quorum (Marzullo's Algorithm)

To prevent reliance on a single potentially compromised or laggy server, TrustedTime uses a **Consensus Strategy**.

1. **Fan-out**: Queries 3-5 sources in parallel (NTP + HTTPS).
2. **Interval Estimation**: Each source provides a time `T` and an error `E` (based on RTT).
3. **Consensus**: Marzullo's Algorithm finds the widest overlapping interval that contains the true time. Outliers are discarded.

## State Persistence

The anchor is stored in encrypted platform storage (`Keychain` or `Keystore`).
- **Persistence Logic**: On app restart, we load the anchor. If `CurrentUptime > U_sync`, the anchor is still valid (no reboot has occurred).
- **Integrity Loss**: If `CurrentUptime < U_sync`, the device has rebooted, the monotonic counter has reset, and a new network sync is required.

## Performance Analysis

### Synchronous Retrieval
Because `now()` is a simple subtraction and addition of local variables, it is computationally trivial.
- **Time Complexity**: O(1)
- **Latenty**: < 1μs

### Memory Management
The engine is designed as a "Zero-Alloc" module during steady-state operation. No objects are allocated in the `now()` path, minimizing GC pressure for high-frequency trading or gaming applications.

