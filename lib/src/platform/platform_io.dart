import 'dart:io';
import '../../trusted_time_platform_interface.dart';
import 'trusted_time_method_channel.dart';
import 'trusted_time_desktop.dart';

/// IO-specific provider implementation (Mobile/Desktop).
TrustedTimePlatform getPlatformInstance() {
  if (Platform.isAndroid || Platform.isIOS) {
    return MethodChannelTrustedTime();
  }
  return TrustedTimeDesktop();
}
