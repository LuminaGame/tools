# Changelog

## 0.0.1

- Initial release: Dart FFI bindings to Epic Games' OpenRigLogic and its DNA
  reader (`DnaReader`, `RigLogic`, `RigInstance`).
- The native-assets build hook compiles the bundled OpenRigLogic sources with
  the platform's C++ toolchain, so the package builds without CMake or
  prebuilt binaries; a prebuilt static library can still be linked through
  the `riglogic_lib_dir` user-define.
- Verified on Windows x64 and Linux x64; builds for Android arm64.
