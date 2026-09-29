[Türkçe](../tr/flutter_assimp.md)

# flutter_assimp

`flutter_assimp` binds the Open Asset Import Library (Assimp) through Dart FFI and converts more than 40 3D formats (FBX, OBJ, DAE, STL, Blend and others), on disk or in memory, into binary glTF 2.0 (`.glb`), the format the Lumina engine loads. File paths are relative to the `flutter_assimp/` package directory.

**On this page:**

- [Native C bridge](#native-c-bridge)
  - [`src/assimp_bridge.h`](#srcassimp_bridgeh)
- [Dart API](#dart-api)
  - [`lib/flutter_assimp.dart`](#libflutter_assimpdart)
  - [`lib/src/assimp_bindings.dart`](#libsrcassimp_bindingsdart)

## Native C bridge

The C functions below are declared in the package's `src/` headers and called from Dart through FFI.

### `src/assimp_bridge.h`

| C Function | Signature | Purpose & Description |
| :--- | :--- | :--- |
| `assimp_get_last_error` | `ASSIMP_EXPORT const char* assimp_get_last_error();` | Returns the last error message recorded during Assimp file reading or conversion. |
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
| `version` | `static String get version` | Returns the underlying native Assimp library version (e.g. "6.0.5"). |
| `lastError` | `static String get lastError` | Returns the last error message from native Assimp operations. |
| `isSupportedFormat` | `static bool isSupportedFormat(String pathOrExtension)` | Checks if a file path or extension is a supported 3D import format. |

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

---

[Previous: Lumina tools documentation](../README.md) | [Up: Lumina tools documentation](../README.md) | [Next: flutter_riglogic](flutter_riglogic.md)
