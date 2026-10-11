[Türkçe](../tr/flutter_kimodo.md)

# flutter_kimodo

Dart FFI bindings to [kimodo.cpp](https://github.com/localai-org/kimodo.cpp), the GGML port of NVIDIA's Kimodo
text-to-motion model. A prompt such as "a person walks forward and waves" becomes a 30 fps motion on Kimodo's 30-joint
SOMA skeleton. The Lumina Kimodo plugin retargets it onto skeletal meshes; this package only generates.

## What it contains

| Part | Where | What it does |
|---|---|---|
| Prebuilt runtime | `third_party/kimodo/prebuilt/<VERSION>/<os>-x64/` (gitignored) | `kimodo.dll` / `libkimodo.so` and the ggml backends, built from the pinned commit by `tool/build_kimodo.*` |
| Extension entry points | `native/kimodo_lumina.{h,cpp}` | compiled **into** the kimodo library: multi-prompt sequences (`kimodo_lumina_generate_sequence`), constrained generation (`kimodo_lumina_generate_constrained`), backend selection (`kimodo_lumina_configure`), the build's backends |
| Loader wrapper | `src/flutter_kimodo.{h,c}` | built by the native-assets hook; loads kimodo from its own folder at run time and forwards to it; lists Vulkan devices |
| Dart API | `lib/flutter_kimodo.dart` | `KimodoRuntime`, `KimodoModel`, `KimodoMotion`, `KimodoConstraints`, `KimodoSkeleton`, `KimodoModelFiles`, `KimodoPrebuilt` |

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
`third_party/kimodo/src`, applies `tool/kimodo/patches/*.patch` in order (on a clean LF checkout; a checkout that already has them is kept), builds it through `tool/kimodo/CMakeLists.txt` (CMake ≥ 3.25, Ninja; Windows: Visual Studio
2022 x64, the dynamic CRT `/MD`), stages the libraries, `kimodo.lib`, the headers, the licences and
`lumina-kimodo.json` (provenance), packs `third_party/kimodo/dist/kimodo-<VERSION>-<os>-x64.{zip,tar.gz}` with a
`.sha256` sidecar and installs the folder the hook reads. A first CPU build takes a few minutes.

- **Vulkan**: `auto` builds the ggml Vulkan backend when the [Vulkan SDK](https://vulkan.lunarg.com/sdk/home) is
  installed (`VULKAN_SDK`, `glslc`) and the CPU backend only otherwise; `on` fails without the SDK.
- **Version**: `tool/kimodo/VERSION` (`<commit>-lumina.<n>`). Bump the `-lumina.N` suffix after changing the commit, a
  patch, `native/kimodo_lumina.cpp`, the build flags or the toolchain. The hook depends on `VERSION`, so a bump
  re-runs it. `5679ff1-lumina.2` adds `patches/0001-constrained-generation.patch` (constraint tensors for single prompts
  and sequences, normalised in the library).
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

## Constraints

Kimodo can follow constraints while it denoises: a root path on the ground, end effectors (hands, feet, the hips) at
given frames and full-body keyframes. `KimodoConstraints` is the list of NVIDIA Kimodo's constraint sets
(`kimodo.constraints` in the Python reference), with frames counted over the whole generated timeline:

| Dart | Upstream | Pins on each frame |
|---|---|---|
| `KimodoRoot2DConstraint(frames, points, headings?)` | `Root2DConstraintSet` | the smooth root's ground position (x, z) and, when given, the heading (radians, 0 faces +Z) |
| `KimodoEndEffectorConstraint.leftHand / rightHand / leftFoot / rightFoot(frames, poses)`, `KimodoEndEffectorConstraint(joints: [...])` | `EndEffectorConstraintSet` and subclasses | the chain's joint positions (hand + middle finger tip, foot + toe), the first joint's rotation, the pose's smooth root, pelvis height and heading |
| `KimodoFullBodyConstraint(frames, poses)` | `FullBodyConstraintSet` | every joint position, the smooth root, pelvis height and heading |

```dart
final skeleton = KimodoSkeleton.soma30;
final base = await model.generate('a person stands and looks around', frames: 90);
final pose = skeleton.motionPose(base, 60); // global positions + rotations
final raised = pose.translated(0, 0.25, 0); // or move only the hand chain
final motion = await model.generate(
  'a person stands and looks around',
  frames: 90,
  constraints: KimodoConstraints([
    KimodoRoot2DConstraint(frames: [0, 89], points: [(x: 0, z: 0), (x: 1.5, z: 1.0)]),
    KimodoEndEffectorConstraint.leftHand(frames: [60], poses: [raised]),
  ]),
  options: const KimodoGenerationOptions(constraintCfg: 2),
);
```

- `generateSequence(segments, constraints: ...)` takes constraints over the joined timeline (the segments' frames one
  after another); each segment is conditioned on the rows of its own frames after the transition rows, as upstream's
  `_multiprompt` does.
- `KimodoConstraints.encode(frames)` builds the conditioning tensors in the motion representation's feature layout
  (smooth root, heading, joint positions relative to the smooth root, global 6D rotations; unnormalised): the
  feature layout of upstream `KimodoMotionRep.create_conditions`. A later set replaces an earlier one's value for the
  same frame (and joint). kimodo.cpp normalises them with the checkpoint's statistics.
- `KimodoSkeleton.soma30` has the names, parents, rest offsets, hips and end-effector chains; `pose(...)` /
  `motionPose(motion, frame)` run forward kinematics into a `KimodoPose` (global positions and row-major rotation
  matrices; `translated`, `turned`).
- **Parity**: `test/fixtures/constraints_parity.json` holds the tensors the Python reference builds for root paths,
  each end effector, full-body keys and overlapping sets on random poses;
  `tool/kimodo/constraints_parity_fixture.py` (with `KIMODO_UPSTREAM_DIR` pointing at an `nv-tlabs/kimodo` checkout)
  writes it, and the test compares every value.
- The C surface is `kimodo_lumina_generate_constrained` (prompts, frames, the transition, `observed_motion` and
  `motion_mask` of `[sum(frames), motion_dim]`, mask values 0 or 1, validated before generation).

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
flutter test test/kimodo_constraints_test.dart
```

They call the real native library. `kimodo_constraints_test.dart` checks the encoding against the Python reference's
fixture and, with the weights, that a 3 m root path ends within 0.3 m of its goal, that a left-hand target is reached
within 0.1 m and that constraints steer the second prompt of a sequence. The generation tests skip until the GGUF files are in `KIMODO_MODELS_DIR` (or the
plugin's model folder) and run as soon as they are. The bindings are written in ffigen's style; regenerate them with
`dart run tool/ffigen.dart` (needs libclang); `test/bindings_lockstep_test.dart` keeps them in step with the headers.

## Licences

The package is GPL-3.0 like the repository. The prebuilt carries kimodo.cpp (Apache-2.0, with its NOTICE) and ggml
(MIT) in `licenses/`; `src/kimodo/kimodo_capi.h` is vendored from kimodo.cpp (Apache-2.0). Model weights are never
bundled.

---

[Previous: flutter_riglogic](flutter_riglogic.md) · [Index](../README.md)
