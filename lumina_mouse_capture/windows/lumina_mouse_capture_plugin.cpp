#include "lumina_mouse_capture_plugin.h"

#include <windows.h>

#include <flutter/event_stream_handler_functions.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <optional>
#include <string>
#include <utility>
#include <variant>

namespace lumina_mouse_capture {

namespace {

using flutter::EncodableMap;
using flutter::EncodableValue;

std::optional<double> ReadNumber(const EncodableMap& map, const char* key) {
  const auto it = map.find(EncodableValue(key));
  if (it == map.end()) return std::nullopt;
  if (const auto* d = std::get_if<double>(&it->second)) return *d;
  if (const auto* i = std::get_if<int32_t>(&it->second)) return static_cast<double>(*i);
  if (const auto* l = std::get_if<int64_t>(&it->second)) return static_cast<double>(*l);
  return std::nullopt;
}

}  // namespace

// static
void LuminaMouseCapturePlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  registrar->AddPlugin(std::make_unique<LuminaMouseCapturePlugin>(registrar));
}

LuminaMouseCapturePlugin::LuminaMouseCapturePlugin(
    flutter::PluginRegistrarWindows* registrar)
    : registrar_(registrar), os_(CreateWin32PointerOs()) {
  // The view's window exists now; its top-level parent may not yet (the
  // runner parents the view after registering plugins), so the capture looks
  // the top-level up when it captures.
  flutter::FlutterView* view = registrar->GetView();
  HWND view_window = view != nullptr ? view->GetNativeWindow() : nullptr;

  CaptureCallbacks callbacks;
  callbacks.motion = [this](double dx, double dy) {
    Send(EncodableMap{{EncodableValue("type"), EncodableValue("motion")},
                      {EncodableValue("dx"), EncodableValue(dx)},
                      {EncodableValue("dy"), EncodableValue(dy)}});
  };
  callbacks.locked = [this]() {
    Send(EncodableMap{{EncodableValue("type"), EncodableValue("locked")}});
  };
  callbacks.lost = [this](const char* reason) {
    Send(EncodableMap{{EncodableValue("type"), EncodableValue("lost")},
                      {EncodableValue("reason"), EncodableValue(reason)}});
  };
  capture_ = std::make_unique<PointerCapture>(os_.get(), view_window,
                                              std::move(callbacks));

  channel_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      registrar->messenger(), "lumina_mouse_capture",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    HandleMethodCall(call, std::move(result));
  });

  event_channel_ = std::make_unique<flutter::EventChannel<EncodableValue>>(
      registrar->messenger(), "lumina_mouse_capture/events",
      &flutter::StandardMethodCodec::GetInstance());
  event_channel_->SetStreamHandler(
      std::make_unique<flutter::StreamHandlerFunctions<EncodableValue>>(
          [this](const EncodableValue*,
                 std::unique_ptr<flutter::EventSink<EncodableValue>>&& events)
              -> std::unique_ptr<flutter::StreamHandlerError<EncodableValue>> {
            sink_ = std::move(events);
            return nullptr;
          },
          [this](const EncodableValue*)
              -> std::unique_ptr<flutter::StreamHandlerError<EncodableValue>> {
            sink_.reset();
            return nullptr;
          }));

  window_proc_id_ = registrar->RegisterTopLevelWindowProcDelegate(
      [this](HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
        return HandleWindowMessage(hwnd, message, wparam, lparam);
      });
}

LuminaMouseCapturePlugin::~LuminaMouseCapturePlugin() {
  if (window_proc_id_ >= 0) {
    registrar_->UnregisterTopLevelWindowProcDelegate(window_proc_id_);
  }
  if (channel_) channel_->SetMethodCallHandler(nullptr);
  if (event_channel_) event_channel_->SetStreamHandler(nullptr);
  sink_.reset();
  // Gives the pointer back (no event: the engine is going away).
  capture_.reset();
  os_.reset();
}

void LuminaMouseCapturePlugin::Send(EncodableMap event) {
  if (sink_) sink_->Success(EncodableValue(std::move(event)));
}

std::optional<LRESULT> LuminaMouseCapturePlugin::HandleWindowMessage(
    HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
  if (!capture_) return std::nullopt;
  capture_->HandleMessage(hwnd, message, wparam, lparam);
  // The plugin's own flush message ends here; every window message continues
  // to Flutter and DefWindowProc (WM_INPUT needs DefWindowProc too).
  if (os_ && message == os_->FlushMessage()) return 0;
  return std::nullopt;
}

void LuminaMouseCapturePlugin::HandleMethodCall(
    const flutter::MethodCall<EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  const std::string& method = call.method_name();
  if (method == "support") {
    const Support support = capture_->GetSupport();
    result->Success(EncodableValue(EncodableMap{
        {EncodableValue("kind"), EncodableValue(KindName(support.kind))},
        {EncodableValue("pointerLock"), EncodableValue(support.pointer_lock)},
        {EncodableValue("relativeMotion"),
         EncodableValue(support.relative_motion)},
        {EncodableValue("detail"), EncodableValue(support.detail)},
    }));
  } else if (method == "capture") {
    bool has_centre = false;
    double x = 0;
    double y = 0;
    if (const auto* args = std::get_if<EncodableMap>(call.arguments())) {
      const auto cx = ReadNumber(*args, "x");
      const auto cy = ReadNumber(*args, "y");
      if (cx && cy) {
        has_centre = true;
        x = *cx;
        y = *cy;
      }
    }
    result->Success(EncodableValue(capture_->Capture(has_centre, x, y)));
  } else if (method == "release") {
    capture_->Release();
    result->Success();
  } else {
    result->NotImplemented();
  }
}

}  // namespace lumina_mouse_capture
