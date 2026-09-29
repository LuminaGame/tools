#include "include/flutter_riglogic/flutter_riglogic_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

#define FLUTTER_RIGLOGIC_PLUGIN(obj) \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), flutter_riglogic_plugin_get_type(), \
                              FlutterRiglogicPlugin))

struct _FlutterRiglogicPlugin {
  GObject parent_instance;
};

G_DEFINE_TYPE(FlutterRiglogicPlugin, flutter_riglogic_plugin, G_TYPE_OBJECT)

static void flutter_riglogic_plugin_dispose(GObject* object) {
  G_OBJECT_CLASS(flutter_riglogic_plugin_parent_class)->dispose(object);
}

static void flutter_riglogic_plugin_class_init(FlutterRiglogicPluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = flutter_riglogic_plugin_dispose;
}

static void flutter_riglogic_plugin_init(FlutterRiglogicPlugin* self) {}

void flutter_riglogic_plugin_register_with_registrar(FlPluginRegistrar* registrar) {
  FlutterRiglogicPlugin* plugin = FLUTTER_RIGLOGIC_PLUGIN(
      g_object_new(flutter_riglogic_plugin_get_type(), nullptr));
  g_object_unref(plugin);
}
