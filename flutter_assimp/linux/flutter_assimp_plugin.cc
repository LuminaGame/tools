#include "include/flutter_assimp/flutter_assimp_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

#define FLUTTER_ASSIMP_PLUGIN(obj) \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), flutter_assimp_plugin_get_type(), \
                              FlutterAssimpPlugin))

struct _FlutterAssimpPlugin {
  GObject parent_instance;
};

G_DEFINE_TYPE(FlutterAssimpPlugin, flutter_assimp_plugin, G_TYPE_OBJECT)

static void flutter_assimp_plugin_dispose(GObject* object) {
  G_OBJECT_CLASS(flutter_assimp_plugin_parent_class)->dispose(object);
}

static void flutter_assimp_plugin_class_init(FlutterAssimpPluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = flutter_assimp_plugin_dispose;
}

static void flutter_assimp_plugin_init(FlutterAssimpPlugin* self) {}

void flutter_assimp_plugin_register_with_registrar(FlPluginRegistrar* registrar) {
  FlutterAssimpPlugin* plugin = FLUTTER_ASSIMP_PLUGIN(
      g_object_new(flutter_assimp_plugin_get_type(), nullptr));
  g_object_unref(plugin);
}
