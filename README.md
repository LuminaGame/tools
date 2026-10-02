[Türkçe](README.tr.md)

# Lumina tools

Native and FFI packages that the [Lumina](https://github.com/LuminaGame/lumina) game engine and its editor, Lumina Studio, build on. Lumina is a Flutter/Dart 3D game engine on top of Google Filament; the packages here cover model import, facial rig evaluation, video encoding and pointer capture.

Documentation: [docs/README.md](docs/README.md).

| Package | What it is |
|---|---|
| [`flutter_assimp`](flutter_assimp/) | Dart FFI bindings to [Assimp](https://github.com/assimp/assimp): converts FBX, OBJ, DAE, 3DS, Blend and other formats to glTF 2.0 binary (GLB). Links the Assimp library from a Filament build. |
| [`flutter_kimodo`](flutter_kimodo/) | Dart FFI bindings to [kimodo.cpp](https://github.com/localai-org/kimodo.cpp): NVIDIA Kimodo text-to-motion generation (GGUF weights, CPU and Vulkan) on a background isolate. |
| [`flutter_riglogic`](flutter_riglogic/) | Dart FFI bindings to Epic Games' [OpenRigLogic](https://github.com/EpicGames/openriglogic): reads MetaHuman `.dna` files and evaluates facial rigs. |
| [`flutter_gstreamer`](flutter_gstreamer/) | Pure-Dart FFI bindings to a system GStreamer 1.x install, loaded at run time: pipelines, VP8/WebM encoding from PNG or RGBA frames, media probing. The engine's smoke tests record their videos with it. |
| [`lumina_smoke`](lumina_smoke/) | The engine packages' shared smoke-test system: PNG and VP8/WebM artifacts with sidecar JSON matched by test name, the smoke-video rules (10 s, 1024×768, 30 fps) and probe, frame recorders, and the `flutter test` runner that writes the linked HTML smoke report. |
| [`lumina_mouse_capture`](lumina_mouse_capture/) | Flutter plugin for pointer capture with relative motion on Linux (Wayland pointer constraints, X11 grab and warp) and Windows (raw input, clipped hidden cursor); other platforms fall back to no capture. |

Related repositories: [lumina](https://github.com/LuminaGame/lumina) (engine and editor), [plugins](https://github.com/LuminaGame/plugins), [marketplace](https://github.com/LuminaGame/marketplace), [test-assets](https://github.com/LuminaGame/test-assets).

## Requirements

- Flutter SDK with Dart `^3.12.0`.
- [melos](https://melos.invertase.dev/) 7 for the workspace scripts (a dev dependency of the root pubspec; `dart pub global activate melos` puts `melos` on the PATH, or use `dart run melos`).
- For the native packages (`flutter_assimp`, `flutter_riglogic`):
  - **Linux**: clang, CMake, and the bundled libc++ that ships in the lumina repo under `flutter_filament/third_party/libcxx`.
  - **Windows**: Visual Studio 2022 with the C++ workload (MSVC), CMake and Ninja.
  - A prebuilt **Google Filament v1.77.0** (with the local patches documented in the lumina repo) for `flutter_assimp`.
- For `flutter_gstreamer`: GStreamer 1.x with the base and good plugin sets.
- For `lumina_mouse_capture` on Linux: GTK 3 and, for Wayland support, `wayland-client`, `wayland-scanner` and `wayland-protocols`.

## Setup

The Lumina repositories are meant to be checked out side by side:

```
<dir>/
  lumina/        https://github.com/LuminaGame/lumina
  tools/         this repository
  plugins/       https://github.com/LuminaGame/plugins
  marketplace/   https://github.com/LuminaGame/marketplace
  filament/      patched Filament v1.77.0 with its prebuilt out/ folders
  test-assets/   https://github.com/LuminaGame/test-assets (optional, Git LFS)
```

```bash
git clone https://github.com/LuminaGame/tools.git
cd tools
ln -s ../filament filament            # Windows: mklink /J filament ..\filament
ln -s ../test-assets test-assets      # optional; Windows: mklink /J test-assets ..\test-assets
dart pub get                          # resolves every package of the workspace
```

`filament/` and `test-assets/` are gitignored links. The repository is a Dart pub workspace: the root `pubspec.yaml` lists the packages under `workspace:`, each package has `resolution: workspace`, and one `pubspec.lock` covers them all.

### Filament

`flutter_assimp` compiles a small C++ bridge against the Assimp sources in `filament/third_party/libassimp` and links the static libraries of the Filament build:

- Linux / macOS: `filament/out/cmake-release/third_party/libassimp/tnt/libassimp.a` and `.../zstd/tnt/libzstd.a`
- Windows: `filament/out/cmake-release-windows/third_party/{libassimp,zstd,libz}/tnt/*.lib`

How to build and patch Filament is documented in the [lumina](https://github.com/LuminaGame/lumina) repository.

### OpenRigLogic

`flutter_riglogic` links a static OpenRigLogic library built from the vendored sources in `flutter_riglogic/third_party/openriglogic`:

```bash
bash flutter_riglogic/tool/build_openriglogic.sh              # Linux   -> third_party/openriglogic/lib/libriglogic.a
flutter_riglogic\tool\build_openriglogic.bat                  # Windows -> third_party\openriglogic\lib\riglogic.lib
flutter_riglogic\tool\build_openriglogic_android.bat [abi]    # Android (Windows host) -> third_party\openriglogic\lib\android\<abi>\libriglogic.a
bash flutter_riglogic/tool/build_openriglogic_android.sh [abi]# Android (Linux host)   -> third_party/openriglogic/lib/android/<abi>/libriglogic.a
```

### kimodo.cpp

`flutter_kimodo` bundles a prebuilt kimodo.cpp (kimodo + ggml shared libraries) built from the commit pinned in `flutter_kimodo/tool/kimodo/UPSTREAM`:

```bash
powershell -ExecutionPolicy Bypass -File flutter_kimodo\tool\build_kimodo.ps1   # Windows: VS 2022; Vulkan when the Vulkan SDK is installed
bash flutter_kimodo/tool/build_kimodo.sh                                      # Linux
dart run flutter_kimodo/tool/fetch_prebuilt.dart                              # unpack a local or released archive
```

See [docs/en/flutter_kimodo.md](docs/en/flutter_kimodo.md).

### Native-assets hook settings

The native-assets hooks of `flutter_assimp` and `flutter_riglogic` read their paths from `hooks: user_defines:` in the **workspace root pubspec of the app being built** (paths relative to that pubspec). Environment variables override them, but only when a hook is run directly: the Flutter/Dart hooks runner does not forward `LUMINA_*` variables.

| Setting | Package | Environment override | Default |
|---|---|---|---|
| `filament_dir` | flutter_assimp | `LUMINA_FILAMENT_DIR` | `<package>/../filament` (this repository's `filament/` link) |
| `libcxx_dir` (Linux) | both | `LUMINA_LIBCXX_DIR` | `<package>/../../lumina/flutter_filament/third_party/libcxx` |
| `riglogic_lib_dir` | flutter_riglogic | `LUMINA_RIGLOGIC_LIB_DIR` | `<package>/third_party/openriglogic/lib` |
| `kimodo_dir` | flutter_kimodo | `LUMINA_KIMODO_DIR` | `<package>/third_party/kimodo/prebuilt/<VERSION>/<os>-x64` |

This repository's root pubspec sets `flutter_assimp: filament_dir: filament`.

## Using the packages from another repository

Depend on them as git dependencies:

```yaml
dependencies:
  flutter_assimp:
    git:
      url: https://github.com/LuminaGame/tools.git
      path: flutter_assimp
  flutter_gstreamer:
    git:
      url: https://github.com/LuminaGame/tools.git
      path: flutter_gstreamer
```

A package resolved from git lives in the pub cache and has no Filament next to it, so the app's workspace root pubspec tells the hooks where things are. For example, in a workspace laid out like the lumina repository (with its own `filament/` link):

```yaml
hooks:
  user_defines:
    flutter_assimp:
      filament_dir: filament
      libcxx_dir: flutter_filament/third_party/libcxx
    flutter_riglogic:
      libcxx_dir: flutter_filament/third_party/libcxx
      riglogic_lib_dir: ../tools/flutter_riglogic/third_party/openriglogic/lib
```

For local development across sibling checkouts, a gitignored `pubspec_overrides.yaml` at the consuming workspace's root points the git dependencies at this checkout (pub workspaces read overrides from the root only):

```yaml
dependency_overrides:
  flutter_assimp:
    path: ../tools/flutter_assimp
  flutter_riglogic:
    path: ../tools/flutter_riglogic
  flutter_gstreamer:
    path: ../tools/flutter_gstreamer
  lumina_smoke:
    path: ../tools/lumina_smoke
  lumina_mouse_capture:
    path: ../tools/lumina_mouse_capture
```

## Development

```bash
melos run analyze        # flutter analyze in every package
melos run format         # dart format
melos run format:check   # fail on unformatted sources
melos run test           # flutter test in every package with a test/ folder, one at a time
```

Tests use real native libraries and real files, no mocks. Tests that need models from `test-assets/` (or `LUMINA_TEST_ASSETS`) are skipped when the assets are missing. To get them:

```bash
git lfs install
git clone https://github.com/LuminaGame/test-assets.git ../test-assets
```

## License

GPL-3.0 (see [LICENSE](LICENSE)); every package carries the same license file. Third-party code keeps its own license: OpenRigLogic (MIT, `flutter_riglogic/third_party/openriglogic/LICENSE`), kimodo.cpp (Apache-2.0) and ggml (MIT) in the kimodo prebuilt (`licenses/`), Assimp (BSD-3-Clause), Google Filament (Apache-2.0) and GStreamer (LGPL, loaded dynamically, not distributed).
