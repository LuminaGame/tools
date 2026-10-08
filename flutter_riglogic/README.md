[Türkçe](https://github.com/LuminaGame/tools/blob/main/flutter_riglogic/README.tr.md)

# flutter_riglogic

Dart FFI bindings to Epic Games' [OpenRigLogic](https://github.com/EpicGames/openriglogic) and its DNA reader: read a MetaHuman `.dna` file and evaluate its facial rig in real time, from control values to joint transforms, blend shape weights and animated map values. The native code is compiled from the bundled OpenRigLogic sources by the package's native-assets build hook, so there is nothing to install besides a C++ compiler. [Lumina](https://github.com/LuminaGame/lumina) uses it to drive MetaHuman faces.

## Features

- `DnaReader`: reads a binary `.dna` from disk or memory: name, LOD count, joints, blend shape channels, raw and GUI controls, animated maps.
- `RigLogic`: the rig evaluator built from a `DnaReader` (joints, blend shapes, animated maps, PSD, RBF and machine-learned behaviour).
- `RigInstance`: one character's control values, LOD and calculated outputs.
- No CMake, no prebuilt binaries: the hook compiles OpenRigLogic and the C wrapper with the platform's toolchain on the first build and caches the result.

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
flutter pub add flutter_riglogic
```

Requirements: Dart 3.12 or later (Flutter with native assets), and the platform's C++ toolchain:

- Windows: Visual Studio 2022 (or the Build Tools) with the "Desktop development with C++" workload.
- Linux: `clang` (the Flutter Linux desktop prerequisites already include it).
- Android: the Android NDK that Flutter's Android toolchain installs.
- macOS / iOS: Xcode.

## Usage

```dart
import 'package:flutter_riglogic/flutter_riglogic.dart';

void evaluate(String dnaPath) {
  final reader = DnaReader.fromFile(dnaPath);
  print('${reader.name}: ${reader.jointCount} joints, '
      '${reader.blendShapeChannelCount} blend shapes, '
      '${reader.rawControlCount} raw controls');

  final rig = RigLogic.create(reader);
  final instance = RigInstance.create(rig)..lod = 0;

  instance.setRawControl(0, 1.0);
  rig.calculate(instance);

  final joints = instance.getJointOutputs(); // List<double>
  final weights = instance.getBlendShapeOutputs(); // List<double>
  final maps = instance.getAnimatedMapOutputs(); // List<double>
  print('${joints.length} joint values, ${weights.length} weights, ${maps.length} maps');

  instance.dispose();
  rig.dispose();
  reader.dispose();
}
```

`DnaReader.fromMemory(bytes)` reads a DNA that is already in memory (for example from `rootBundle`). The factories throw `UnsupportedError` when the native library is not loaded. Every object owns native memory: call `dispose()` when you are done.

The [example](https://github.com/LuminaGame/tools/tree/main/flutter_riglogic/example) is a Flutter app that loads a small DNA, lists its raw controls as sliders and shows the evaluated outputs.

## How the native library is built

`hook/build.dart` builds `flutter_riglogic` as a dynamic library and bundles it as a code asset; Dart calls it through `@Native` bindings.

- **From source (default).** The hook compiles the C wrapper (`src/riglogic_c.cpp`) together with the vendored OpenRigLogic sources (`third_party/openriglogic/src`, about 100 files). The first build takes about 20 seconds; later builds reuse the cached library.
- **Prebuilt static library (optional).** When `third_party/openriglogic/lib` (or the folder named by the `riglogic_lib_dir` user-define) holds `riglogic.lib` / `libriglogic.a`, only the wrapper is compiled and that library is linked. `tool/build_openriglogic.{sh,bat}` and `tool/build_openriglogic_android.{sh,bat}` build it with CMake. An app sets the user-define in its root pubspec, relative to that pubspec:

  ```yaml
  hooks:
    user_defines:
      flutter_riglogic:
        riglogic_lib_dir: third_party/openriglogic/lib
        libcxx_dir: path/to/libcxx   # Linux only, a libc++ the prebuilt library was built against
  ```

## Additional information

- Source, issues and contributions: [LuminaGame/tools](https://github.com/LuminaGame/tools) ([issues](https://github.com/LuminaGame/tools/issues)). Tests: `flutter test test/dna_reader_test.dart test/rig_logic_test.dart` (they read the real DNA fixture `test/fixtures/sample.dna`); `dart run tool/inspect_dna.dart` prints that fixture's joints, blend shapes and controls.
- License: GPL-3.0 (see [LICENSE](LICENSE)). The bundled OpenRigLogic is MIT-licensed by Epic Games; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
- MetaHuman DNA files from Epic's MetaHuman tools are subject to Epic's own license terms; this package ships only a small synthetic test DNA.
