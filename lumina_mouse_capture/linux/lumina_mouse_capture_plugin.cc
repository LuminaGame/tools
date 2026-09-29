// Channel glue for the mouse-capture core.
//
// Method channel `lumina_mouse_capture`: `support`, `capture` ({x, y} in the
// Flutter view's logical coordinates, optional), `release`.
// Event channel `lumina_mouse_capture/events`: {type: motion, dx, dy},
// {type: locked}, {type: lost}.
#include "include/lumina_mouse_capture/lumina_mouse_capture_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

#include <cstring>

#include "mouse_capture_core.h"

#define LUMINA_MOUSE_CAPTURE_PLUGIN(obj)                                  \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), lumina_mouse_capture_plugin_get_type(), \
                              LuminaMouseCapturePlugin))

struct _LuminaMouseCapturePlugin {
  GObject parent_instance;
  FlMethodChannel* channel;
  FlEventChannel* events;
  gboolean listening;
  GtkWidget* view;
  lumina_mouse_capture::MouseCapture* capture;
};

G_DEFINE_TYPE(LuminaMouseCapturePlugin, lumina_mouse_capture_plugin,
              g_object_get_type())

static void send_event(LuminaMouseCapturePlugin* self, FlValue* event) {
  if (self->listening && self->events != nullptr) {
    fl_event_channel_send(self->events, event, nullptr, nullptr);
  }
  fl_value_unref(event);
}

static FlValue* typed_event(const char* type) {
  FlValue* event = fl_value_new_map();
  fl_value_set_string_take(event, "type", fl_value_new_string(type));
  return event;
}

// The view is being destroyed: release, and never touch it again.
static void view_destroyed(gpointer data, GObject*) {
  auto* self = static_cast<LuminaMouseCapturePlugin*>(data);
  self->view = nullptr;
  if (self->capture != nullptr) self->capture->DetachWidget();
}

static lumina_mouse_capture::MouseCapture* ensure_capture(
    LuminaMouseCapturePlugin* self) {
  if (self->capture != nullptr || self->view == nullptr) return self->capture;
  lumina_mouse_capture::Callbacks callbacks;
  callbacks.motion = [self](double dx, double dy) {
    FlValue* event = typed_event("motion");
    fl_value_set_string_take(event, "dx", fl_value_new_float(dx));
    fl_value_set_string_take(event, "dy", fl_value_new_float(dy));
    send_event(self, event);
  };
  callbacks.locked = [self]() { send_event(self, typed_event("locked")); };
  callbacks.lost = [self]() { send_event(self, typed_event("lost")); };
  self->capture = new lumina_mouse_capture::MouseCapture(self->view,
                                                         std::move(callbacks));
  return self->capture;
}

static FlMethodResponse* support_response(LuminaMouseCapturePlugin* self) {
  lumina_mouse_capture::Support support;
  if (lumina_mouse_capture::DisabledByEnvironment()) {
    support.kind = lumina_mouse_capture::Kind::kDisabled;
    support.detail = "LUMINA_MOUSE_CAPTURE is off: nothing captures the pointer";
  } else if (auto* capture = ensure_capture(self)) {
    support = capture->GetSupport();
  } else {
    support.detail = "no Flutter view";
  }
  g_autoptr(FlValue) result = fl_value_new_map();
  fl_value_set_string_take(
      result, "kind",
      fl_value_new_string(lumina_mouse_capture::KindName(support.kind)));
  fl_value_set_string_take(result, "pointerLock",
                           fl_value_new_bool(support.pointer_lock));
  fl_value_set_string_take(result, "relativeMotion",
                           fl_value_new_bool(support.relative_motion));
  fl_value_set_string_take(result, "detail",
                           fl_value_new_string(support.detail.c_str()));
  return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
}

static bool read_double(FlValue* map, const char* key, double* out) {
  FlValue* value = fl_value_lookup_string(map, key);
  if (value == nullptr) return false;
  switch (fl_value_get_type(value)) {
    case FL_VALUE_TYPE_FLOAT:
      *out = fl_value_get_float(value);
      return true;
    case FL_VALUE_TYPE_INT:
      *out = static_cast<double>(fl_value_get_int(value));
      return true;
    default:
      return false;
  }
}

static FlMethodResponse* capture_response(LuminaMouseCapturePlugin* self,
                                          FlValue* args) {
  bool ok = false;
  auto* capture = lumina_mouse_capture::DisabledByEnvironment()
                      ? nullptr
                      : ensure_capture(self);
  if (capture != nullptr) {
    double x = 0;
    double y = 0;
    const bool has_centre =
        args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_MAP &&
        read_double(args, "x", &x) && read_double(args, "y", &y);
    ok = capture->Capture(has_centre, x, y);
  }
  g_autoptr(FlValue) result = fl_value_new_bool(ok);
  return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
}

static void method_call_cb(FlMethodChannel*, FlMethodCall* method_call,
                           gpointer user_data) {
  auto* self = LUMINA_MOUSE_CAPTURE_PLUGIN(user_data);
  const gchar* method = fl_method_call_get_name(method_call);
  g_autoptr(FlMethodResponse) response = nullptr;
  if (strcmp(method, "support") == 0) {
    response = support_response(self);
  } else if (strcmp(method, "capture") == 0) {
    response = capture_response(self, fl_method_call_get_args(method_call));
  } else if (strcmp(method, "release") == 0) {
    if (self->capture != nullptr) self->capture->Release();
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }
  fl_method_call_respond(method_call, response, nullptr);
}

static FlMethodErrorResponse* listen_cb(FlEventChannel*, FlValue*,
                                        gpointer user_data) {
  LUMINA_MOUSE_CAPTURE_PLUGIN(user_data)->listening = TRUE;
  return nullptr;
}

static FlMethodErrorResponse* cancel_cb(FlEventChannel*, FlValue*,
                                        gpointer user_data) {
  LUMINA_MOUSE_CAPTURE_PLUGIN(user_data)->listening = FALSE;
  return nullptr;
}

static void lumina_mouse_capture_plugin_dispose(GObject* object) {
  auto* self = LUMINA_MOUSE_CAPTURE_PLUGIN(object);
  if (self->view != nullptr) {
    g_object_weak_unref(G_OBJECT(self->view), view_destroyed, self);
    self->view = nullptr;
  }
  delete self->capture;
  self->capture = nullptr;
  g_clear_object(&self->channel);
  g_clear_object(&self->events);
  G_OBJECT_CLASS(lumina_mouse_capture_plugin_parent_class)->dispose(object);
}

static void lumina_mouse_capture_plugin_class_init(
    LuminaMouseCapturePluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = lumina_mouse_capture_plugin_dispose;
}

static void lumina_mouse_capture_plugin_init(LuminaMouseCapturePlugin* self) {
  self->channel = nullptr;
  self->events = nullptr;
  self->listening = FALSE;
  self->view = nullptr;
  self->capture = nullptr;
}

void lumina_mouse_capture_plugin_register_with_registrar(
    FlPluginRegistrar* registrar) {
  LuminaMouseCapturePlugin* plugin = LUMINA_MOUSE_CAPTURE_PLUGIN(
      g_object_new(lumina_mouse_capture_plugin_get_type(), nullptr));

  FlView* view = fl_plugin_registrar_get_view(registrar);
  if (view != nullptr) {
    plugin->view = GTK_WIDGET(view);
    g_object_weak_ref(G_OBJECT(view), view_destroyed, plugin);
  }

  FlBinaryMessenger* messenger = fl_plugin_registrar_get_messenger(registrar);
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  plugin->channel = fl_method_channel_new(messenger, "lumina_mouse_capture",
                                          FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      plugin->channel, method_call_cb, g_object_ref(plugin), g_object_unref);
  plugin->events = fl_event_channel_new(
      messenger, "lumina_mouse_capture/events", FL_METHOD_CODEC(codec));
  fl_event_channel_set_stream_handlers(plugin->events, listen_cb, cancel_cb,
                                       g_object_ref(plugin), g_object_unref);

  g_object_unref(plugin);
}
