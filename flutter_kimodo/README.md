[Türkçe](README.tr.md)

# flutter_kimodo

Dart FFI bindings to [kimodo.cpp](https://github.com/localai-org/kimodo.cpp), the GGML port of NVIDIA Kimodo: text
prompts become 30 fps motions on Kimodo's 30-joint SOMA skeleton, on the CPU or a Vulkan GPU, generated on a background
isolate.

- `tool/build_kimodo.ps1` / `tool/build_kimodo.sh` build the pinned kimodo.cpp commit (`tool/kimodo/UPSTREAM`) into
  `third_party/kimodo/prebuilt/<VERSION>/<os>-x64` plus a `.sha256`-checked archive; `tool/fetch_prebuilt.dart`
  installs an archive instead.
- The native-assets hook builds the loader wrapper (`src/flutter_kimodo.c`) and bundles the kimodo and ggml libraries
  beside it.
- `KimodoModel.load(...)`, `generate(prompt, frames: …)`, `generateSequence([...])` → `KimodoMotion` (local XYZW
  rotations per joint and frame, root positions).

Model weights are not included: they are downloaded separately under their own licences. Documentation:
[docs/en/flutter_kimodo.md](../docs/en/flutter_kimodo.md).
