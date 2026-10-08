# Changelog

## 0.0.1

- Initial release: Dart FFI bindings to Assimp that convert FBX, OBJ,
  Collada, 3DS, PLY, DirectX and STL models to glTF 2.0 binary (GLB), from a
  file or from memory, with a JSON report (source metadata, animation takes,
  materials, removed collision hulls).
- `AssimpConvertOptions.normalize` bakes the source's units and axes into
  the scene; `AssimpConvertOptions.stripCollision` removes collision hulls.
- The native-assets build hook compiles the bundled Assimp 5.0 sources (and
  zlib on Windows) with the platform's C++ toolchain, so the package builds
  without CMake or prebuilt binaries; a Google Filament build can still be
  linked through the `filament_dir` user-define.
- Verified on Windows x64 and Linux x64; builds for Android arm64.
