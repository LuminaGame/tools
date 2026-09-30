// The real PointerOs: the Win32 calls behind the capture state machine.
//
// Only the plugin creates this; the state-machine tests use a fake and never
// link this file.
#include <windows.h>

#include <memory>
#include <string>

#include "pointer_os.h"

namespace lumina_mouse_capture {

namespace {

constexpr USHORT kGenericDesktopPage = 0x01;
constexpr USHORT kMouseUsage = 0x02;

class Win32PointerOs : public PointerOs {
 public:
  std::string Environment(const char* name) override {
    char buffer[64];
    const DWORD length =
        GetEnvironmentVariableA(name, buffer, static_cast<DWORD>(sizeof(buffer)));
    if (length == 0 || length >= sizeof(buffer)) return std::string();
    return std::string(buffer, length);
  }

  HWND TopLevelOf(HWND view) override {
    if (view == nullptr || !IsWindow(view)) return nullptr;
    return GetAncestor(view, GA_ROOT);
  }

  bool IsForeground(HWND top_level) override {
    return top_level != nullptr && GetForegroundWindow() == top_level &&
           !IsIconic(top_level);
  }

  bool ViewClientRect(HWND view, ScreenRect* rect) override {
    RECT client;
    if (view == nullptr || !GetClientRect(view, &client)) return false;
    // Client to screen: virtual-desktop pixels (the runner is per-monitor
    // DPI aware, so these are physical pixels on every monitor).
    POINT corners[2] = {{client.left, client.top}, {client.right, client.bottom}};
    SetLastError(0);
    if (MapWindowPoints(view, nullptr, corners, 2) == 0 && GetLastError() != 0) {
      return false;
    }
    *rect = ScreenRect{corners[0].x, corners[0].y, corners[1].x, corners[1].y};
    return true;
  }

  double ScaleOf(HWND view) override {
    const UINT dpi = view != nullptr ? GetDpiForWindow(view) : 0;
    return dpi == 0 ? 1.0 : dpi / 96.0;
  }

  ScreenRect VirtualScreen() override {
    const long left = GetSystemMetrics(SM_XVIRTUALSCREEN);
    const long top = GetSystemMetrics(SM_YVIRTUALSCREEN);
    return ScreenRect{left, top, left + GetSystemMetrics(SM_CXVIRTUALSCREEN),
                      top + GetSystemMetrics(SM_CYVIRTUALSCREEN)};
  }

  ScreenRect PrimaryMonitor() override {
    return ScreenRect{0, 0, GetSystemMetrics(SM_CXSCREEN),
                      GetSystemMetrics(SM_CYSCREEN)};
  }

  bool GetCursorPosition(ScreenPoint* point) override {
    POINT p;
    if (!GetCursorPos(&p)) return false;
    *point = ScreenPoint{p.x, p.y};
    return true;
  }

  bool SetCursorPosition(ScreenPoint point) override {
    return SetCursorPos(static_cast<int>(point.x), static_cast<int>(point.y)) != 0;
  }

  bool ClipCursorTo(const ScreenRect* rect) override {
    if (rect == nullptr) return ClipCursor(nullptr) != 0;
    const RECT clip{rect->left, rect->top, rect->right, rect->bottom};
    return ClipCursor(&clip) != 0;
  }

  int ShowCursorCounter(bool show) override { return ShowCursor(show ? TRUE : FALSE); }

  bool RegisterRawMouse(HWND target) override {
    // No RIDEV_NOLEGACY or RIDEV_CAPTUREMOUSE: Flutter keeps its legacy mouse
    // messages (clicks, the wheel). No RIDEV_INPUTSINK: reports stop when the
    // window is not in the foreground.
    RAWINPUTDEVICE device{kGenericDesktopPage, kMouseUsage, 0, target};
    return RegisterRawInputDevices(&device, 1, sizeof(device)) != 0;
  }

  bool UnregisterRawMouse() override {
    RAWINPUTDEVICE device{kGenericDesktopPage, kMouseUsage, RIDEV_REMOVE, nullptr};
    return RegisterRawInputDevices(&device, 1, sizeof(device)) != 0;
  }

  bool ReadRawMouse(LPARAM lparam, RawMouseSample* sample) override {
    RAWINPUT input;
    UINT size = sizeof(input);
    const UINT read = GetRawInputData(reinterpret_cast<HRAWINPUT>(lparam), RID_INPUT,
                                      &input, &size, sizeof(RAWINPUTHEADER));
    if (read == static_cast<UINT>(-1) || read == 0) return false;
    if (input.header.dwType != RIM_TYPEMOUSE) return false;
    sample->flags = input.data.mouse.usFlags;
    sample->last_x = input.data.mouse.lLastX;
    sample->last_y = input.data.mouse.lLastY;
    return true;
  }

  UINT FlushMessage() override {
    if (flush_message_ == 0) {
      flush_message_ = RegisterWindowMessageW(L"LuminaMouseCaptureFlushMotion");
    }
    return flush_message_;
  }

  bool PostFlush(HWND top_level) override {
    const UINT message = FlushMessage();
    return message != 0 && PostMessageW(top_level, message, 0, 0) != 0;
  }

 private:
  UINT flush_message_ = 0;
};

}  // namespace

std::unique_ptr<PointerOs> CreateWin32PointerOs() {
  return std::make_unique<Win32PointerOs>();
}

}  // namespace lumina_mouse_capture
