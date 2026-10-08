[Türkçe](https://github.com/LuminaGame/tools/blob/main/flutter_assimp/README.tr.md)

# flutter_assimp

Dart FFI bindings to the [Open Asset Import Library (Assimp)](https://github.com/assimp/assimp) for converting 3D models to glTF 2.0 binary (GLB) inside your app: FBX, OBJ, Collada, 3DS, PLY, DirectX and STL go in, a GLB and a JSON report of what was converted come out. A small C bridge (`src/assimp_bridge.cpp`) drives Assimp; the package's native-assets build hook compiles it together with the bundled Assimp sources, so there is nothing to install besides a C++ compiler. [Lumina](https://github.com/LuminaGame/lumina) uses it to import models into its GLB-based asset pipeline.

## Features

- File to file (`convertFileToGlb`), file to bytes with a report (`convertFileForImport`) and bytes to bytes (`convertMemoryToGlb`).
- Reads FBX (binary and ASCII), OBJ (+MTL), Collada (`.dae`, zipped `.zae`), 3DS, PLY, DirectX (`.x`) and STL.
- Optional normalization: bakes the source's unit scale and axis system (FBX GlobalSettings) into the scene, so the GLB is standard glTF (metres, +Y up, +Z front).
- Optional removal of collision hull meshes (`UCX_`, `UBX_`, `USP_`, `UCP_`), returned in the report with their points and triangles.
- A report with source metadata, animation takes, mesh, skinned-mesh, material and node counts, and per-material colours, PBR values and texture paths.
- Skinned meshes and animations are kept (one glTF animation per take).

## Platform support

| Platform | Status |
|---|---|
| Windows x64 | Verified (`flutter test`, `flutter build windows`) |
| Linux x64 | Verified (`flutter test`, `flutter build linux`) |
| Android arm64 | Builds and links (`flutter build apk`); libc++ is linked statically |
| macOS, iOS | Expected to build with Xcode's clang; not verified yet |
| Web | Not supported (`dart:ffi`) |

## Getting started

```bash
flutter pub add flutter_assimp
```

Requirements: Dart 3.12 or later (Flutter with native assets), and the platform's C++ toolchain:

- Windows: Visual Studio 2022 (or the Build Tools) with the "Desktop development with C++" workload.
- Linux: `clang` and the zlib headers (`zlib1g-dev`; the Flutter Linux desktop prerequisites already pull them in).
- Android: the Android NDK that Flutter's Android toolchain installs.
- macOS / iOS: Xcode.

## Usage

```dart
import 'package:flutter_assimp/flutter_assimp.dart';

Future<void> convert() async {
  if (FlutterAssimp.isAvailable) {
    print(FlutterAssimp.version); // e.g. "5.0 (commit 4673545f)"
  }

  // File to file.
  final ok = await FlutterAssimp.convertFileToGlb('crate.fbx', 'crate.glb');
  if (!ok) print(FlutterAssimp.lastError);

  // For an import pipeline: GLB bytes plus a report.
  final result = FlutterAssimp.convertFileForImport(
    'SM_Barrel.fbx',
    options: AssimpConvertOptions.all, // normalize | stripCollision
  );
  if (result.success) {
    final glb = result.glb!; // Uint8List
    print('${glb.length} bytes, unit scale ${result.report['unit_scale']}, '
        'hulls ${result.report['collision']}');
  } else {
    print(result.error);
  }

  // In memory; `hint` is the source format's extension.
  final bytes = await File('crate.obj').readAsBytes();
  final fromMemory = await FlutterAssimp.convertMemoryToGlb(bytes, hint: 'obj');
  print(fromMemory?.length);

  print(FlutterAssimp.isSupportedFormat('model.dae')); // true
}
```

(`File` comes from `dart:io`.) `AssimpConvertOptions.normalize` bakes units and axes, `AssimpConvertOptions.stripCollision` removes collision hulls and lists them in the report. `convertFileToGlb` falls back to an `assimp` command-line tool on the `PATH` when the native bridge is not loaded; the other calls need the bridge. `AssimpBindings` gives low-level access to it.

See [example/main.dart](https://github.com/LuminaGame/tools/blob/main/flutter_assimp/example/main.dart) for a complete conversion.

## How the native library is built

`hook/build.dart` builds `flutter_assimp` as a dynamic library and bundles it as a code asset; Dart calls it through `@Native` bindings.

- **From the bundled sources (default).** The hook compiles the bridge with the Assimp 5.0 sources in `third_party/assimp` (Google Filament's patched copy of Assimp, reduced to the importers above and the glTF 2 exporter) in one compiler run. zlib comes from `third_party/zlib` on Windows and from the system elsewhere. The first build takes about 20 seconds on a desktop machine; later builds reuse the cached library. `tool/vendor_assimp.dart` refreshes the bundled sources from a Filament checkout.
- **Against a Filament build (optional).** When the `filament_dir` user-define (relative to the app's root pubspec) names a Google Filament build with its Assimp static library (`out/cmake-release-windows/third_party/libassimp/tnt/assimp.lib` on Windows, `out/cmake-release/third_party/libassimp/tnt/libassimp.a` elsewhere), the hook links that library and compiles only the bridge, the exporter and the extra importers. This is how Lumina builds it:

  ```yaml
  hooks:
    user_defines:
      flutter_assimp:
        filament_dir: filament
        libcxx_dir: flutter_filament/third_party/libcxx # Linux only: the libc++ Filament was built with
  ```

## Additional information

- Source, issues and contributions: [LuminaGame/tools](https://github.com/LuminaGame/tools) ([issues](https://github.com/LuminaGame/tools/issues)).
- Tests: `flutter test test/import_formats_test.dart test/fbx_import_conversion_test.dart`. The FBX tests read real Unreal exports from Lumina's test-assets folder (`../test-assets`, or `LUMINA_TEST_ASSETS`) and are skipped when it is missing. After changing `src/assimp_bridge.h`, regenerate the bindings with `dart run tool/ffigen.dart`.
- License: GPL-3.0 (see [LICENSE](LICENSE)). The bundled Assimp (BSD-3-Clause) with its contrib libraries and zlib keep their own licenses; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
