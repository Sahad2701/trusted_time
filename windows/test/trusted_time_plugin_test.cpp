#include <flutter/method_call.h>
#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>
#include <gtest/gtest.h>
#include <windows.h>

#include <memory>
#include <string>
#include <variant>

#include "trusted_time_plugin.h"

namespace trusted_time {
namespace test {

namespace {

using flutter::EncodableMap;
using flutter::EncodableValue;
using flutter::MethodCall;
using flutter::MethodResultFunctions;

}  // namespace

TEST(TrustedTimePlugin, GetPlatformVersion) {
  // Pass nullptr — HandleMethodCall does not dereference registrar_ for
  // getPlatformVersion or getUptimeMs, only for HandleOnListen (window handle).
  TrustedTimePlugin plugin(nullptr);

  std::string result_string;
  plugin.HandleMethodCall(
      MethodCall("getPlatformVersion", std::make_unique<EncodableValue>()),
      std::make_unique<MethodResultFunctions<>>(
          [&result_string](const EncodableValue* result) {
            result_string = std::get<std::string>(*result);
          },
          nullptr, nullptr));

  EXPECT_TRUE(result_string.rfind("Windows ", 0) == 0);
}

TEST(TrustedTimePlugin, GetUptimeMs) {
  TrustedTimePlugin plugin(nullptr);

  int64_t uptime_ms = 0;
  plugin.HandleMethodCall(
      MethodCall("getUptimeMs", std::make_unique<EncodableValue>()),
      std::make_unique<MethodResultFunctions<>>(
          [&uptime_ms](const EncodableValue* result) {
            uptime_ms = std::get<int64_t>(*result);
          },
          nullptr, nullptr));

  EXPECT_GT(uptime_ms, 0);
}

}  // namespace test
}  // namespace trusted_time
