[Türkçe](README.tr.md)

# Lumina tools documentation

This is the reference documentation of the tools repository: the native and FFI packages that the Lumina game engine and its editor, Lumina Studio, build on. It covers model import (`flutter_assimp`), facial rig evaluation (`flutter_riglogic`), in-process video encoding (`flutter_gstreamer`), the smoke-test system (`lumina_smoke`) and pointer capture (`lumina_mouse_capture`). Setup, requirements and the native-assets hook settings are described in the repository's [README](../README.md).

## Where to start

- **Game developers** meet these packages only indirectly, through the engine. Start with the [Lumina documentation](https://github.com/LuminaGame/lumina/tree/main/docs); read [lumina_mouse_capture](en/lumina_mouse_capture.md) if your game captures the mouse.
- **Editor and plugin developers**: [flutter_assimp](en/flutter_assimp.md) is what the content browser imports models with; [flutter_riglogic](en/flutter_riglogic.md) drives MetaHuman faces in the skeletal mesh and animation editors.
- **Engine contributors**: all four pages, and the repository [README](../README.md) for building OpenRigLogic and pointing the hooks at Filament. [lumina_smoke](en/lumina_smoke.md) and [flutter_gstreamer](en/flutter_gstreamer.md) matter when you work on smoke tests and their evidence.

## Contents

- [flutter_assimp](en/flutter_assimp.md) - Assimp model import: 40+ formats to binary glTF (GLB).
- [flutter_riglogic](en/flutter_riglogic.md) - MetaHuman RigLogic: DNA files and facial rig evaluation.
- [flutter_kimodo](en/flutter_kimodo.md) - kimodo.cpp: text-to-motion generation with NVIDIA Kimodo, CPU or Vulkan.
- [flutter_gstreamer](en/flutter_gstreamer.md) - GStreamer bindings: in-process video encoding and media probing.
- [lumina_mouse_capture](en/lumina_mouse_capture.md) - Pointer capture with relative motion on Linux (Wayland and X11).
- [lumina_smoke](en/lumina_smoke.md) - The smoke-test system: artifacts, video rules, recorders and the report runner.
- [lumina_smoke API](en/lumina_smoke-api.md) - Class reference of the artifacts, video, recorder and report libraries.

## Related documentation

- [Lumina documentation](https://github.com/LuminaGame/lumina/tree/main/docs): architecture, getting started and the engine and editor API reference.
- [plugins](https://github.com/LuminaGame/plugins) and [marketplace](https://github.com/LuminaGame/marketplace).

---

[Next: flutter_assimp](en/flutter_assimp.md)
