// A plain GTK window driving the mouse-capture core (linux/mouse_capture_core)
// without Flutter, for checking it against a real compositor: run it inside
// the nested headless GNOME Shell of nested_session.py, never on a desktop
// someone is using.
//
// Keys: c = capture at the window centre, r = release, q = quit. A click while
// released captures. Every event is one JSON line on stdout:
//   {"ev":"support","kind":"wayland","lock":true,"relative":true}
//   {"ev":"capture","ok":true}  {"ev":"locked"}  {"ev":"lost"}
//   {"ev":"motion","dx":..,"dy":..,"sum_dx":..,"sum_dy":..}
//   {"ev":"pointer","x":..,"y":..}      (GDK motion on the window)
//   {"ev":"release"}  {"ev":"key","key":"c"}  {"ev":"focus","in":true}
#include <gtk/gtk.h>

#include <cstdio>

#include "../../linux/mouse_capture_core.h"

using lumina_mouse_capture::MouseCapture;

namespace {

MouseCapture* g_capture = nullptr;
double g_sum_dx = 0;
double g_sum_dy = 0;

void Emit(const char* json) {
  printf("%s\n", json);
  fflush(stdout);
}

void Capture() {
  const bool ok = g_capture->Capture(false, 0, 0);
  char line[64];
  snprintf(line, sizeof(line), "{\"ev\":\"capture\",\"ok\":%s}",
           ok ? "true" : "false");
  Emit(line);
}

gboolean OnKey(GtkWidget*, GdkEventKey* event, gpointer) {
  char line[64];
  snprintf(line, sizeof(line), "{\"ev\":\"key\",\"key\":\"%s\"}",
           gdk_keyval_name(event->keyval));
  Emit(line);
  switch (event->keyval) {
    case GDK_KEY_c:
      Capture();
      break;
    case GDK_KEY_r:
      g_capture->Release();
      Emit("{\"ev\":\"release\"}");
      break;
    case GDK_KEY_q:
      gtk_main_quit();
      break;
    default:
      break;
  }
  return TRUE;
}

gboolean OnButton(GtkWidget*, GdkEventButton*, gpointer) {
  Emit("{\"ev\":\"button\"}");
  if (!g_capture->captured()) Capture();
  return TRUE;
}

gboolean OnMotion(GtkWidget*, GdkEventMotion* event, gpointer) {
  char line[96];
  snprintf(line, sizeof(line), "{\"ev\":\"pointer\",\"x\":%.1f,\"y\":%.1f}",
           event->x, event->y);
  Emit(line);
  return FALSE;
}

gboolean OnFocus(GtkWidget*, GdkEventFocus* event, gpointer) {
  Emit(event->in ? "{\"ev\":\"focus\",\"in\":true}"
                 : "{\"ev\":\"focus\",\"in\":false}");
  return FALSE;
}

gboolean ReportSupport(gpointer) {
  const auto support = g_capture->GetSupport();
  char line[256];
  snprintf(line, sizeof(line),
           "{\"ev\":\"support\",\"kind\":\"%s\",\"lock\":%s,\"relative\":%s}",
           lumina_mouse_capture::KindName(support.kind),
           support.pointer_lock ? "true" : "false",
           support.relative_motion ? "true" : "false");
  Emit(line);
  return G_SOURCE_REMOVE;
}

}  // namespace

int main(int argc, char** argv) {
  gtk_init(&argc, &argv);
  const bool decoy = argc > 1 && g_strcmp0(argv[1], "--decoy") == 0;

  GtkWidget* window = gtk_window_new(GTK_WINDOW_TOPLEVEL);
  gtk_window_set_title(GTK_WINDOW(window), decoy ? "decoy" : "capture_probe");
  gtk_window_set_default_size(GTK_WINDOW(window), decoy ? 400 : 1000,
                              decoy ? 300 : 700);
  g_signal_connect(window, "destroy", G_CALLBACK(gtk_main_quit), nullptr);
  GtkWidget* area = gtk_drawing_area_new();
  gtk_container_add(GTK_CONTAINER(window), area);
  if (decoy) {
    gtk_widget_show_all(window);
    gtk_main();
    return 0;
  }

  gtk_widget_add_events(area, GDK_POINTER_MOTION_MASK | GDK_BUTTON_PRESS_MASK);
  g_signal_connect(area, "motion-notify-event", G_CALLBACK(OnMotion), nullptr);
  g_signal_connect(area, "button-press-event", G_CALLBACK(OnButton), nullptr);
  g_signal_connect(window, "key-press-event", G_CALLBACK(OnKey), nullptr);
  g_signal_connect(window, "focus-in-event", G_CALLBACK(OnFocus), nullptr);
  g_signal_connect(window, "focus-out-event", G_CALLBACK(OnFocus), nullptr);

  lumina_mouse_capture::Callbacks callbacks;
  callbacks.motion = [](double dx, double dy) {
    g_sum_dx += dx;
    g_sum_dy += dy;
    char line[160];
    snprintf(line, sizeof(line),
             "{\"ev\":\"motion\",\"dx\":%.2f,\"dy\":%.2f,\"sum_dx\":%.2f,"
             "\"sum_dy\":%.2f}",
             dx, dy, g_sum_dx, g_sum_dy);
    Emit(line);
  };
  callbacks.locked = []() { Emit("{\"ev\":\"locked\"}"); };
  callbacks.lost = []() { Emit("{\"ev\":\"lost\"}"); };
  MouseCapture capture(area, callbacks);
  g_capture = &capture;

  gtk_widget_show_all(window);
  g_timeout_add(300, ReportSupport, nullptr);
  gtk_main();
  g_capture = nullptr;
  return 0;
}
