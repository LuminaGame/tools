[Türkçe](../tr/flutter_assimp.md)

# flutter_assimp

`flutter_assimp` binds the Open Asset Import Library (Assimp) through Dart FFI and converts FBX, OBJ, Collada (DAE), 3DS, PLY, DirectX (X) and STL files, on disk or in memory, into binary glTF 2.0 (`.glb`), the format the Lumina engine loads. File paths are relative to the `flutter_assimp/` package directory.

Texture coordinates come out in glTF's convention (v = 0 at the top of the image): the V-up coordinates of FBX, OBJ, Collada and the other formats are written as `1 - v`, on every UV set and for every conversion (file or memory). Assimp 5.0's `Exporter::Export` runs an exporter twice on the same scene copy, and its glTF exporter flips V in place, so the bridge registers that exporter once more as `glb2-once`, which writes on the first run only; the plain `glb2` entry would hand back the source's V-up coordinates when converting to a file. A GLB converted before this fix holds V-up coordinates and draws its textures upside down; convert (import) the source again.

**On this page:**

- [Native build](#native-build)
- [Native C bridge](#native-c-bridge)
  - [`src/assimp_bridge.h`](#srcassimp_bridgeh)
- [Dart API](#dart-api)
  - [`lib/flutter_assimp.dart`](#libflutter_assimpdart)
  - [`lib/src/assimp_bindings.dart`](#libsrcassimp_bindingsdart)

## Native build

`hook/build.dart` compiles the bridge into the `flutter_assimp` dynamic library (code asset `package:flutter_assimp/src/third_party/assimp_c.g.dart`):

- **Bundled sources** (default, and how the package builds from pub.dev): the Assimp 5.0 sources in `third_party/assimp` (Filament's patched copy; `third_party/assimp/sources.txt` lists the compiled files, `tool/vendor_assimp.dart <filament checkout>` refreshes them) go to the compiler in one run through a response file. All importers but FBX, OBJ, Collada, 3DS, PLY, DirectX and STL are disabled with `ASSIMP_BUILD_NO_*_IMPORTER`, so Assimp's importer registry registers those seven; `src/vendored/` compiles the glTF 2 exporter with the glTF headers visible. zlib is `third_party/zlib` on Windows and the system library elsewhere.
- **Filament build** (Lumina): when `filament_dir` names a Filament build holding `out/cmake-release-windows/third_party/libassimp/tnt/assimp.lib` (Windows) or `out/cmake-release/third_party/libassimp/tnt/libassimp.a`, the bridge links it, compiles the extra importers from that checkout and registers them itself (`FLUTTER_ASSIMP_EXTRA_IMPORTERS`).

## Native C bridge

The C functions below are declared in the package's `src/` headers and called from Dart through FFI.

### `src/assimp_bridge.h`

| C Function | Signature | Purpose & Description |
| :--- | :--- | :--- |
| `assimp_get_last_error` | `ASSIMP_EXPORT const char* assimp_get_last_error();` | Returns the last error message recorded during Assimp file reading or conversion. |
| `assimp_get_import_extensions` | `ASSIMP_EXPORT const char* assimp_get_import_extensions();` | The file extensions the bridge imports, as Assimp lists them: `"*.fbx;*.obj;*.dae;…"`. |
| `assimp_convert_file_to_glb` | `ASSIMP_EXPORT int assimp_convert_file_to_glb( const char* input_pat...` | Reads any 3D model file on disk (FBX, OBJ, DAE, STL, BLEND, etc.), triangulates geometry, and writes a standard glTF 2.0 (.glb) binary file. |
| `assimp_convert_memory_to_glb` | `ASSIMP_EXPORT int assimp_convert_memory_to_glb( const uint8_t* in_b...` | Directly converts in-memory (RAM) 3D model buffer bytes into a glTF 2.0 (.glb) binary buffer based on format hint. |
| `assimp_free_blob` | `ASSIMP_EXPORT void assimp_free_blob(uint8_t* blob);` | Frees the native GLB memory blob allocated by C to prevent memory leaks. |

## Dart API

### `lib/flutter_assimp.dart`

#### `class FlutterAssimp`

High-performance native Assimp 3D asset conversion bridge for Dart & Flutter.

**Functions, Methods & Accessors:**

| Method / Getter | Signature | Purpose & Description |
| :--- | :--- | :--- |
| `isAvailable` | `static bool get isAvailable` | Returns true if the native Assimp library is loaded and available. |
| `version` | `static String get version` | Returns the underlying native Assimp library version (e.g. "5.0 (commit 4673545f)"). |
| `lastError` | `static String get lastError` | Returns the last error message from native Assimp operations. |
| `importExtensions` | `static Set<String> get importExtensions` | The lower-case extensions (no dot) the loaded bridge imports: FBX, OBJ, Collada (`dae`, `zae`), 3DS (`3ds`, `prj`), PLY, DirectX (`x`) and STL, whether the hook built the bundled Assimp sources or linked a Filament build (an older Filament prebuilt without the extra importer sources builds the bridge with FBX and OBJ only). Without the bridge: the formats the package is built to read. |
| `isSupportedFormat` | `static bool isSupportedFormat(String pathOrExtension)` | Whether [pathOrExtension] (a path, `.ext` or `ext`) is a 3D format the bridge imports ([importExtensions]). |

### `lib/src/assimp_bindings.dart`

#### `class AssimpBindings`

`AssimpBindings`: `class` representing the data model or functionality of the module.

**Constructors:**
- `AssimpBindings._init()`: Initializes `AssimpBindings._init()`.

**Functions, Methods & Accessors:**

| Method / Getter | Signature | Purpose & Description |
| :--- | :--- | :--- |
| `isAvailable` | `bool get isAvailable` | Checks current state or capability and returns a boolean value. |
| `getVersion` | `String getVersion()` | Queries and returns the `Version` value or child object. |
| `getLastError` | `String getLastError()` | Queries and returns the `LastError` value or child object. |
| `getImportExtensions` | `String? getImportExtensions()` | The extensions the loaded library imports (`"*.fbx;*.obj;…"`), or null when it is not loaded or predates the query. |

---

[Previous: Lumina tools documentation](../README.md) | [Up: Lumina tools documentation](../README.md) | [Next: flutter_riglogic](flutter_riglogic.md)
