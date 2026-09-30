#include "include/lumina_mouse_capture/lumina_mouse_capture_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "lumina_mouse_capture_plugin.h"

void LuminaMouseCapturePluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  lumina_mouse_capture::LuminaMouseCapturePlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
