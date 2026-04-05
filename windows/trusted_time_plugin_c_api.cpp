#include "include/trusted_time/trusted_time_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "trusted_time_plugin.h"

void TrustedTimePluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  trusted_time::TrustedTimePlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}