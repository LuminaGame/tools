[Türkçe](README.tr.md)

# flutter_assimp

Dart FFI bindings to the [Open Asset Import Library (Assimp)](https://github.com/assimp/assimp) for in-process 3D model conversion. A small C bridge (`src/assimp_bridge.cpp`) loads a model with Assimp and writes glTF 2.0 binary (GLB). Lumina uses it to import FBX, OBJ, Collada (DAE), 3DS, PLY, DirectX (X) and STL files into its GLB-based asset pipeline.

The bridge is compiled by the package's native-assets hook (`hook/build.dart`) on the first `flutter run` / `flutter test`; there is no manual build step. It links the Assimp library of a Google Filament build instead of building Assimp itself.

Platforms: Linux and Windows (the hook also has a macOS branch).

## Requirements

- A prebuilt **Google Filament v1.77.0** (with the local patches documented in the [lumina](https://github.com/LuminaGame/lumina) repository). The hook uses:
  - the Assimp sources and headers in `<filament>/third_party/libassimp`: Filament's Assimp library has only the FBX and OBJ importers, so the hook also compiles the Collada, 3DS, PLY, DirectX and STL importers from `third_party/libassimp/code` (with `contrib/irrXML`, `contrib/unzip` and `third_party/libz` headers) when those sources are there; without them the bridge reads FBX and OBJ only;
  - Linux / macOS: `<filament>/out/cmake-release/third_party/libassimp/tnt/libassimp.a` and `third_party/zstd/tnt/libzstd.a`;
  - Windows: `<filament>/out/cmake-release-windows/third_party/libassimp/tnt/assimp.lib`, `zstd/tnt/zstd.lib`, `libz/tnt/z.lib`.
- Linux: clang and the bundled libc++ from the lumina repository (`flutter_filament/third_party/libcxx`).
- Windows: Visual Studio 2022 with the C++ workload.

## Where the hook finds Filament and libc++

| What | In order |
|---|---|
| Filament | 1. `LUMINA_FILAMENT_DIR` (only when the hook is run directly; the hooks runner does not forward `LUMINA_*` variables) 2. `filament_dir` under `hooks: user_defines: flutter_assimp:` in the workspace root pubspec, relative to that pubspec 3. `<package root>/../filament` |
| libc++ (Linux) | 1. `LUMINA_LIBCXX_DIR` 2. the `libcxx_dir` user-define 3. `<package root>/../../lumina/flutter_filament/third_party/libcxx` |

As a git dependency the package sits in the pub cache, so set the user-defines in your app's root pubspec:

```yaml
dependencies:
  flutter_assimp:
    git:
      url: https://github.com/LuminaGame/tools.git
      path: flutter_assimp

hooks:
  user_defines:
    flutter_assimp:
      filament_dir: filament                          # relative to this pubspec
      libcxx_dir: flutter_filament/third_party/libcxx # Linux only
```

## Usage

```dart
import 'package:flutter_assimp/flutter_assimp.dart';

if (FlutterAssimp.isAvailable) {
  print(FlutterAssimp.version); // e.g. "5.0 (commit 4673545f)"
}

// File to file. Falls back to an `assimp` CLI on the PATH when the native
// bridge is not loaded.
final ok = await FlutterAssimp.convertFileToGlb('crate.fbx', 'crate.glb');
if (!ok) print(FlutterAssimp.lastError);

// For an import pipeline: native bridge only, GLB bytes plus a report.
final result = FlutterAssimp.convertFileForImport(
  'SM_Barrel.fbx',
  options: AssimpConvertOptions.all, // normalize | stripCollision
);
if (result.success) {
  final glb = result.glb!;              // Uint8List
  final unitScale = result.report['unit_scale'];
  final hulls = result.report['collision'];
} else {
  print(result.error);
}

// In memory; `hint` is the source format's extension.
final glb = await FlutterAssimp.convertMemoryToGlb(bytes, hint: 'obj');

FlutterAssimp.isSupportedFormat('model.dae'); // true: one of FlutterAssimp.importExtensions
```

`AssimpConvertOptions`:

- `normalize` bakes the source's unit scale and axis system (FBX GlobalSettings) into the scene, so the GLB comes out in metres, +Y up, +Z front.
- `stripCollision` removes collision hull meshes (names starting with `UCX_`, `UBX_`, `USP_`, `UCP_`) and lists them in the report.

The report (`AssimpImportConversion.report`) also carries the source metadata, axes, animation takes, mesh, skinned-mesh, material and node counts, and per-material details (colours, PBR values, texture paths). `AssimpBindings` gives low-level access to the bridge.

## Development

Regenerate the `@Native` bindings (`lib/src/third_party/assimp_c.g.dart`) after changing `src/assimp_bridge.h`:

```bash
dart run tool/ffigen.dart
```

Tests:

```bash
flutter test test/flutter_assimp_test.dart test/fbx_import_conversion_test.dart
```

The conversion tests use real FBX files from the [test-assets](https://github.com/LuminaGame/test-assets) repository (`../test-assets`, or `LUMINA_TEST_ASSETS`) and are skipped when those are missing.

## License

GPL-3.0 (see [LICENSE](LICENSE)). Assimp is BSD-3-Clause and Google Filament is Apache-2.0; both keep their own licenses.
