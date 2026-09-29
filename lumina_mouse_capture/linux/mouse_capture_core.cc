#include "mouse_capture_core.h"

#include <strings.h>

#include <cmath>
#include <cstdlib>
#include <cstring>

#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#ifdef GDK_WINDOWING_WAYLAND
#include <gdk/gdkwayland.h>
#endif

#if defined(GDK_WINDOWING_WAYLAND) && defined(LUMINA_MC_WAYLAND_PROTOCOLS)
#define LUMINA_MC_WAYLAND 1
#include "pointer-constraints-unstable-v1-client-protocol.h"
#include "relative-pointer-unstable-v1-client-protocol.h"
#endif

namespace lumina_mouse_capture {

const char* KindName(Kind kind) {
  switch (kind) {
    case Kind::kWayland:
      return "wayland";
    case Kind::kX11:
      return "x11";
    case Kind::kDisabled:
      return "disabled";
    case Kind::kUnsupported:
      break;
  }
  return "unsupported";
}

bool DisabledByEnvironment() {
  const char* value = getenv("LUMINA_MOUSE_CAPTURE");
  if (value == nullptr) return false;
  return strcasecmp(value, "off") == 0 || strcasecmp(value, "record") == 0;
}

MouseCapture::MouseCapture(GtkWidget* widget, Callbacks callbacks)
    : widget_(widget), callbacks_(std::move(callbacks)) {}

// The two managers are deliberately not destroyed: this runs while the app
// shuts down, possibly after GDK closed the display they belong to, and
// destroying a proxy of a closed connection is a use-after-free.
MouseCapture::~MouseCapture() { Release(); }

void MouseCapture::DetachWidget() {
  Release();
  widget_ = nullptr;
}

// ([x], [y]) in widget coordinates → the toplevel window's coordinates, which
// are the toplevel wl_surface's (GTK3 draws client-side decorations and their
// shadow inside the same window).
bool MouseCapture::ToplevelPoint(bool has_centre, double x, double y, int* tx,
                                 int* ty) {
  if (widget_ == nullptr) return false;
  GtkWidget* toplevel = gtk_widget_get_toplevel(widget_);
  if (toplevel == nullptr || !gtk_widget_get_realized(toplevel)) return false;
  if (!has_centre) {
    x = gtk_widget_get_allocated_width(widget_) / 2.0;
    y = gtk_widget_get_allocated_height(widget_) / 2.0;
  }
  return gtk_widget_translate_coordinates(widget_, toplevel,
                                          static_cast<gint>(std::lround(x)),
                                          static_cast<gint>(std::lround(y)),
                                          tx, ty);
}

Support MouseCapture::GetSupport() {
  Support support;
  if (DisabledByEnvironment()) {
    support.kind = Kind::kDisabled;
    support.detail = "LUMINA_MOUSE_CAPTURE is off: nothing captures the pointer";
    return support;
  }
  if (widget_ == nullptr) {
    support.detail = "no Flutter view";
    return support;
  }
  GdkDisplay* display = gtk_widget_get_display(widget_);
#ifdef GDK_WINDOWING_WAYLAND
  if (GDK_IS_WAYLAND_DISPLAY(display)) {
#ifdef LUMINA_MC_WAYLAND
    if (EnsureWaylandGlobals()) {
      support.kind = Kind::kWayland;
      support.pointer_lock = true;
      support.relative_motion = true;
      support.detail =
          "zwp_pointer_constraints_v1 + zwp_relative_pointer_manager_v1";
    } else {
      support.detail = std::string("the compositor lacks ") +
                       (constraints_ == nullptr
                            ? "zwp_pointer_constraints_v1"
                            : "zwp_relative_pointer_manager_v1");
    }
#else
    support.detail = "built without wayland-scanner / wayland-protocols";
#endif
    return support;
  }
#endif
#ifdef GDK_WINDOWING_X11
  if (GDK_IS_X11_DISPLAY(display)) {
    support.kind = Kind::kX11;
    support.pointer_lock = true;
    support.relative_motion = true;
    support.detail = "X11 seat grab + warp to centre";
    return support;
  }
#endif
  support.detail = "neither a Wayland nor an X11 display";
  return support;
}

bool MouseCapture::Capture(bool has_centre, double x, double y) {
  if (DisabledByEnvironment() || widget_ == nullptr) return false;
  GdkDisplay* display = gtk_widget_get_display(widget_);
#ifdef LUMINA_MC_WAYLAND
  if (GDK_IS_WAYLAND_DISPLAY(display)) return CaptureWayland(has_centre, x, y);
#endif
#ifdef GDK_WINDOWING_X11
  if (GDK_IS_X11_DISPLAY(display)) return CaptureX11(has_centre, x, y);
#endif
  (void)display;
  return false;
}

void MouseCapture::Release() {
#ifdef LUMINA_MC_WAYLAND
  DestroyWaylandObjects();
#endif
  ReleaseX11();
  captured_ = false;
}

void MouseCapture::ReportLost() {
  if (callbacks_.lost) callbacks_.lost();
}

// --- Wayland -----------------------------------------------------------------

#ifdef LUMINA_MC_WAYLAND

static const struct wl_registry_listener kRegistryListener = {
    MouseCapture::OnRegistryGlobal,
    MouseCapture::OnRegistryGlobalRemove,
};

static const struct zwp_locked_pointer_v1_listener kLockedListener = {
    MouseCapture::OnLockedEvent,
    MouseCapture::OnUnlockedEvent,
};

static const struct zwp_relative_pointer_v1_listener kRelativeListener = {
    MouseCapture::OnRelativeMotionEvent,
};

void MouseCapture::OnRegistryGlobal(void* data, struct wl_registry* registry,
                                    uint32_t name, const char* interface,
                                    uint32_t version) {
  auto* self = static_cast<MouseCapture*>(data);
  if (strcmp(interface, zwp_pointer_constraints_v1_interface.name) == 0 &&
      self->constraints_ == nullptr) {
    self->constraints_ = static_cast<zwp_pointer_constraints_v1*>(
        wl_registry_bind(registry, name, &zwp_pointer_constraints_v1_interface,
                         1));
  } else if (strcmp(interface,
                    zwp_relative_pointer_manager_v1_interface.name) == 0 &&
             self->relative_manager_ == nullptr) {
    self->relative_manager_ = static_cast<zwp_relative_pointer_manager_v1*>(
        wl_registry_bind(registry, name,
                         &zwp_relative_pointer_manager_v1_interface, 1));
  }
}

void MouseCapture::OnRegistryGlobalRemove(void*, struct wl_registry*,
                                          uint32_t) {}

// Binds the two managers on GDK's own connection. The registry lives on a
// private queue, so GDK's dispatch never sees its events; the managers are
// then moved to the default queue, which GDK dispatches on the main thread,
// and everything created from them (lock, relative pointer) inherits it.
bool MouseCapture::EnsureWaylandGlobals() {
  if (wayland_probed_) {
    return constraints_ != nullptr && relative_manager_ != nullptr;
  }
  wayland_probed_ = true;
  GdkDisplay* display = gtk_widget_get_display(widget_);
  wl_display_ = gdk_wayland_display_get_wl_display(display);
  if (wl_display_ == nullptr) return false;

  struct wl_event_queue* queue = wl_display_create_queue(wl_display_);
  auto* wrapper = static_cast<struct wl_display*>(
      wl_proxy_create_wrapper(wl_display_));
  wl_proxy_set_queue(reinterpret_cast<struct wl_proxy*>(wrapper), queue);
  struct wl_registry* registry = wl_display_get_registry(wrapper);
  wl_registry_add_listener(registry, &kRegistryListener, this);
  wl_display_roundtrip_queue(wl_display_, queue);
  wl_registry_destroy(registry);
  wl_proxy_wrapper_destroy(wrapper);

  if (constraints_ != nullptr) {
    wl_proxy_set_queue(reinterpret_cast<struct wl_proxy*>(constraints_),
                       nullptr);
  }
  if (relative_manager_ != nullptr) {
    wl_proxy_set_queue(reinterpret_cast<struct wl_proxy*>(relative_manager_),
                       nullptr);
  }
  wl_event_queue_destroy(queue);
  g_message("lumina_mouse_capture: wayland globals: pointer constraints %s, "
            "relative pointer %s",
            constraints_ != nullptr ? "yes" : "no",
            relative_manager_ != nullptr ? "yes" : "no");
  return constraints_ != nullptr && relative_manager_ != nullptr;
}

bool MouseCapture::CaptureWayland(bool has_centre, double x, double y) {
  if (!EnsureWaylandGlobals()) return false;
  GtkWidget* toplevel = gtk_widget_get_toplevel(widget_);
  GdkWindow* window = gtk_widget_get_window(toplevel);
  if (window == nullptr) return false;
  struct wl_surface* surface = gdk_wayland_window_get_wl_surface(window);
  GdkSeat* seat = gdk_display_get_default_seat(gtk_widget_get_display(widget_));
  GdkDevice* pointer_device = seat != nullptr ? gdk_seat_get_pointer(seat)
                                              : nullptr;
  struct wl_pointer* pointer =
      pointer_device != nullptr
          ? gdk_wayland_device_get_wl_pointer(pointer_device)
          : nullptr;
  if (surface == nullptr || pointer == nullptr) {
    g_warning("lumina_mouse_capture: no wl_surface or wl_pointer to lock");
    return false;
  }

  // Never two constraints on one surface: that is a protocol error, and a
  // protocol error ends GDK's connection and the app with it.
  DestroyWaylandObjects();

  locked_pointer_ = zwp_pointer_constraints_v1_lock_pointer(
      constraints_, surface, pointer, nullptr,
      ZWP_POINTER_CONSTRAINTS_V1_LIFETIME_ONESHOT);
  zwp_locked_pointer_v1_add_listener(locked_pointer_, &kLockedListener, this);
  int hx = 0;
  int hy = 0;
  if (ToplevelPoint(has_centre, x, y, &hx, &hy)) {
    // Where the pointer reappears on release (applied on the surface's next
    // commit, which the next frame makes).
    zwp_locked_pointer_v1_set_cursor_position_hint(
        locked_pointer_, wl_fixed_from_int(hx), wl_fixed_from_int(hy));
    gtk_widget_queue_draw(toplevel);
  }
  relative_pointer_ = zwp_relative_pointer_manager_v1_get_relative_pointer(
      relative_manager_, pointer);
  zwp_relative_pointer_v1_add_listener(relative_pointer_, &kRelativeListener,
                                       this);
  wl_display_flush(wl_display_);
  captured_ = true;
  g_message("lumina_mouse_capture: wayland lock requested (hint %d,%d)", hx,
            hy);
  return true;
}

void MouseCapture::DestroyWaylandObjects() {
  bool any = false;
  if (relative_pointer_ != nullptr) {
    zwp_relative_pointer_v1_destroy(relative_pointer_);
    relative_pointer_ = nullptr;
    any = true;
  }
  if (locked_pointer_ != nullptr) {
    zwp_locked_pointer_v1_destroy(locked_pointer_);
    locked_pointer_ = nullptr;
    any = true;
  }
  if (flush_source_ != 0) {
    g_source_remove(flush_source_);
    flush_source_ = 0;
  }
  pending_dx_ = 0;
  pending_dy_ = 0;
  if (any && wl_display_ != nullptr) {
    wl_display_flush(wl_display_);
    g_message("lumina_mouse_capture: wayland lock released");
  }
}

void MouseCapture::OnLockedEvent(void* data, struct zwp_locked_pointer_v1*) {
  static_cast<MouseCapture*>(data)->OnWaylandLocked();
}

void MouseCapture::OnUnlockedEvent(void* data, struct zwp_locked_pointer_v1*) {
  static_cast<MouseCapture*>(data)->OnWaylandUnlocked();
}

void MouseCapture::OnWaylandLocked() {
  g_message("lumina_mouse_capture: wayland pointer locked");
  if (callbacks_.locked) callbacks_.locked();
}

// A one-shot lock that the compositor deactivated (focus loss) is defunct:
// destroy it now so the next capture can lock again, and report the loss.
void MouseCapture::OnWaylandUnlocked() {
  g_message("lumina_mouse_capture: wayland pointer unlocked by the compositor");
  DestroyWaylandObjects();
  if (!captured_) return;
  captured_ = false;
  ReportLost();
}

void MouseCapture::OnRelativeMotionEvent(void* data,
                                         struct zwp_relative_pointer_v1*,
                                         uint32_t, uint32_t, wl_fixed_t dx,
                                         wl_fixed_t dy, wl_fixed_t,
                                         wl_fixed_t) {
  static_cast<MouseCapture*>(data)->OnRelativeMotion(wl_fixed_to_double(dx),
                                                     wl_fixed_to_double(dy));
}

// Relative events can come at the mouse's report rate (1 kHz); they are
// summed and sent once per main-loop turn.
void MouseCapture::OnRelativeMotion(double dx, double dy) {
  if (!captured_) return;
  pending_dx_ += dx;
  pending_dy_ += dy;
  if (flush_source_ == 0) {
    flush_source_ =
        g_idle_add_full(G_PRIORITY_DEFAULT, FlushMotion, this, nullptr);
  }
}

gboolean MouseCapture::FlushMotion(gpointer data) {
  auto* self = static_cast<MouseCapture*>(data);
  self->flush_source_ = 0;
  const double dx = self->pending_dx_;
  const double dy = self->pending_dy_;
  self->pending_dx_ = 0;
  self->pending_dy_ = 0;
  if ((dx != 0 || dy != 0) && self->captured_ && self->callbacks_.motion) {
    self->callbacks_.motion(dx, dy);
  }
  return G_SOURCE_REMOVE;
}

#else  // !LUMINA_MC_WAYLAND

void MouseCapture::OnRegistryGlobal(void*, struct wl_registry*, uint32_t,
                                    const char*, uint32_t) {}
void MouseCapture::OnRegistryGlobalRemove(void*, struct wl_registry*,
                                          uint32_t) {}
bool MouseCapture::EnsureWaylandGlobals() { return false; }
bool MouseCapture::CaptureWayland(bool, double, double) { return false; }
void MouseCapture::DestroyWaylandObjects() {}
void MouseCapture::OnLockedEvent(void*, struct zwp_locked_pointer_v1*) {}
void MouseCapture::OnUnlockedEvent(void*, struct zwp_locked_pointer_v1*) {}
void MouseCapture::OnWaylandLocked() {}
void MouseCapture::OnWaylandUnlocked() {}
void MouseCapture::OnRelativeMotionEvent(void*, struct zwp_relative_pointer_v1*,
                                         uint32_t, uint32_t, int32_t, int32_t,
                                         int32_t, int32_t) {}
void MouseCapture::OnRelativeMotion(double, double) {}
gboolean MouseCapture::FlushMotion(gpointer) { return G_SOURCE_REMOVE; }

#endif  // LUMINA_MC_WAYLAND

// --- X11 ---------------------------------------------------------------------

// A seat grab keeps the pointer's events on the window; the pointer is warped
// to the centre, and a 4 ms poll reads how far it moved and warps it back.
bool MouseCapture::CaptureX11(bool has_centre, double x, double y) {
#ifdef GDK_WINDOWING_X11
  ReleaseX11();
  GtkWidget* toplevel = gtk_widget_get_toplevel(widget_);
  GdkWindow* window = gtk_widget_get_window(toplevel);
  int tx = 0;
  int ty = 0;
  if (window == nullptr || !ToplevelPoint(has_centre, x, y, &tx, &ty)) {
    return false;
  }
  int ox = 0;
  int oy = 0;
  gdk_window_get_origin(window, &ox, &oy);
  root_cx_ = ox + tx;
  root_cy_ = oy + ty;

  GdkDisplay* display = gtk_widget_get_display(widget_);
  GdkSeat* seat = gdk_display_get_default_seat(display);
  // A blank cursor for the grab: hidden whatever the app shows, and Xwayland
  // only honours warps (by locking the Wayland pointer) while the cursor is
  // hidden.
  GdkCursor* blank = gdk_cursor_new_for_display(display, GDK_BLANK_CURSOR);
  GdkGrabStatus status =
      gdk_seat_grab(seat, window, GDK_SEAT_CAPABILITY_ALL_POINTING, TRUE,
                    blank, nullptr, nullptr, nullptr);
  g_object_unref(blank);
  x11_grabbed_ = status == GDK_GRAB_SUCCESS;
  GdkDevice* pointer = gdk_seat_get_pointer(seat);
  gdk_device_warp(pointer, gdk_window_get_screen(window), root_cx_, root_cy_);
  last_x_ = root_cx_;
  last_y_ = root_cy_;
  warp_pending_ = true;
  pre_warp_x_ = -1;
  pre_warp_y_ = -1;
  poll_source_ = g_timeout_add(4, PollX11, this);
  focus_widget_ = toplevel;
  focus_handler_ = g_signal_connect(toplevel, "focus-out-event",
                                    G_CALLBACK(OnFocusOut), this);
  captured_ = true;
  g_message("lumina_mouse_capture: x11 capture (grab %s) at %d,%d",
            x11_grabbed_ ? "ok" : "refused", root_cx_, root_cy_);
  if (callbacks_.locked) callbacks_.locked();
  return true;
#else
  (void)has_centre;
  (void)x;
  (void)y;
  return false;
#endif
}

void MouseCapture::ReleaseX11() {
  if (poll_source_ != 0) {
    g_source_remove(poll_source_);
    poll_source_ = 0;
  }
  if (focus_handler_ != 0 && focus_widget_ != nullptr) {
    g_signal_handler_disconnect(focus_widget_, focus_handler_);
  }
  focus_handler_ = 0;
  focus_widget_ = nullptr;
  if (x11_grabbed_ && widget_ != nullptr) {
    gdk_seat_ungrab(
        gdk_display_get_default_seat(gtk_widget_get_display(widget_)));
    g_message("lumina_mouse_capture: x11 capture released");
  }
  x11_grabbed_ = false;
}

gboolean MouseCapture::PollX11(gpointer data) {
  auto* self = static_cast<MouseCapture*>(data);
  if (self->widget_ == nullptr) return G_SOURCE_CONTINUE;
  GdkSeat* seat =
      gdk_display_get_default_seat(gtk_widget_get_display(self->widget_));
  GdkDevice* pointer = gdk_seat_get_pointer(seat);
  GdkScreen* screen = nullptr;
  int x = 0;
  int y = 0;
  gdk_device_get_position(pointer, &screen, &x, &y);
  // Deltas are measured from the last position seen, and a warp is only
  // assumed done once the pointer left the spot it was warped from: a warp
  // the server has not applied yet must not count the same offset twice.
  if (self->warp_pending_) {
    self->warp_pending_ = false;
    if (x != self->pre_warp_x_ || y != self->pre_warp_y_) {
      self->last_x_ = self->root_cx_;
      self->last_y_ = self->root_cy_;
    }
  }
  const int dx = x - self->last_x_;
  const int dy = y - self->last_y_;
  self->last_x_ = x;
  self->last_y_ = y;
  if ((dx != 0 || dy != 0) && self->callbacks_.motion) {
    self->callbacks_.motion(dx, dy);
  }
  if (x != self->root_cx_ || y != self->root_cy_) {
    self->pre_warp_x_ = x;
    self->pre_warp_y_ = y;
    self->warp_pending_ = true;
    gdk_device_warp(pointer, screen, self->root_cx_, self->root_cy_);
  }
  return G_SOURCE_CONTINUE;
}

gboolean MouseCapture::OnFocusOut(GtkWidget*, GdkEvent*, gpointer data) {
  auto* self = static_cast<MouseCapture*>(data);
  if (self->captured_) {
    self->ReleaseX11();
    self->captured_ = false;
    self->ReportLost();
  }
  return FALSE;
}

}  // namespace lumina_mouse_capture
