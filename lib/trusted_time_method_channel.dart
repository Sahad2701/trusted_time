import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'trusted_time_platform_interface.dart';

/// An implementation of [TrustedTimePlatform] that uses method channels.
class MethodChannelTrustedTime extends TrustedTimePlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('trusted_time');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }
}
