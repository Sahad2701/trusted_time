## [1.0.1] - 2026-02-08

Initial release
* Handle missing git tags in release workflow (5cdb62c)
* Add verbose debug logs to release workflow (686965c)
* Handle initial release in release workflow (f802bf9)
* Add release workflow, bump script, update CI (149fcbc)
* style: Remove unused import in platform interface (c8dad53)
* style: Final formatting pass for platform stub (abd4f74)
* fix: Resolve test compilation errors and improve platform-aware testing (b175b0d)
* style: Final formatting pass for pub.dev compliance (262f257)
* feat: Add full platform support (Web/Desktop) and SPM compliance (36417ac)
* chore: Update official URLs in pubspec and README after live release (eb9283a)
* style: Apply standard Dart formatting (d04b971)
* chore: Reduce topics to meet pub.dev 5-topic limit (3716ab6)
* feat: Initial Release v1.0.0 (3f71f27)
# Changelog

## 1.0.0

- **Initial High-Integrity Release**: Production-ready engine for tamper-proof UTC time.
- **Marzullo Consensus**: Multi-source quorum resolution from Tier-1 NTP and HTTPS providers.
- **Temporal Baseline**: Hardware-anchored monotonic timeline ensuring zero-drift consistency.
- **Full Jitter Backoff**: Industry-standard retry strategy for high-resiliency cloud connectivity.
- **Zero-Alloc Performance**: Memory-optimized internal stack with <1μs synchronous retrieval.
