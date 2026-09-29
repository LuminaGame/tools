// Pointer capture for a GTK window: a Wayland pointer
// lock with relative motion, or an X11 grab with warp-to-centre.
//
// No Flutter types here, so a plain GTK program can drive it; the plugin glue
// (lumina_mouse_capture_plugin.cc) only forwards channel calls and events.
#ifndef LUMINA_MOUSE_CAPTURE_CORE_H_
#define LUMINA_MOUSE_CAPTURE_CORE_H_

#include <gtk/gtk.h>

#include <cstdint>
#include <functional>
#include <string>

// Global-scope forward declarations: an elaborated `struct X*` first seen
// inside the namespace below would declare a different, namespaced type.
struct wl_display;
struct wl_registry;
struct zwp_pointer_constraints_v1;
struct zwp_relative_pointer_manager_v1;
struct zwp_locked_pointer_v1;
struct zwp_relative_pointer_v1;

namespace lumina_mouse_capture {

enum class Kind { kWayland, kX11, kUnsupported, kDisabled };

// The Dart-side name of [kind] (`MouseCaptureBackendKind`).
const char* KindName(Kind kind);

struct Support {
  Kind kind = Kind::kUnsupported;
  // A capture really holds the pointer.
  bool pointer_lock = false;
  // Motion callbacks carry the mouse's movement.
  bool relative_motion = false;
  std::string detail;
};

struct Callbacks {
  // The mouse moved by (dx, dy) logical pixels while captured.
  std::function<void(double dx, double dy)> motion;
  // The platform confirmed the capture.
  std::function<void()> locked;
  // The capture ended without Release(): focus loss, the compositor.
  std::function<void()> lost;
};

// True when LUMINA_MOUSE_CAPTURE is `off` or `record`: nothing may capture
// the pointer (tests, smokes and the harnesses that start the editor).
bool DisabledByEnvironment();

class MouseCapture {
 public:
  // [widget] is the widget whose coordinates Capture() takes (the Flutter
  // view); its toplevel window is what holds the pointer.
  MouseCapture(GtkWidget* widget, Callbacks callbacks);
  ~MouseCapture();

  MouseCapture(const MouseCapture&) = delete;
  MouseCapture& operator=(const MouseCapture&) = delete;

  Support GetSupport();

  // Captures the pointer. With [has_centre], ([x], [y]) is in [widget]'s
  // logical coordinates: X11 warps the pointer there, Wayland shows it there
  // again on release. Without, the widget's centre. Returns whether a capture
  // was put in place (Wayland: requested; it activates when the pointer is on
  // the window).
  bool Capture(bool has_centre, double x, double y);

  // Releases the pointer; a no-op when not captured. Never reports lost.
  void Release();

  bool captured() const { return captured_; }

  // The widget is going away: release without touching it again.
  void DetachWidget();

  // Wayland listener entry points (C callbacks; not for other callers).
  static void OnLockedEvent(void* data, struct zwp_locked_pointer_v1* locked);
  static void OnUnlockedEvent(void* data, struct zwp_locked_pointer_v1* locked);
  static void OnRelativeMotionEvent(void* data,
                                    struct zwp_relative_pointer_v1* pointer,
                                    uint32_t utime_hi,
                                    uint32_t utime_lo,
                                    int32_t dx,
                                    int32_t dy,
                                    int32_t dx_unaccel,
                                    int32_t dy_unaccel);
  static void OnRegistryGlobal(void* data,
                               struct wl_registry* registry,
                               uint32_t name,
                               const char* interface,
                               uint32_t version);
  static void OnRegistryGlobalRemove(void* data,
                                     struct wl_registry* registry,
                                     uint32_t name);

 private:
  bool ToplevelPoint(bool has_centre, double x, double y, int* tx, int* ty);

  // Wayland.
  bool EnsureWaylandGlobals();
  bool CaptureWayland(bool has_centre, double x, double y);
  void DestroyWaylandObjects();
  void OnWaylandLocked();
  void OnWaylandUnlocked();
  void OnRelativeMotion(double dx, double dy);
  static gboolean FlushMotion(gpointer data);
  // X11.
  bool CaptureX11(bool has_centre, double x, double y);
  void ReleaseX11();
  static gboolean PollX11(gpointer data);
  static gboolean OnFocusOut(GtkWidget* widget,
                             GdkEvent* event,
                             gpointer data);

  void ReportLost();

  GtkWidget* widget_;
  Callbacks callbacks_;
  bool captured_ = false;

  // Wayland state.
  bool wayland_probed_ = false;
  struct wl_display* wl_display_ = nullptr;
  struct zwp_pointer_constraints_v1* constraints_ = nullptr;
  struct zwp_relative_pointer_manager_v1* relative_manager_ = nullptr;
  struct zwp_locked_pointer_v1* locked_pointer_ = nullptr;
  struct zwp_relative_pointer_v1* relative_pointer_ = nullptr;
  double pending_dx_ = 0;
  double pending_dy_ = 0;
  guint flush_source_ = 0;

  // X11 state.
  bool x11_grabbed_ = false;
  guint poll_source_ = 0;
  gulong focus_handler_ = 0;
  GtkWidget* focus_widget_ = nullptr;
  int root_cx_ = 0;
  int root_cy_ = 0;
  int last_x_ = 0;
  int last_y_ = 0;
  bool warp_pending_ = false;
  int pre_warp_x_ = -1;
  int pre_warp_y_ = -1;
};

}  // namespace lumina_mouse_capture

#endif  // LUMINA_MOUSE_CAPTURE_CORE_H_
