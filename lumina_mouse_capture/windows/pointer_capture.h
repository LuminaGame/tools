// Pointer capture for a Flutter Windows view: raw mouse input for relative
// motion, with the cursor hidden and clipped to one pixel at the requested
// centre so it cannot leave the game however far the mouse moves.
//
// No Flutter types and no direct Win32 calls: the OS goes through PointerOs,
// so the state machine runs in tests against a fake without touching the
// pointer of the person at the machine. The plugin glue
// (lumina_mouse_capture_plugin.cpp) forwards channel calls, window messages
// and events.
#ifndef LUMINA_MOUSE_CAPTURE_POINTER_CAPTURE_H_
#define LUMINA_MOUSE_CAPTURE_POINTER_CAPTURE_H_

#include <windows.h>

#include <functional>
#include <string>

#include "pointer_os.h"

namespace lumina_mouse_capture {

enum class Kind { kWindows, kUnsupported, kDisabled };

// The Dart-side name of [kind] (`MouseCaptureBackendKind`).
const char* KindName(Kind kind);

struct Support {
  Kind kind = Kind::kUnsupported;
  bool pointer_lock = false;
  bool relative_motion = false;
  std::string detail;
};

// Why a capture ended without Release(); the `reason` of a `lost` event.
namespace lost_reason {
inline constexpr const char* kFocus = "focus";
inline constexpr const char* kMinimized = "minimized";
inline constexpr const char* kWindow = "window";
}  // namespace lost_reason

struct CaptureCallbacks {
  // The mouse moved by (dx, dy) logical pixels while captured.
  std::function<void(double dx, double dy)> motion;
  // The capture is in place.
  std::function<void()> locked;
  // The capture ended without Release(): focus loss, minimise, the window
  // went away.
  std::function<void(const char* reason)> lost;
};

// True when LUMINA_MOUSE_CAPTURE is `off` or `record`: nothing may capture
// the pointer (tests, smokes and the harnesses that start the editor).
bool DisabledByEnvironment(PointerOs& os);

class PointerCapture {
 public:
  // [os] must outlive this object. [view] is the Flutter view's window,
  // whose client coordinates (logical pixels) Capture() takes.
  PointerCapture(PointerOs* os, HWND view, CaptureCallbacks callbacks);
  // Releases a capture still in force (without reporting lost).
  ~PointerCapture();

  PointerCapture(const PointerCapture&) = delete;
  PointerCapture& operator=(const PointerCapture&) = delete;

  Support GetSupport();

  // Captures the pointer at ([x], [y]) in the view's logical coordinates, or
  // at the view's centre without [has_centre]. Refused (false, and nothing
  // touched) under LUMINA_MOUSE_CAPTURE=off, without a view or top-level
  // window, or while the window is not in the foreground. A capture already
  // in force moves to the new centre.
  bool Capture(bool has_centre, double x, double y);

  // Gives the pointer back: unclipped, shown, where it was before the
  // capture, raw input unregistered. A no-op when not captured.
  void Release();

  bool captured() const { return captured_; }

  // A message of the top-level window (the plugin's window proc delegate).
  // Observes only: the message always continues to Flutter and
  // DefWindowProc.
  void HandleMessage(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam);

 private:
  bool ComputeClip(ScreenRect* clip, double* scale);
  bool ApplyClip();
  void OnRawInput(LPARAM lparam);
  void Flush();
  void Lose(const char* reason);
  // Undoes whatever the capture did to the OS, in reverse.
  void RestoreOs();

  PointerOs* os_;
  HWND view_;
  CaptureCallbacks callbacks_;

  bool captured_ = false;
  HWND top_level_ = nullptr;
  bool has_centre_ = false;
  double centre_x_ = 0;
  double centre_y_ = 0;
  double scale_ = 1.0;

  // What the capture changed, so RestoreOs() undoes exactly that.
  bool raw_registered_ = false;
  bool clipped_ = false;
  int hide_calls_ = 0;
  bool saved_position_valid_ = false;
  ScreenPoint saved_position_;

  // Motion in physical pixels, waiting for the posted flush.
  double pending_dx_ = 0;
  double pending_dy_ = 0;
  bool flush_posted_ = false;
  bool has_absolute_ = false;
  bool absolute_virtual_ = false;
  double last_absolute_x_ = 0;
  double last_absolute_y_ = 0;
};

}  // namespace lumina_mouse_capture

#endif  // LUMINA_MOUSE_CAPTURE_POINTER_CAPTURE_H_
