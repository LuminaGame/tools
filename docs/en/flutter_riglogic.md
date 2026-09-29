[Türkçe](../tr/flutter_riglogic.md)

# flutter_riglogic

`flutter_riglogic` binds Epic Games' OpenRigLogic library through Dart FFI. It reads MetaHuman `.dna` files and evaluates facial rigs (PSDs, RBFs, joint transforms and blend shape weights) every frame. File paths are relative to the `flutter_riglogic/` package directory.

**On this page:**

- [Native C bridge](#native-c-bridge)
  - [`src/riglogic_c.h`](#srcriglogic_ch)
- [Dart API](#dart-api)
  - [`lib/src/bindings.dart`](#libsrcbindingsdart)
  - [`lib/src/dna_reader.dart`](#libsrcdna_readerdart)
  - [`lib/src/rig_instance.dart`](#libsrcrig_instancedart)
  - [`lib/src/rig_logic.dart`](#libsrcrig_logicdart)

## Native C bridge

The C functions below are declared in the package's `src/` headers and called from Dart through FFI.

### `src/riglogic_c.h`

| C Function | Signature | Purpose & Description |
| :--- | :--- | :--- |
| `rl_dna_reader_create_from_file` | `RL_C_API rl_dna_reader_t* rl_dna_reader_create_from_file(const char...` | Reads a MetaHuman DNA binary file from disk and creates a DNA reader handle. |
| `rl_dna_reader_create_from_memory` | `RL_C_API rl_dna_reader_t* rl_dna_reader_create_from_memory(const vo...` | Creates a DNA reader handle from in-memory DNA buffer bytes. |
| `rl_dna_reader_destroy` | `RL_C_API void rl_dna_reader_destroy(rl_dna_reader_t* reader);` | Destroys the DNA reader instance and releases its memory. |
| `rl_dna_reader_get_name` | `RL_C_API const char* rl_dna_reader_get_name(const rl_dna_reader_t* ...` | Returns the character or rig name stored in the DNA file. |
| `rl_dna_reader_get_lod_count` | `RL_C_API uint16_t rl_dna_reader_get_lod_count(const rl_dna_reader_t...` | Returns the number of Level-of-Detail (LOD) tiers defined for the character. |
| `rl_dna_reader_get_joint_count` | `RL_C_API uint16_t rl_dna_reader_get_joint_count(const rl_dna_reader...` | Returns the total number of joints/bones in the character rig. |
| `rl_dna_reader_get_joint_name` | `RL_C_API const char* rl_dna_reader_get_joint_name(const rl_dna_read...` | Returns the name of the joint/bone at the specified index. |
| `rl_dna_reader_get_blend_shape_channel_count` | `RL_C_API uint16_t rl_dna_reader_get_blend_shape_channel_count(const...` | Returns the total number of morph target / blend shape channels. |
| `rl_dna_reader_get_blend_shape_channel_name` | `RL_C_API const char* rl_dna_reader_get_blend_shape_channel_name(con...` | Returns the name of the blend shape channel at the specified index. |
| `rl_dna_reader_get_raw_control_count` | `RL_C_API uint16_t rl_dna_reader_get_raw_control_count(const rl_dna_...` | Returns the number of raw control input channels (e.g. brow raise, squint). |
| `rl_dna_reader_get_raw_control_name` | `RL_C_API const char* rl_dna_reader_get_raw_control_name(const rl_dn...` | Returns the name of the raw control input channel at the specified index. |
| `rl_dna_reader_get_gui_control_count` | `RL_C_API uint16_t rl_dna_reader_get_gui_control_count(const rl_dna_...` | Returns the number of GUI controls. |
| `rl_dna_reader_get_gui_control_name` | `RL_C_API const char* rl_dna_reader_get_gui_control_name(const rl_dn...` | Returns the name of the GUI control at the specified index. |
| `rl_dna_reader_get_animated_map_count` | `RL_C_API uint16_t rl_dna_reader_get_animated_map_count(const rl_dna...` | Returns the number of animated maps (wrinkle / normal maps). |
| `rl_dna_reader_get_animated_map_name` | `RL_C_API const char* rl_dna_reader_get_animated_map_name(const rl_d...` | Returns the name of the animated map at the specified index. |
| `rl_riglogic_create` | `RL_C_API rl_riglogic_t* rl_riglogic_create(rl_dna_reader_t* reader);` | Builds and compiles the RigLogic ML and deformation evaluation engine from a DNA reader. |
| `rl_riglogic_destroy` | `RL_C_API void rl_riglogic_destroy(rl_riglogic_t* rl);` | Destroys the RigLogic engine instance and releases native resources. |
| `rl_riglogic_calculate` | `RL_C_API void rl_riglogic_calculate(rl_riglogic_t* rl, rl_riginstan...` | Evaluates control input values and computes runtime joint transforms and blend shape outputs. |
| `rl_riginstance_create` | `RL_C_API rl_riginstance_t* rl_riginstance_create(rl_riglogic_t* rl);` | Creates an independent runtime evaluation instance for a specific character. |
| `rl_riginstance_destroy` | `RL_C_API void rl_riginstance_destroy(rl_riginstance_t* inst);` | Destroys the RigInstance and frees allocated memory. |
| `rl_riginstance_get_raw_control_count` | `RL_C_API uint16_t rl_riginstance_get_raw_control_count(const rl_rig...` | Returns the number of raw control input channels on the instance. |
| `rl_riginstance_get_raw_control` | `RL_C_API float rl_riginstance_get_raw_control(const rl_riginstance_...` | Gets the current float value (0.0 to 1.0) of the control at the specified index. |
| `rl_riginstance_set_raw_control` | `RL_C_API void rl_riginstance_set_raw_control(rl_riginstance_t* inst...` | Sets a new float input value for the control channel at the specified index. |
| `rl_riginstance_get_lod` | `RL_C_API uint16_t rl_riginstance_get_lod(const rl_riginstance_t* in...` | Gets the current LOD evaluation level for the instance. |
| `rl_riginstance_set_lod` | `RL_C_API void rl_riginstance_set_lod(rl_riginstance_t* inst, uint16...` | Sets the LOD evaluation level for the instance. |
| `rl_riginstance_get_joint_outputs` | `RL_C_API uint32_t rl_riginstance_get_joint_outputs(const rl_riginst...` | Retrieves the evaluated 3D bone transforms (translation, rotation, scale) as a float array. |
| `rl_riginstance_get_blend_shape_outputs` | `RL_C_API uint32_t rl_riginstance_get_blend_shape_outputs(const rl_r...` | Retrieves the evaluated morph target / blend shape weight array. |
| `rl_riginstance_get_animated_map_outputs` | `RL_C_API uint32_t rl_riginstance_get_animated_map_outputs(const rl_...` | Retrieves the evaluated wrinkle map / animated normal map weights. |

## Dart API

### `lib/src/bindings.dart`

**Top-level Functions:**

- **`Pointer<RlDnaReader> Function(Pointer<Utf8> path)`**: Executes `Function` operation.
- **`Pointer<RlDnaReader> Function(Pointer<Utf8> path)`**: Executes `Function` operation.
- **`Pointer<RlDnaReader> Function(Pointer<Uint8> data, IntPtr size)`**: Executes `Function` operation.
- **`Pointer<RlDnaReader> Function(Pointer<Uint8> data, int size)`**: Executes `Function` operation.
- **`Pointer<Utf8> Function(Pointer<RlDnaReader> reader)`**: Executes `Function` operation.
- **`Pointer<Utf8> Function(Pointer<RlDnaReader> reader)`**: Executes `Function` operation.
- **`Uint16 Function(Pointer<RlDnaReader> reader)`**: Executes `Function` operation.
- **`int Function(Pointer<RlDnaReader> reader)`**: Executes `Function` operation.
- **`Pointer<Utf8> Function(Pointer<RlDnaReader> reader, Uint16 index)`**: Executes `Function` operation.
- **`Pointer<Utf8> Function(Pointer<RlDnaReader> reader, int index)`**: Executes `Function` operation.
- **`Uint16 Function(Pointer<RlDnaReader> reader)`**: Executes `Function` operation.
- **`int Function(Pointer<RlDnaReader> reader)`**: Executes `Function` operation.
- **`Pointer<Utf8> Function(Pointer<RlDnaReader> reader, Uint16 index)`**: Executes `Function` operation.
- **`Pointer<Utf8> Function(Pointer<RlDnaReader> reader, int index)`**: Executes `Function` operation.
- **`Uint16 Function(Pointer<RlDnaReader> reader)`**: Executes `Function` operation.
- **`int Function(Pointer<RlDnaReader> reader)`**: Executes `Function` operation.
- **`Pointer<Utf8> Function(Pointer<RlDnaReader> reader, Uint16 index)`**: Executes `Function` operation.
- **`Pointer<Utf8> Function(Pointer<RlDnaReader> reader, int index)`**: Executes `Function` operation.
- **`Uint16 Function(Pointer<RlDnaReader> reader)`**: Executes `Function` operation.
- **`int Function(Pointer<RlDnaReader> reader)`**: Executes `Function` operation.
- **`Pointer<Utf8> Function(Pointer<RlDnaReader> reader, Uint16 index)`**: Executes `Function` operation.
- **`Pointer<Utf8> Function(Pointer<RlDnaReader> reader, int index)`**: Executes `Function` operation.
- **`Uint16 Function(Pointer<RlDnaReader> reader)`**: Executes `Function` operation.
- **`int Function(Pointer<RlDnaReader> reader)`**: Executes `Function` operation.
- **`Pointer<Utf8> Function(Pointer<RlDnaReader> reader, Uint16 index)`**: Executes `Function` operation.
- **`Pointer<Utf8> Function(Pointer<RlDnaReader> reader, int index)`**: Executes `Function` operation.
- **`Pointer<RlRigLogic> Function(Pointer<RlDnaReader> reader)`**: Executes `Function` operation.
- **`Pointer<RlRigLogic> Function(Pointer<RlDnaReader> reader)`**: Executes `Function` operation.
- **`Void Function(Pointer<RlRigLogic> rl, Pointer<RlRigInstance> inst)`**: Executes `Function` operation.
- **`void Function(Pointer<RlRigLogic> rl, Pointer<RlRigInstance> inst)`**: Executes `Function` operation.
- **`Pointer<RlRigInstance> Function(Pointer<RlRigLogic> rl)`**: Executes `Function` operation.
- **`Pointer<RlRigInstance> Function(Pointer<RlRigLogic> rl)`**: Executes `Function` operation.
- **`Uint16 Function(Pointer<RlRigInstance> inst)`**: Executes `Function` operation.
- **`int Function(Pointer<RlRigInstance> inst)`**: Executes `Function` operation.
- **`Float Function(Pointer<RlRigInstance> inst, Uint16 index)`**: Executes `Function` operation.
- **`double Function(Pointer<RlRigInstance> inst, int index)`**: Executes `Function` operation.
- **`Void Function(Pointer<RlRigInstance> inst, Uint16 index, Float value)`**: Executes `Function` operation.
- **`void Function(Pointer<RlRigInstance> inst, int index, double value)`**: Executes `Function` operation.
- **`Void Function(Pointer<RlRigInstance> inst, Uint16 lod)`**: Executes `Function` operation.
- **`void Function(Pointer<RlRigInstance> inst, int lod)`**: Executes `Function` operation.
- **`int Function(Pointer<RlRigInstance> inst, Pointer<Pointer<Float>> outData)`**: Executes `Function` operation.

#### `class RlDnaReader`

`RlDnaReader`: `class` representing the data model or functionality of the module.

#### `class RlRigLogic`

`RlRigLogic`: `class` representing the data model or functionality of the module.

#### `class RlRigInstance`

`RlRigInstance`: `class` representing the data model or functionality of the module.

#### `class RigLogicBindings`

`RigLogicBindings`: `class` representing the data model or functionality of the module.

**Constructors:**
- `RigLogicBindings._init()`: Initializes `RigLogicBindings._init()`.

**Functions, Methods & Accessors:**

| Method / Getter | Signature | Purpose & Description |
| :--- | :--- | :--- |
| `dnaReaderCreateFromFile` | `final RlDnaReaderCreateFromFileDart dnaReaderCreateFromFile` | Holds the `dnaReaderCreateFromFile` property or configuration state. |
| `dnaReaderCreateFromMemory` | `final RlDnaReaderCreateFromMemoryDart dnaReaderCreateFromMemory` | Holds the `dnaReaderCreateFromMemory` property or configuration state. |
| `dnaReaderDestroy` | `final RlDnaReaderDestroyDart dnaReaderDestroy` | Holds the `dnaReaderDestroy` property or configuration state. |
| `dnaReaderGetName` | `final RlDnaReaderGetNameDart dnaReaderGetName` | Holds the `dnaReaderGetName` property or configuration state. |
| `dnaReaderGetLodCount` | `final RlDnaReaderGetLodCountDart dnaReaderGetLodCount` | Holds the `dnaReaderGetLodCount` property or configuration state. |
| `dnaReaderGetJointCount` | `final RlDnaReaderGetJointCountDart dnaReaderGetJointCount` | Holds the `dnaReaderGetJointCount` property or configuration state. |
| `dnaReaderGetJointName` | `final RlDnaReaderGetJointNameDart dnaReaderGetJointName` | Holds the `dnaReaderGetJointName` property or configuration state. |
| `dnaReaderGetBlendShapeChannelCount` | `dnaReaderGetBlendShapeChannelCount` | Holds the `dnaReaderGetBlendShapeChannelCount` property or configuration state. |
| `dnaReaderGetBlendShapeChannelName` | `dnaReaderGetBlendShapeChannelName` | Holds the `dnaReaderGetBlendShapeChannelName` property or configuration state. |
| `dnaReaderGetRawControlCount` | `final RlDnaReaderGetRawControlCountDart dnaReaderGetRawControlCount` | Holds the `dnaReaderGetRawControlCount` property or configuration state. |
| `dnaReaderGetRawControlName` | `final RlDnaReaderGetRawControlNameDart dnaReaderGetRawControlName` | Holds the `dnaReaderGetRawControlName` property or configuration state. |
| `dnaReaderGetGuiControlCount` | `final RlDnaReaderGetGuiControlCountDart dnaReaderGetGuiControlCount` | Holds the `dnaReaderGetGuiControlCount` property or configuration state. |
| `dnaReaderGetGuiControlName` | `final RlDnaReaderGetGuiControlNameDart dnaReaderGetGuiControlName` | Holds the `dnaReaderGetGuiControlName` property or configuration state. |
| `dnaReaderGetAnimatedMapCount` | `final RlDnaReaderGetAnimatedMapCountDart dnaReaderGetAnimatedMapCount` | Holds the `dnaReaderGetAnimatedMapCount` property or configuration state. |
| `dnaReaderGetAnimatedMapName` | `final RlDnaReaderGetAnimatedMapNameDart dnaReaderGetAnimatedMapName` | Holds the `dnaReaderGetAnimatedMapName` property or configuration state. |
| `rigLogicCreate` | `final RlRigLogicCreateDart rigLogicCreate` | Holds the `rigLogicCreate` property or configuration state. |
| `rigLogicDestroy` | `final RlRigLogicDestroyDart rigLogicDestroy` | Holds the `rigLogicDestroy` property or configuration state. |
| `rigLogicCalculate` | `final RlRigLogicCalculateDart rigLogicCalculate` | Holds the `rigLogicCalculate` property or configuration state. |
| `rigInstanceCreate` | `final RlRigInstanceCreateDart rigInstanceCreate` | Holds the `rigInstanceCreate` property or configuration state. |
| `rigInstanceDestroy` | `final RlRigInstanceDestroyDart rigInstanceDestroy` | Holds the `rigInstanceDestroy` property or configuration state. |
| `rigInstanceGetRawControlCount` | `final RlRigInstanceGetRawControlCountDart rigInstanceGetRawControlCount` | Holds the `rigInstanceGetRawControlCount` property or configuration state. |
| `rigInstanceGetRawControl` | `final RlRigInstanceGetRawControlDart rigInstanceGetRawControl` | Holds the `rigInstanceGetRawControl` property or configuration state. |
| `rigInstanceSetRawControl` | `final RlRigInstanceSetRawControlDart rigInstanceSetRawControl` | Holds the `rigInstanceSetRawControl` property or configuration state. |
| `rigInstanceGetLod` | `final RlRigInstanceGetLodDart rigInstanceGetLod` | Holds the `rigInstanceGetLod` property or configuration state. |
| `rigInstanceSetLod` | `final RlRigInstanceSetLodDart rigInstanceSetLod` | Holds the `rigInstanceSetLod` property or configuration state. |
| `rigInstanceGetJointOutputs` | `final RlRigInstanceGetOutputsDart rigInstanceGetJointOutputs` | Holds the `rigInstanceGetJointOutputs` property or configuration state. |
| `rigInstanceGetBlendShapeOutputs` | `final RlRigInstanceGetOutputsDart rigInstanceGetBlendShapeOutputs` | Holds the `rigInstanceGetBlendShapeOutputs` property or configuration state. |
| `rigInstanceGetAnimatedMapOutputs` | `final RlRigInstanceGetOutputsDart rigInstanceGetAnimatedMapOutputs` | Holds the `rigInstanceGetAnimatedMapOutputs` property or configuration state. |
| `isAvailable` | `bool get isAvailable` | Checks current state or capability and returns a boolean value. |

### `lib/src/dna_reader.dart`

#### `class DnaReader`

Reads MetaHuman DNA files containing joint hierarchy, blend shape mappings, and rig behavior parameters.

**Constructors:**
- `DnaReader._(this._handle)`: Initializes `DnaReader._(this._handle)`.
- `DnaReader.fromFile(String path)`: Creates a [DnaReader] from a DNA file on disk.
- `DnaReader.fromMemory(Uint8List bytes)`: Creates a [DnaReader] from an in-memory byte buffer.

**Functions, Methods & Accessors:**

| Method / Getter | Signature | Purpose & Description |
| :--- | :--- | :--- |
| `handle` | `Pointer<RlDnaReader> get handle` | Returns the underlying native FFI pointer handle. |
| `name` | `String get name` | Getter accessor returning the current value of `name`. |
| `lodCount` | `int get lodCount` | Getter accessor returning the current value of `lodCount`. |
| `jointCount` | `int get jointCount` | Getter accessor returning the current value of `jointCount`. |
| `getJointName` | `String getJointName(int index)` | Queries and returns the `JointName` value or child object. |
| `blendShapeChannelCount` | `int get blendShapeChannelCount` | Getter accessor returning the current value of `blendShapeChannelCount`. |
| `getBlendShapeChannelName` | `String getBlendShapeChannelName(int index)` | Queries and returns the `BlendShapeChannelName` value or child object. |
| `rawControlCount` | `int get rawControlCount` | Getter accessor returning the current value of `rawControlCount`. |
| `getRawControlName` | `String getRawControlName(int index)` | Queries and returns the `RawControlName` value or child object. |
| `guiControlCount` | `int get guiControlCount` | Getter accessor returning the current value of `guiControlCount`. |
| `getGuiControlName` | `String getGuiControlName(int index)` | Queries and returns the `GuiControlName` value or child object. |
| `animatedMapCount` | `int get animatedMapCount` | Getter accessor returning the current value of `animatedMapCount`. |
| `getAnimatedMapName` | `String getAnimatedMapName(int index)` | Queries and returns the `AnimatedMapName` value or child object. |
| `dispose` | `void dispose()` | Releases native FFI pointers, event subscriptions, and allocated memory. |

### `lib/src/rig_instance.dart`

#### `class RigInstance`

An instance of a rig driven by [RigLogic], containing runtime state, control inputs, and calculated joint transforms and blend shape outputs.

**Constructors:**
- `RigInstance._(this._handle)`: Initializes `RigInstance._(this._handle)`.
- `RigInstance.create(RigLogic rigLogic)`: Initializes `RigInstance.create(RigLogic rigLogic)`.

**Functions, Methods & Accessors:**

| Method / Getter | Signature | Purpose & Description |
| :--- | :--- | :--- |
| `handle` | `Pointer<RlRigInstance> get handle` | Returns the underlying native FFI pointer handle. |
| `rawControlCount` | `int get rawControlCount` | Getter accessor returning the current value of `rawControlCount`. |
| `getRawControl` | `double getRawControl(int index) => RigLogicBindings.instance.rigInstance...` | Queries and returns the `RawControl` value or child object. |
| `setRawControl` | `void setRawControl(int index, double value)` | Updates the `RawControl` parameter and applies changes to the system. |
| `lod` | `int get lod` | Getter accessor returning the current value of `lod`. |
| `lod` | `lod(int value) => RigLogicBindings.instance.rigInstanceSetLod(handle, va...` | Executes `lod` operation. |
| `getJointOutputs` | `List<double> getJointOutputs()` | Queries and returns the `JointOutputs` value or child object. |
| `getBlendShapeOutputs` | `List<double> getBlendShapeOutputs()` | Queries and returns the `BlendShapeOutputs` value or child object. |
| `getAnimatedMapOutputs` | `List<double> getAnimatedMapOutputs()` | Queries and returns the `AnimatedMapOutputs` value or child object. |
| `dispose` | `void dispose()` | Releases native FFI pointers, event subscriptions, and allocated memory. |

### `lib/src/rig_logic.dart`

#### `class RigLogic`

Evaluates MetaHuman facial rigs using machine-learned behavior, PSDs (Pose-Space Deformers), and RBFs.

**Constructors:**
- `RigLogic._(this._handle)`: Initializes `RigLogic._(this._handle)`.
- `RigLogic.create(DnaReader reader)`: Initializes `RigLogic.create(DnaReader reader)`.

**Functions, Methods & Accessors:**

| Method / Getter | Signature | Purpose & Description |
| :--- | :--- | :--- |
| `handle` | `Pointer<RlRigLogic> get handle` | Returns the underlying native FFI pointer handle. |
| `calculate` | `void calculate(RigInstance instance)` | Evaluates inputs and computes deformation, matrix, or bone outputs. |
| `dispose` | `void dispose()` | Releases native FFI pointers, event subscriptions, and allocated memory. |

---

[Previous: flutter_assimp](flutter_assimp.md) | [Up: Lumina tools documentation](../README.md) | [Next: flutter_gstreamer](flutter_gstreamer.md)
