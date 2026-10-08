import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter_riglogic/src/riglogic_native.dart' as native;

// Opaque types
final class RlDnaReader extends Opaque {}

final class RlRigLogic extends Opaque {}

final class RlRigInstance extends Opaque {}

// C function types
typedef RlDnaReaderCreateFromFileC =
    Pointer<RlDnaReader> Function(Pointer<Utf8> path);
typedef RlDnaReaderCreateFromFileDart =
    Pointer<RlDnaReader> Function(Pointer<Utf8> path);

typedef RlDnaReaderCreateFromMemoryC =
    Pointer<RlDnaReader> Function(Pointer<Uint8> data, IntPtr size);
typedef RlDnaReaderCreateFromMemoryDart =
    Pointer<RlDnaReader> Function(Pointer<Uint8> data, int size);

typedef RlDnaReaderDestroyC = Void Function(Pointer<RlDnaReader> reader);
typedef RlDnaReaderDestroyDart = void Function(Pointer<RlDnaReader> reader);

typedef RlDnaReaderGetNameC =
    Pointer<Utf8> Function(Pointer<RlDnaReader> reader);
typedef RlDnaReaderGetNameDart =
    Pointer<Utf8> Function(Pointer<RlDnaReader> reader);

typedef RlDnaReaderGetLodCountC = Uint16 Function(Pointer<RlDnaReader> reader);
typedef RlDnaReaderGetLodCountDart = int Function(Pointer<RlDnaReader> reader);

typedef RlDnaReaderGetJointCountC =
    Uint16 Function(Pointer<RlDnaReader> reader);
typedef RlDnaReaderGetJointCountDart =
    int Function(Pointer<RlDnaReader> reader);

typedef RlDnaReaderGetJointNameC =
    Pointer<Utf8> Function(Pointer<RlDnaReader> reader, Uint16 index);
typedef RlDnaReaderGetJointNameDart =
    Pointer<Utf8> Function(Pointer<RlDnaReader> reader, int index);

typedef RlDnaReaderGetBlendShapeChannelCountC =
    Uint16 Function(Pointer<RlDnaReader> reader);
typedef RlDnaReaderGetBlendShapeChannelCountDart =
    int Function(Pointer<RlDnaReader> reader);

typedef RlDnaReaderGetBlendShapeChannelNameC =
    Pointer<Utf8> Function(Pointer<RlDnaReader> reader, Uint16 index);
typedef RlDnaReaderGetBlendShapeChannelNameDart =
    Pointer<Utf8> Function(Pointer<RlDnaReader> reader, int index);

typedef RlDnaReaderGetRawControlCountC =
    Uint16 Function(Pointer<RlDnaReader> reader);
typedef RlDnaReaderGetRawControlCountDart =
    int Function(Pointer<RlDnaReader> reader);

typedef RlDnaReaderGetRawControlNameC =
    Pointer<Utf8> Function(Pointer<RlDnaReader> reader, Uint16 index);
typedef RlDnaReaderGetRawControlNameDart =
    Pointer<Utf8> Function(Pointer<RlDnaReader> reader, int index);

typedef RlDnaReaderGetGuiControlCountC =
    Uint16 Function(Pointer<RlDnaReader> reader);
typedef RlDnaReaderGetGuiControlCountDart =
    int Function(Pointer<RlDnaReader> reader);

typedef RlDnaReaderGetGuiControlNameC =
    Pointer<Utf8> Function(Pointer<RlDnaReader> reader, Uint16 index);
typedef RlDnaReaderGetGuiControlNameDart =
    Pointer<Utf8> Function(Pointer<RlDnaReader> reader, int index);

typedef RlDnaReaderGetAnimatedMapCountC =
    Uint16 Function(Pointer<RlDnaReader> reader);
typedef RlDnaReaderGetAnimatedMapCountDart =
    int Function(Pointer<RlDnaReader> reader);

typedef RlDnaReaderGetAnimatedMapNameC =
    Pointer<Utf8> Function(Pointer<RlDnaReader> reader, Uint16 index);
typedef RlDnaReaderGetAnimatedMapNameDart =
    Pointer<Utf8> Function(Pointer<RlDnaReader> reader, int index);

// RigLogic functions
typedef RlRigLogicCreateC =
    Pointer<RlRigLogic> Function(Pointer<RlDnaReader> reader);
typedef RlRigLogicCreateDart =
    Pointer<RlRigLogic> Function(Pointer<RlDnaReader> reader);

typedef RlRigLogicDestroyC = Void Function(Pointer<RlRigLogic> rl);
typedef RlRigLogicDestroyDart = void Function(Pointer<RlRigLogic> rl);

typedef RlRigLogicCalculateC =
    Void Function(Pointer<RlRigLogic> rl, Pointer<RlRigInstance> inst);
typedef RlRigLogicCalculateDart =
    void Function(Pointer<RlRigLogic> rl, Pointer<RlRigInstance> inst);

// RigInstance functions
typedef RlRigInstanceCreateC =
    Pointer<RlRigInstance> Function(Pointer<RlRigLogic> rl);
typedef RlRigInstanceCreateDart =
    Pointer<RlRigInstance> Function(Pointer<RlRigLogic> rl);

typedef RlRigInstanceDestroyC = Void Function(Pointer<RlRigInstance> inst);
typedef RlRigInstanceDestroyDart = void Function(Pointer<RlRigInstance> inst);

typedef RlRigInstanceGetRawControlCountC =
    Uint16 Function(Pointer<RlRigInstance> inst);
typedef RlRigInstanceGetRawControlCountDart =
    int Function(Pointer<RlRigInstance> inst);

typedef RlRigInstanceGetRawControlC =
    Float Function(Pointer<RlRigInstance> inst, Uint16 index);
typedef RlRigInstanceGetRawControlDart =
    double Function(Pointer<RlRigInstance> inst, int index);

typedef RlRigInstanceSetRawControlC =
    Void Function(Pointer<RlRigInstance> inst, Uint16 index, Float value);
typedef RlRigInstanceSetRawControlDart =
    void Function(Pointer<RlRigInstance> inst, int index, double value);

typedef RlRigInstanceGetLodC = Uint16 Function(Pointer<RlRigInstance> inst);
typedef RlRigInstanceGetLodDart = int Function(Pointer<RlRigInstance> inst);

typedef RlRigInstanceSetLodC =
    Void Function(Pointer<RlRigInstance> inst, Uint16 lod);
typedef RlRigInstanceSetLodDart =
    void Function(Pointer<RlRigInstance> inst, int lod);

typedef RlRigInstanceGetOutputsC =
    Uint32 Function(
      Pointer<RlRigInstance> inst,
      Pointer<Pointer<Float>> outData,
    );
typedef RlRigInstanceGetOutputsDart =
    int Function(Pointer<RlRigInstance> inst, Pointer<Pointer<Float>> outData);

class RigLogicBindings {
  static final RigLogicBindings instance = RigLogicBindings._init();

  bool _isAvailable = false;

  late final RlDnaReaderCreateFromFileDart dnaReaderCreateFromFile;
  late final RlDnaReaderCreateFromMemoryDart dnaReaderCreateFromMemory;
  late final RlDnaReaderDestroyDart dnaReaderDestroy;
  late final RlDnaReaderGetNameDart dnaReaderGetName;
  late final RlDnaReaderGetLodCountDart dnaReaderGetLodCount;
  late final RlDnaReaderGetJointCountDart dnaReaderGetJointCount;
  late final RlDnaReaderGetJointNameDart dnaReaderGetJointName;
  late final RlDnaReaderGetBlendShapeChannelCountDart
  dnaReaderGetBlendShapeChannelCount;
  late final RlDnaReaderGetBlendShapeChannelNameDart
  dnaReaderGetBlendShapeChannelName;
  late final RlDnaReaderGetRawControlCountDart dnaReaderGetRawControlCount;
  late final RlDnaReaderGetRawControlNameDart dnaReaderGetRawControlName;
  late final RlDnaReaderGetGuiControlCountDart dnaReaderGetGuiControlCount;
  late final RlDnaReaderGetGuiControlNameDart dnaReaderGetGuiControlName;
  late final RlDnaReaderGetAnimatedMapCountDart dnaReaderGetAnimatedMapCount;
  late final RlDnaReaderGetAnimatedMapNameDart dnaReaderGetAnimatedMapName;

  late final RlRigLogicCreateDart rigLogicCreate;
  late final RlRigLogicDestroyDart rigLogicDestroy;
  late final RlRigLogicCalculateDart rigLogicCalculate;

  late final RlRigInstanceCreateDart rigInstanceCreate;
  late final RlRigInstanceDestroyDart rigInstanceDestroy;
  late final RlRigInstanceGetRawControlCountDart rigInstanceGetRawControlCount;
  late final RlRigInstanceGetRawControlDart rigInstanceGetRawControl;
  late final RlRigInstanceSetRawControlDart rigInstanceSetRawControl;
  late final RlRigInstanceGetLodDart rigInstanceGetLod;
  late final RlRigInstanceSetLodDart rigInstanceSetLod;
  late final RlRigInstanceGetOutputsDart rigInstanceGetJointOutputs;
  late final RlRigInstanceGetOutputsDart rigInstanceGetBlendShapeOutputs;
  late final RlRigInstanceGetOutputsDart rigInstanceGetAnimatedMapOutputs;

  bool get isAvailable => _isAvailable;

  RigLogicBindings._init() {
    if (_bindNativeAssets()) return;
    _bindDynamicLibrary();
  }

  /// Binds the `@Native` functions of the code asset the package's
  /// native-assets hook builds. False when the asset is not bundled (a host
  /// that runs without native assets).
  bool _bindNativeAssets() {
    try {
      // Throws when the asset is not bundled.
      native.dnaReaderGetName(nullptr);
    } catch (_) {
      return false;
    }
    dnaReaderCreateFromFile = (path) => native.dnaReaderCreateFromFile(path);
    dnaReaderCreateFromMemory = (data, size) =>
        native.dnaReaderCreateFromMemory(data, size);
    dnaReaderDestroy = (reader) => native.dnaReaderDestroy(reader);
    dnaReaderGetName = (reader) => native.dnaReaderGetName(reader);
    dnaReaderGetLodCount = (reader) => native.dnaReaderGetLodCount(reader);
    dnaReaderGetJointCount = (reader) => native.dnaReaderGetJointCount(reader);
    dnaReaderGetJointName = (reader, index) =>
        native.dnaReaderGetJointName(reader, index);
    dnaReaderGetBlendShapeChannelCount = (reader) =>
        native.dnaReaderGetBlendShapeChannelCount(reader);
    dnaReaderGetBlendShapeChannelName = (reader, index) =>
        native.dnaReaderGetBlendShapeChannelName(reader, index);
    dnaReaderGetRawControlCount = (reader) =>
        native.dnaReaderGetRawControlCount(reader);
    dnaReaderGetRawControlName = (reader, index) =>
        native.dnaReaderGetRawControlName(reader, index);
    dnaReaderGetGuiControlCount = (reader) =>
        native.dnaReaderGetGuiControlCount(reader);
    dnaReaderGetGuiControlName = (reader, index) =>
        native.dnaReaderGetGuiControlName(reader, index);
    dnaReaderGetAnimatedMapCount = (reader) =>
        native.dnaReaderGetAnimatedMapCount(reader);
    dnaReaderGetAnimatedMapName = (reader, index) =>
        native.dnaReaderGetAnimatedMapName(reader, index);
    rigLogicCreate = (reader) => native.riglogicCreate(reader);
    rigLogicDestroy = (rl) => native.riglogicDestroy(rl);
    rigLogicCalculate = (rl, inst) => native.riglogicCalculate(rl, inst);
    rigInstanceCreate = (rl) => native.riginstanceCreate(rl);
    rigInstanceDestroy = (inst) => native.riginstanceDestroy(inst);
    rigInstanceGetRawControlCount = (inst) =>
        native.riginstanceGetRawControlCount(inst);
    rigInstanceGetRawControl = (inst, index) =>
        native.riginstanceGetRawControl(inst, index);
    rigInstanceSetRawControl = (inst, index, value) =>
        native.riginstanceSetRawControl(inst, index, value);
    rigInstanceGetLod = (inst) => native.riginstanceGetLod(inst);
    rigInstanceSetLod = (inst, lod) => native.riginstanceSetLod(inst, lod);
    rigInstanceGetJointOutputs = (inst, outData) =>
        native.riginstanceGetJointOutputs(inst, outData);
    rigInstanceGetBlendShapeOutputs = (inst, outData) =>
        native.riginstanceGetBlendShapeOutputs(inst, outData);
    rigInstanceGetAnimatedMapOutputs = (inst, outData) =>
        native.riginstanceGetAnimatedMapOutputs(inst, outData);
    _isAvailable = true;
    return true;
  }

  /// Opens a prebuilt `flutter_riglogic` library by path.
  void _bindDynamicLibrary() {
    try {
      final dylib = _loadDynamicLibrary();
      dnaReaderCreateFromFile = dylib
          .lookupFunction<
            RlDnaReaderCreateFromFileC,
            RlDnaReaderCreateFromFileDart
          >('rl_dna_reader_create_from_file');
      dnaReaderCreateFromMemory = dylib
          .lookupFunction<
            RlDnaReaderCreateFromMemoryC,
            RlDnaReaderCreateFromMemoryDart
          >('rl_dna_reader_create_from_memory');
      dnaReaderDestroy = dylib
          .lookupFunction<RlDnaReaderDestroyC, RlDnaReaderDestroyDart>(
            'rl_dna_reader_destroy',
          );
      dnaReaderGetName = dylib
          .lookupFunction<RlDnaReaderGetNameC, RlDnaReaderGetNameDart>(
            'rl_dna_reader_get_name',
          );
      dnaReaderGetLodCount = dylib
          .lookupFunction<RlDnaReaderGetLodCountC, RlDnaReaderGetLodCountDart>(
            'rl_dna_reader_get_lod_count',
          );
      dnaReaderGetJointCount = dylib
          .lookupFunction<
            RlDnaReaderGetJointCountC,
            RlDnaReaderGetJointCountDart
          >('rl_dna_reader_get_joint_count');
      dnaReaderGetJointName = dylib
          .lookupFunction<
            RlDnaReaderGetJointNameC,
            RlDnaReaderGetJointNameDart
          >('rl_dna_reader_get_joint_name');
      dnaReaderGetBlendShapeChannelCount = dylib
          .lookupFunction<
            RlDnaReaderGetBlendShapeChannelCountC,
            RlDnaReaderGetBlendShapeChannelCountDart
          >('rl_dna_reader_get_blend_shape_channel_count');
      dnaReaderGetBlendShapeChannelName = dylib
          .lookupFunction<
            RlDnaReaderGetBlendShapeChannelNameC,
            RlDnaReaderGetBlendShapeChannelNameDart
          >('rl_dna_reader_get_blend_shape_channel_name');
      dnaReaderGetRawControlCount = dylib
          .lookupFunction<
            RlDnaReaderGetRawControlCountC,
            RlDnaReaderGetRawControlCountDart
          >('rl_dna_reader_get_raw_control_count');
      dnaReaderGetRawControlName = dylib
          .lookupFunction<
            RlDnaReaderGetRawControlNameC,
            RlDnaReaderGetRawControlNameDart
          >('rl_dna_reader_get_raw_control_name');
      dnaReaderGetGuiControlCount = dylib
          .lookupFunction<
            RlDnaReaderGetGuiControlCountC,
            RlDnaReaderGetGuiControlCountDart
          >('rl_dna_reader_get_gui_control_count');
      dnaReaderGetGuiControlName = dylib
          .lookupFunction<
            RlDnaReaderGetGuiControlNameC,
            RlDnaReaderGetGuiControlNameDart
          >('rl_dna_reader_get_gui_control_name');
      dnaReaderGetAnimatedMapCount = dylib
          .lookupFunction<
            RlDnaReaderGetAnimatedMapCountC,
            RlDnaReaderGetAnimatedMapCountDart
          >('rl_dna_reader_get_animated_map_count');
      dnaReaderGetAnimatedMapName = dylib
          .lookupFunction<
            RlDnaReaderGetAnimatedMapNameC,
            RlDnaReaderGetAnimatedMapNameDart
          >('rl_dna_reader_get_animated_map_name');

      rigLogicCreate = dylib
          .lookupFunction<RlRigLogicCreateC, RlRigLogicCreateDart>(
            'rl_riglogic_create',
          );
      rigLogicDestroy = dylib
          .lookupFunction<RlRigLogicDestroyC, RlRigLogicDestroyDart>(
            'rl_riglogic_destroy',
          );
      rigLogicCalculate = dylib
          .lookupFunction<RlRigLogicCalculateC, RlRigLogicCalculateDart>(
            'rl_riglogic_calculate',
          );

      rigInstanceCreate = dylib
          .lookupFunction<RlRigInstanceCreateC, RlRigInstanceCreateDart>(
            'rl_riginstance_create',
          );
      rigInstanceDestroy = dylib
          .lookupFunction<RlRigInstanceDestroyC, RlRigInstanceDestroyDart>(
            'rl_riginstance_destroy',
          );
      rigInstanceGetRawControlCount = dylib
          .lookupFunction<
            RlRigInstanceGetRawControlCountC,
            RlRigInstanceGetRawControlCountDart
          >('rl_riginstance_get_raw_control_count');
      rigInstanceGetRawControl = dylib
          .lookupFunction<
            RlRigInstanceGetRawControlC,
            RlRigInstanceGetRawControlDart
          >('rl_riginstance_get_raw_control');
      rigInstanceSetRawControl = dylib
          .lookupFunction<
            RlRigInstanceSetRawControlC,
            RlRigInstanceSetRawControlDart
          >('rl_riginstance_set_raw_control');
      rigInstanceGetLod = dylib
          .lookupFunction<RlRigInstanceGetLodC, RlRigInstanceGetLodDart>(
            'rl_riginstance_get_lod',
          );
      rigInstanceSetLod = dylib
          .lookupFunction<RlRigInstanceSetLodC, RlRigInstanceSetLodDart>(
            'rl_riginstance_set_lod',
          );
      rigInstanceGetJointOutputs = dylib
          .lookupFunction<
            RlRigInstanceGetOutputsC,
            RlRigInstanceGetOutputsDart
          >('rl_riginstance_get_joint_outputs');
      rigInstanceGetBlendShapeOutputs = dylib
          .lookupFunction<
            RlRigInstanceGetOutputsC,
            RlRigInstanceGetOutputsDart
          >('rl_riginstance_get_blend_shape_outputs');
      rigInstanceGetAnimatedMapOutputs = dylib
          .lookupFunction<
            RlRigInstanceGetOutputsC,
            RlRigInstanceGetOutputsDart
          >('rl_riginstance_get_animated_map_outputs');

      _isAvailable = true;
    } catch (e) {
      _isAvailable = false;
    }
  }

  static DynamicLibrary _loadDynamicLibrary() {
    if (Platform.isLinux) {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final candidates = [
        '$exeDir/lib/libflutter_riglogic.so',
        '$exeDir/libflutter_riglogic.so',
        'libflutter_riglogic.so',
        'lib/libflutter_riglogic.so',
        '../flutter_riglogic/lib/libflutter_riglogic.so',
        '../../flutter_riglogic/lib/libflutter_riglogic.so',
        'flutter_riglogic/lib/libflutter_riglogic.so',
      ];
      for (final path in candidates) {
        try {
          return DynamicLibrary.open(path);
        } catch (_) {}
      }
      return DynamicLibrary.process();
    } else if (Platform.isMacOS) {
      final candidates = [
        'libflutter_riglogic.dylib',
        'lib/libflutter_riglogic.dylib',
      ];
      for (final path in candidates) {
        try {
          return DynamicLibrary.open(path);
        } catch (_) {}
      }
      return DynamicLibrary.process();
    } else if (Platform.isWindows) {
      final candidates = ['flutter_riglogic.dll', 'lib/flutter_riglogic.dll'];
      for (final path in candidates) {
        try {
          return DynamicLibrary.open(path);
        } catch (_) {}
      }
      return DynamicLibrary.process();
    }
    return DynamicLibrary.process();
  }
}
