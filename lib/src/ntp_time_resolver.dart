/// A high-performance resolver that fetches trusted time using the NTP protocol.
///
/// NTP (Network Time Protocol) provides sub-millisecond precision by using
/// specialized hardware timestamps at the server level.
///
/// Note: On Web platforms, this resolver is a stub as raw UDP sockets
/// are not supported in the browser.
library;

export 'ntp_time_resolver_stub.dart'
    if (dart.library.io) 'ntp_time_resolver_io.dart';
