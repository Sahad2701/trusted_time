/// A Flutter plugin for obtaining a highly-trusted, tamper-proof current time.
///
/// `TrustedTime` provides a virtual clock that remains accurate even if the
/// user manually adjusts the device system clock. This is achieved by
/// synchronizing with multiple network sources (NTP/HTTPS) and anchoring
/// the result to the device's internal monotonic hardware uptime.
library;

export 'src/core_engine.dart';
export 'src/formatter.dart';
export 'src/exceptions.dart';
export 'src/network_resolver.dart' show NetworkTimeResult;
