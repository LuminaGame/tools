[Türkçe](../tr/flutter_kimodo.md)

# flutter_kimodo

Dart FFI bindings to [kimodo.cpp](https://github.com/localai-org/kimodo.cpp), the GGML port of NVIDIA's Kimodo
text-to-motion model. A prompt such as "a person walks forward and waves" becomes a 30 fps motion on Kimodo's 30-joint
SOMA skeleton. The Lumina Kimodo plugin retargets it onto skeletal meshes; this package only generates.

## What it contains

| Part | Where | What it does |
|---|---|---|
| Prebuilt runtime | `third_party/kimodo/prebuilt/<VERSION>/<os>-x64/` (gitignored) | `kimodo.dll` / `libkimodo.so` and the ggml backends, built from the pinned commit by `tool/build_kimodo.*` |
| Extension entry points | `native/kimodo_lumina.{h,cpp}` | compiled **into** the kimodo library: multi-prompt sequences (`kimodo_lumina_generate_sequence`), backend selection (`kimodo_lumina_configure`), the build's backends |
| Loader wrapper | `src/flutter_kimodo.{h,c}` | built by the native-assets hook; loads kimodo from its own folder at run time and forwards to it; lists Vulkan devices |
| Dart API | `lib/flutter_kimodo.dart` | `KimodoRuntime`, `KimodoModel`, `KimodoMotion`, `KimodoModelFiles`, `KimodoPrebuilt` |

The wrapper has no link-time dependency on kimodo: Windows does not look for a DLL's own imports next to it when the
DLL is loaded by path, so the wrapper loads `kimodo.dll` with the altered search path and the ggml DLLs resolve from the
same folder. The hook copies the runtime next to the wrapper and declares every library as a bundled code asset, so
`flutter test`, `flutter run` and built apps all carry it.

## Building the runtime

```powershell
powershell -ExecutionPolicy Bypass -File tool\build_kimodo.ps1 [-Vulkan auto|on|off] [-Clean]
```

```bash
bash tool/build_kimodo.sh [--vulkan auto|on|off] [--clean]
```

The script checks out `tool/kimodo/UPSTREAM` (repository + commit) with its ggml submodule into
`third_party/kimodo/src`, builds it through `tool/kimodo/CMakeLists.txt` (CMake ≥ 3.25, Ninja; Windows: Visual Studio
2022 x64, the dynamic CRT `/MD`), stages the libraries, `kimodo.lib`, the headers, the licences and
`lumina-kimodo.json` (provenance), packs `third_party/kimodo/dist/kimodo-<VERSION>-<os>-x64.{zip,tar.gz}` with a
`.sha256` sidecar and installs the folder the hook reads. A first CPU build takes a few minutes.

- **Vulkan**: `auto` builds the ggml Vulkan backend when the [Vulkan SDK](https://vulkan.lunarg.com/sdk/home) is
  installed (`VULKAN_SDK`, `glslc`) and the CPU backend only otherwise; `on` fails without the SDK.
- **Version**: `tool/kimodo/VERSION` (`<commit>-lumina.<n>`). Bump the `-lumina.N` suffix after changing the commit,
  `native/kimodo_lumina.cpp`, the build flags or the toolchain.
- **Fetching instead of building**: `dart run tool/fetch_prebuilt.dart` installs the archive in `dist/` (from a local
  build) or downloads `kimodo-<VERSION>-<os>-x64.*` from the `kimodo-<VERSION>` release of the tools repository,
  checks its SHA-256 and prints the folder.

The hook takes the folder from the `kimodo_dir` user-define (workspace root pubspec, relative to it), then
`LUMINA_KIMODO_DIR` (direct hook runs only), then the package default above, and fails with these instructions when
none holds the library.

## Model files

The weights are **not** part of the package or of any Lumina repository: they are several GB and their licences
(NVIDIA Open Model License for the SOMA model, Meta Llama 3 Community License for the text encoder) require the user's
acceptance. The Kimodo plugin downloads them. `KimodoModelFiles.find(dir)` locates:

- `kimodo-soma-rp-v1.1-f32.gguf` (the motion model, about 1.1 GB);
- `Llama-3-Kimodo-Q4_K_M.gguf` (default, about 5 GB) or `Llama-3-Kimodo-Q8_0.gguf` (about 8 GB), with
  `tokenizer.gguf` in the same folder.

`KimodoModelFiles.defaultDirectory()` is `KIMODO_MODELS_DIR`, else `<Lumina data>/plugin_data/lumina_plugin_kimodo/models`.

## Using it

```dart
import 'package:flutter_kimodo/flutter_kimodo.dart';

final files = KimodoModelFiles.find(KimodoModelFiles.defaultDirectory())!;
final model = await KimodoModel.load(
  motionGguf: files.motion,
  textGguf: files.text,
  backend: const KimodoBackend(vulkanDeviceName: 'RTX PRO 2000'),
);
final walk = await model.generate(
  'a person walks forward',
  frames: 150, // 5 s; at most 300
  options: const KimodoGenerationOptions(seed: 7, diffusionSteps: 100, textCfg: 2),
);
final sequence = await model.generateSequence(const [
  KimodoSegment('a person walks forward', 90),
  KimodoSegment('a person sits down on a chair', 120),
], transitionFrames: 5);
await model.dispose();
```

- `KimodoModel` lives on its own isolate: loading and generating block for seconds (GPU) to minutes (CPU), so they
  never run on the caller's isolate. Requests run one at a time, in order.
- `KimodoMotion`: `frames`, `joints` (30), `localRotationsXyzw` (`[frames, joints, 4]`, parent-local, identity = the
  rest T-pose), `rootPositions` (`[frames, 3]`, the hips, metres). Frame: Y up, +Z forward; the root starts at
  X = Z = 0 facing +Z; 30 fps.
- Errors are `KimodoException`s carrying kimodo's reason, for example
  `Loading the Kimodo model failed: cannot open GGUF file (motion: …)`.

## Choosing the device

kimodo.cpp reads its backend from the environment, and ggml reads its Vulkan device list once per process, at the
first model load. `KimodoRuntime.configure(KimodoBackend(...))` (called by `KimodoModel.load`) sets them before that:

| `KimodoBackend` | Effect |
|---|---|
| `device: KimodoDevice.auto` | Vulkan when the build has it and a device exists, else the CPU |
| `device: KimodoDevice.cpu` | `KIMODO_BACKEND=cpu` |
| `threads: n` | `KIMODO_THREADS=n` (0 = every core) |
| `vulkanDeviceName: 'RTX PRO 2000'` | the first device whose name contains it, by its `vkEnumeratePhysicalDevices` index (`GGML_VK_VISIBLE_DEVICES`) |

`KimodoBackend.fromEnvironment()` (the default) reads `KIMODO_DEVICE`, `KIMODO_THREADS` and `KIMODO_VULKAN_DEVICE`,
falling back to `FILAMENT_GPU`, so kimodo runs on the GPU Lumina renders on. `KimodoRuntime.vulkanDevices()` lists the
devices through the system Vulkan loader (no SDK needed). A later `configure` changes the CPU / Vulkan choice and the
threads, not the device.

## Tests

```bash
flutter test test/kimodo_runtime_test.dart test/kimodo_model_test.dart test/kimodo_prebuilt_test.dart
```

They call the real native library. The generation tests skip until the GGUF files are in `KIMODO_MODELS_DIR` (or the
plugin's model folder) and run as soon as they are. The bindings are written in ffigen's style; regenerate them with
`dart run tool/ffigen.dart` (needs libclang); `test/bindings_lockstep_test.dart` keeps them in step with the headers.

## Licences

The package is GPL-3.0 like the repository. The prebuilt carries kimodo.cpp (Apache-2.0, with its NOTICE) and ggml
(MIT) in `licenses/`; `src/kimodo/kimodo_capi.h` is vendored from kimodo.cpp (Apache-2.0). Model weights are never
bundled.

---

[Previous: flutter_riglogic](flutter_riglogic.md) · [Index](../README.md)
