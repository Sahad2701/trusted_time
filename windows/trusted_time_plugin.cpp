#include "trusted_time_plugin.h"

// windows.h is already included via the header (FIX W1), but listing it here
// explicitly keeps the .cpp self-documenting and harmless (include guards
// prevent double inclusion).
#include <commctrl.h>
#include <windows.h>

#include <flutter/event_channel.h>
#include <flutter/event_stream_handler_functions.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <functional>
#include <memory>
#include <sstream>

// Custom window message used to marshal work back onto the UI thread.
// The lParam carries a heap-allocated std::function<void()>* that the handler
// invokes then deletes.
#define WM_POST_LAMBDA (WM_USER + 100)

namespace trusted_time {

// Registration
// static
void TrustedTimePlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar) {
  auto plugin = std::make_unique<TrustedTimePlugin>(registrar);

  // Monotonic clock channel.
  auto monotonic_channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "trusted_time/monotonic",
          &flutter::StandardMethodCodec::GetInstance());
  monotonic_channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto &call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  // Background sync channel (stub on Windows — Dart Timer.periodic handles
  // scheduling; native task scheduling would require installer-level
  // permissions this plugin does not hold).
  auto background_channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "trusted_time/background",
          &flutter::StandardMethodCodec::GetInstance());
  background_channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto &call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  // Integrity event channel.
  auto event_channel =
      std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
          registrar->messenger(), "trusted_time/integrity",
          &flutter::StandardMethodCodec::GetInstance());
  event_channel->SetStreamHandler(
      std::make_unique<
          flutter::StreamHandlerFunctions<flutter::EncodableValue>>(
          [plugin_pointer = plugin.get()](
              const flutter::EncodableValue *arguments,
              std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>
                  &&events) {
            return plugin_pointer->HandleOnListen(arguments, std::move(events));
          },
          [plugin_pointer =
               plugin.get()](const flutter::EncodableValue *arguments) {
            return plugin_pointer->HandleOnCancel(arguments);
          }));

  registrar->AddPlugin(std::move(plugin));
}

// Constructor / destructor
TrustedTimePlugin::TrustedTimePlugin(flutter::PluginRegistrarWindows *registrar)
    : registrar_(registrar),
      // FIX W3/W4: initialise the alive flag to true.
      alive_(std::make_shared<bool>(true)) {}

TrustedTimePlugin::~TrustedTimePlugin() {
  // FIX W3/W4: signal all in-flight lambdas that the plugin is gone.
  // Any WM_POST_LAMBDA messages still queued will check this flag before
  // touching plugin state, so they safely no-op. The lambda heap objects
  // themselves are still deleted by the WM_POST_LAMBDA handler — no leak.
  *alive_ = false;

  if (hwnd_) {
    RemoveWindowSubclass(hwnd_, SubclassWindowProc, 1);
    hwnd_ = nullptr;
  }
}

void TrustedTimePlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (method_call.method_name() == "getPlatformVersion") {
    result->Success(flutter::EncodableValue(std::string("Windows 10+")));
  } else if (method_call.method_name() == "getUptimeMs") {
    // GetTickCount64 returns milliseconds since system boot and is immune to
    // user-level system-clock manipulation. Available on Vista+; Flutter itself
    // requires Windows 10 build 1809, so no version guard is needed.
    int64_t uptimeMs = static_cast<int64_t>(GetTickCount64());
    result->Success(flutter::EncodableValue(uptimeMs));
  } else if (method_call.method_name() == "enableBackgroundSync") {
    // Background sync is stubbed on Windows. The Dart layer already provides
    // a Timer.periodic fallback for desktop platforms where the app runs
    // persistently. Returning true signals the Dart side that no error
    // occurred.
    result->Success(flutter::EncodableValue(true));
  } else {
    result->NotImplemented();
  }
}

std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>>
TrustedTimePlugin::HandleOnListen(
    const flutter::EncodableValue *arguments,
    std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> &&events) {
  // FIX W2: guard against a second listen call while already subscribed.
  // Without this, a second call would destroy the current event_sink_
  // unique_ptr while the subclass proc still holds a raw plugin* whose
  // event_sink_ is now invalid, and SetWindowSubclass would be called again on
  // the same HWND with the same subclass ID (returning FALSE silently).
  if (hwnd_) {
    return nullptr; // Already listening; Dart stream re-subscription is a
                    // no-op.
  }

  // FIX W5: obtain and validate the HWND before accepting the subscription.
  // If the view or window handle is unavailable (e.g. headless test runner),
  // return a descriptive error so the Dart side knows integrity events will
  // not fire rather than silently succeeding.
  flutter::FlutterView *view = registrar_->GetView();
  if (!view) {
    return std::make_unique<
        flutter::StreamHandlerError<flutter::EncodableValue>>(
        "NO_VIEW",
        "Flutter view is unavailable; cannot install WM_TIMECHANGE hook.",
        nullptr);
  }

  HWND hwnd = view->GetNativeWindow();
  if (!hwnd) {
    return std::make_unique<
        flutter::StreamHandlerError<flutter::EncodableValue>>(
        "NO_HWND",
        "Native window handle is null; cannot install WM_TIMECHANGE hook.",
        nullptr);
  }

  // Install the subclass proc before storing the sink so that if installation
  // fails we do not store a sink that will never receive events.
  if (!SetWindowSubclass(hwnd, SubclassWindowProc, 1,
                         reinterpret_cast<DWORD_PTR>(this))) {
    return std::make_unique<
        flutter::StreamHandlerError<flutter::EncodableValue>>(
        "SUBCLASS_FAILED",
        "SetWindowSubclass failed; WM_TIMECHANGE will not be intercepted.",
        nullptr);
  }

  hwnd_ = hwnd;
  event_sink_ = std::move(events);
  return nullptr;
}

std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>>
TrustedTimePlugin::HandleOnCancel(const flutter::EncodableValue *arguments) {
  // Drain the event sink first. Resetting it means any lambda that fires
  // between now and when the WM_POST_LAMBDA is dispatched will check alive_
  // and see event_sink_ is null, preventing a use-after-free.
  event_sink_.reset();

  if (hwnd_) {
    RemoveWindowSubclass(hwnd_, SubclassWindowProc, 1);
    hwnd_ = nullptr;
  }
  return nullptr;
}

// static
LRESULT CALLBACK TrustedTimePlugin::SubclassWindowProc(HWND hWnd, UINT uMsg,
                                                       WPARAM wParam,
                                                       LPARAM lParam,
                                                       UINT_PTR uIdSubclass,
                                                       DWORD_PTR dwRefData) {

  // Dispatch heap-allocated lambdas posted from WM_TIMECHANGE handling.
  if (uMsg == WM_POST_LAMBDA) {
    auto *fn = reinterpret_cast<std::function<void()> *>(lParam);
    if (fn) {
      (*fn)();
      delete fn;
    }
    return 0;
  }

  if (uMsg == WM_TIMECHANGE) {
    TrustedTimePlugin *plugin =
        reinterpret_cast<TrustedTimePlugin *>(dwRefData);

    if (plugin) {
      // FIX W3/W4: capture the alive flag by value (shared_ptr copy, ref-count
      // incremented). If the plugin is destroyed before this lambda executes,
      // *alive_flag is false and we skip all plugin-state access. The lambda
      // object itself is still deleted by WM_POST_LAMBDA, so there is no leak.
      std::shared_ptr<bool> alive_flag = plugin->alive_;

      auto *fn = new std::function<void()>([plugin, alive_flag]() {
        // If the plugin was destroyed after PostMessage but before dispatch,
        // bail out without touching plugin memory.
        if (!(*alive_flag)) {
          return;
        }
        if (plugin->event_sink_) {
          flutter::EncodableMap map;
          map[flutter::EncodableValue("type")] =
              flutter::EncodableValue("clockJumped");
          plugin->event_sink_->Success(flutter::EncodableValue(map));
        }
      });

      PostMessage(hWnd, WM_POST_LAMBDA, 0, reinterpret_cast<LPARAM>(fn));
    }
  }

  return DefSubclassProc(hWnd, uMsg, wParam, lParam);
}

} // namespace trusted_time