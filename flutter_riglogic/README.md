[Türkçe](README.tr.md)

# flutter_riglogic

Dart FFI bindings to Epic Games' [OpenRigLogic](https://github.com/EpicGames/openriglogic) and its DNA reader. Lumina uses it to evaluate MetaHuman facial rigs in real time.

OpenRigLogic computes rig outputs (joint transforms, blend shape weights, animated map values) from input control values. This package wraps it in three classes:

- `DnaReader` reads a binary `.dna` file (from disk or memory): name, LOD count, joints, blend shape channels, raw and GUI controls, animated maps.
- `RigLogic` builds the rig evaluator from a `DnaReader`.
- `RigInstance` holds one character's control values, LOD and calculated outputs.

The C wrapper (`src/riglogic_c.h`, `src/riglogic_c.cpp`) is compiled by the package's native-assets hook (`hook/build.dart`) and links a static OpenRigLogic library that you build once from the vendored sources.

Platforms: Linux and Windows (the hook also has a macOS branch).

## Requirements

- Linux: clang, CMake and the bundled libc++ from the [lumina](https://github.com/LuminaGame/lumina) repository (`flutter_filament/third_party/libcxx`).
- Windows: Visual Studio 2022 with the C++ workload, CMake and Ninja.

## Building OpenRigLogic

OpenRigLogic (MIT) is vendored under `third_party/openriglogic/`. Build the static library before the first `flutter run` / `flutter test`:

```bash
bash tool/build_openriglogic.sh     # Linux: clang + bundled libc++, -fPIC -> third_party/openriglogic/lib/libriglogic.a
```

```bat
tool\build_openriglogic.bat                     :: Windows: MSVC, static CRT (/MT) -> third_party\openriglogic\lib\riglogic.lib
```

```bash
# Android cross-compilation (arm64-v8a and x86_64; requires Android NDK):
tool\build_openriglogic_android.bat [abi]       # Windows host -> third_party/openriglogic/lib/android/<abi>/libriglogic.a
bash tool/build_openriglogic_android.sh [abi]   # Linux host   -> third_party/openriglogic/lib/android/<abi>/libriglogic.a
```

The Linux script finds libc++ through `LUMINA_LIBCXX_DIR`, else `../../lumina/flutter_filament/third_party/libcxx`. The Windows script sets up the MSVC environment with `vswhere` when it is not already active. The Android scripts detect the Android NDK from `ANDROID_NDK_HOME`, `ANDROID_NDK_ROOT`, or the default SDK NDK location, using `libc++_shared` and clang.

## Where the hook finds its inputs

| What | In order |
|---|---|
| OpenRigLogic library | 1. `LUMINA_RIGLOGIC_LIB_DIR` (only when the hook is run directly; the hooks runner does not forward `LUMINA_*` variables) 2. `riglogic_lib_dir` under `hooks: user_defines: flutter_riglogic:` in the workspace root pubspec, relative to that pubspec, when the library is there 3. `<package root>/third_party/openriglogic/lib` |
| libc++ (Linux) | 1. `LUMINA_LIBCXX_DIR` 2. the `libcxx_dir` user-define 3. `<package root>/../../lumina/flutter_filament/third_party/libcxx` |

A `riglogic_lib_dir` that does not hold the library yields to the package's own build, so an app can name the folder it links a prebuilt library into while a development checkout of this package keeps the library built in place. The hook stops with an error naming the build script when `libriglogic.a` / `riglogic.lib` is missing from both. A git dependency lives in the pub cache, where the library is not built, so point `riglogic_lib_dir` at a checkout where you ran the build script:

```yaml
dependencies:
  flutter_riglogic:
    git:
      url: https://github.com/LuminaGame/tools.git
      path: flutter_riglogic

hooks:
  user_defines:
    flutter_riglogic:
      riglogic_lib_dir: ../tools/flutter_riglogic/third_party/openriglogic/lib
      libcxx_dir: flutter_filament/third_party/libcxx   # Linux only
```

## Usage

```dart
import 'package:flutter_riglogic/flutter_riglogic.dart';

final reader = DnaReader.fromFile('assets/face.dna');
print('${reader.name}: ${reader.jointCount} joints, '
    '${reader.blendShapeChannelCount} blend shapes, ${reader.rawControlCount} raw controls');

final rig = RigLogic.create(reader);
final instance = RigInstance.create(rig)..lod = 0;

instance.setRawControl(0, 1.0);
rig.calculate(instance);

final joints = instance.getJointOutputs();          // List<double>
final weights = instance.getBlendShapeOutputs();    // List<double>
final maps = instance.getAnimatedMapOutputs();      // List<double>

instance.dispose();
rig.dispose();
reader.dispose();
```

`DnaReader.fromMemory(bytes)` reads a DNA that is already in memory. The factories throw `UnsupportedError` when the native library is not loaded.

`example/` is a Flutter app that loads `assets/sample.dna` and drives the rig's controls. From the package folder, `dart run tool/inspect_dna.dart` prints the joints, blend shapes and controls of `test/fixtures/sample.dna`.

## Tests

```bash
flutter test test/dna_reader_test.dart test/rig_logic_test.dart
```

They run against the real binary DNA fixture `test/fixtures/sample.dna`.

## License

GPL-3.0 (see [LICENSE](LICENSE)). The vendored OpenRigLogic in `third_party/openriglogic/` is MIT-licensed by Epic Games (see its [LICENSE](third_party/openriglogic/LICENSE)).
