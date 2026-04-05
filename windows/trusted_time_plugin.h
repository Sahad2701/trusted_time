#ifndef FLUTTER_PLUGIN_TRUSTED_TIME_PLUGIN_H_
#define FLUTTER_PLUGIN_TRUSTED_TIME_PLUGIN_H_

// Any translation unit that includes this header needs HWND, UINT_PTR, and
// DWORD_PTR, all of which are defined in windows.h. Relying on the includer
// to have already pulled in windows.h is fragile and breaks unity builds.
#include <commctrl.h>
#include <windows.h>

#include <flutter/event_channel.h>
#include <flutter/event_stream_handler_functions.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace trusted_time {

class TrustedTimePlugin : public flutter::Plugin {
public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  explicit TrustedTimePlugin(flutter::PluginRegistrarWindows *registrar);

  virtual ~TrustedTimePlugin();

  // Disallow copy and assign.
  TrustedTimePlugin(const TrustedTimePlugin &) = delete;
  TrustedTimePlugin &operator=(const TrustedTimePlugin &) = delete;

  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>>
  HandleOnListen(
      const flutter::EncodableValue *arguments,
      std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> &&events);

  std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>>
  HandleOnCancel(const flutter::EncodableValue *arguments);

private:
  flutter::PluginRegistrarWindows *registrar_ = nullptr;
  HWND hwnd_ = nullptr;
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> event_sink_;

  // Lambdas posted via PostMessage capture this flag by value. If the plugin
  // is destroyed before the message is dispatched, the flag is set to false
  // in the destructor and the lambda body safely no-ops — no dangling pointer
  // dereference and no heap leak of the lambda itself (it is still deleted by
  // the WM_POST_LAMBDA handler; it just does nothing).
  std::shared_ptr<bool> alive_;

  static LRESULT CALLBACK SubclassWindowProc(HWND hWnd, UINT uMsg,
                                             WPARAM wParam, LPARAM lParam,
                                             UINT_PTR uIdSubclass,
                                             DWORD_PTR dwRefData);
};

} // namespace trusted_time

#endif // FLUTTER_PLUGIN_TRUSTED_TIME_PLUGIN_H_