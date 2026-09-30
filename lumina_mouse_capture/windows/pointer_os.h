// The only door between the capture state machine and the Windows pointer.
//
// PointerCapture (pointer_capture.h) never calls Win32 itself: everything that
// clips, hides, moves or reads the pointer goes through this interface. The
// plugin uses Win32PointerOs (win32_pointer_os.cpp); the state-machine tests
// use a fake that records the calls and never touches the real pointer.
#ifndef LUMINA_MOUSE_CAPTURE_POINTER_OS_H_
#define LUMINA_MOUSE_CAPTURE_POINTER_OS_H_

#include <windows.h>

#include <memory>
#include <string>

namespace lumina_mouse_capture {

// A rectangle in virtual-screen pixels (may be negative on multi-monitor
// desktops); right and bottom are exclusive, as in RECT.
struct ScreenRect {
  long left = 0;
  long top = 0;
  long right = 0;
  long bottom = 0;

  long width() const { return right - left; }
  long height() const { return bottom - top; }
  bool operator==(const ScreenRect& o) const {
    return left == o.left && top == o.top && right == o.right &&
           bottom == o.bottom;
  }
};

struct ScreenPoint {
  long x = 0;
  long y = 0;
  bool operator==(const ScreenPoint& o) const { return x == o.x && y == o.y; }
};

// One WM_INPUT mouse report: RAWMOUSE's usFlags, lLastX and lLastY.
struct RawMouseSample {
  unsigned short flags = 0;
  long last_x = 0;
  long last_y = 0;
};

class PointerOs {
 public:
  virtual ~PointerOs() = default;

  // The environment variable [name], or empty when unset.
  virtual std::string Environment(const char* name) = 0;

  // The top-level window that holds [view] (null while [view] has no parent
  // top-level yet, or when it is gone).
  virtual HWND TopLevelOf(HWND view) = 0;
  // Whether [top_level] is the foreground window.
  virtual bool IsForeground(HWND top_level) = 0;
  // [view]'s client area in virtual-screen pixels.
  virtual bool ViewClientRect(HWND view, ScreenRect* rect) = 0;
  // [view]'s DPI divided by 96: logical Flutter pixels to physical pixels.
  virtual double ScaleOf(HWND view) = 0;
  // The whole virtual desktop, and the primary monitor (the two frames of
  // an absolute raw mouse report).
  virtual ScreenRect VirtualScreen() = 0;
  virtual ScreenRect PrimaryMonitor() = 0;

  virtual bool GetCursorPosition(ScreenPoint* point) = 0;
  virtual bool SetCursorPosition(ScreenPoint point) = 0;
  // Confines the pointer to [rect]; null removes the confinement.
  virtual bool ClipCursorTo(const ScreenRect* rect) = 0;
  // ShowCursor(TRUE/FALSE): the thread's display counter after the call.
  virtual int ShowCursorCounter(bool show) = 0;

  // Raw mouse input (usage page 1, usage 2) for [target]; legacy mouse
  // messages stay on. Unregister removes the registration.
  virtual bool RegisterRawMouse(HWND target) = 0;
  virtual bool UnregisterRawMouse() = 0;
  // Reads the mouse report of a WM_INPUT message's lParam; false for other
  // devices.
  virtual bool ReadRawMouse(LPARAM lparam, RawMouseSample* sample) = 0;

  // The message that asks for accumulated motion to be sent, and posting it
  // to [top_level] (it comes back through the window proc delegate).
  virtual UINT FlushMessage() = 0;
  virtual bool PostFlush(HWND top_level) = 0;
};

// The real Windows implementation.
std::unique_ptr<PointerOs> CreateWin32PointerOs();

}  // namespace lumina_mouse_capture

#endif  // LUMINA_MOUSE_CAPTURE_POINTER_OS_H_
