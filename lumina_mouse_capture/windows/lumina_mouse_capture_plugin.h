// Channel glue for the Windows pointer capture.
//
// Method channel `lumina_mouse_capture`: `support`, `capture` ({x, y} in the
// Flutter view's logical coordinates, optional), `release`.
// Event channel `lumina_mouse_capture/events`: {type: motion, dx, dy},
// {type: locked}, {type: lost, reason}.
#ifndef FLUTTER_PLUGIN_LUMINA_MOUSE_CAPTURE_PLUGIN_H_
#define FLUTTER_PLUGIN_LUMINA_MOUSE_CAPTURE_PLUGIN_H_

#include <flutter/encodable_value.h>
#include <flutter/event_channel.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>
#include <optional>

#include "pointer_capture.h"
#include "pointer_os.h"

namespace lumina_mouse_capture {

class LuminaMouseCapturePlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  explicit LuminaMouseCapturePlugin(flutter::PluginRegistrarWindows* registrar);
  // Releases any capture still in force before the engine goes away.
  ~LuminaMouseCapturePlugin() override;

  LuminaMouseCapturePlugin(const LuminaMouseCapturePlugin&) = delete;
  LuminaMouseCapturePlugin& operator=(const LuminaMouseCapturePlugin&) = delete;

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  std::optional<LRESULT> HandleWindowMessage(HWND hwnd, UINT message,
                                             WPARAM wparam, LPARAM lparam);
  void Send(flutter::EncodableMap event);

  flutter::PluginRegistrarWindows* registrar_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>> event_channel_;
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> sink_;
  // Declared before capture_: the capture uses it until its own destructor.
  std::unique_ptr<PointerOs> os_;
  std::unique_ptr<PointerCapture> capture_;
  int window_proc_id_ = -1;
};

}  // namespace lumina_mouse_capture

#endif  // FLUTTER_PLUGIN_LUMINA_MOUSE_CAPTURE_PLUGIN_H_
