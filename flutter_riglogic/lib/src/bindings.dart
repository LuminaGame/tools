import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

// Opaque types
final class RlDnaReader extends Opaque {}
final class RlRigLogic extends Opaque {}
final class RlRigInstance extends Opaque {}

// C function types
typedef RlDnaReaderCreateFromFileC = Pointer<RlDnaReader> Function(Pointer<Utf8> path);
typedef RlDnaReaderCreateFromFileDart = Pointer<RlDnaReader> Function(Pointer<Utf8> path);

typedef RlDnaReaderCreateFromMemoryC = Pointer<RlDnaReader> Function(Pointer<Uint8> data, IntPtr size);
typedef RlDnaReaderCreateFromMemoryDart = Pointer<RlDnaReader> Function(Pointer<Uint8> data, int size);

typedef RlDnaReaderDestroyC = Void Function(Pointer<RlDnaReader> reader);
typedef RlDnaReaderDestroyDart = void Function(Pointer<RlDnaReader> reader);

typedef RlDnaReaderGetNameC = Pointer<Utf8> Function(Pointer<RlDnaReader> reader);
typedef RlDnaReaderGetNameDart = Pointer<Utf8> Function(Pointer<RlDnaReader> reader);

typedef RlDnaReaderGetLodCountC = Uint16 Function(Pointer<RlDnaReader> reader);
typedef RlDnaReaderGetLodCountDart = int Function(Pointer<RlDnaReader> reader);

typedef RlDnaReaderGetJointCountC = Uint16 Function(Pointer<RlDnaReader> reader);
typedef RlDnaReaderGetJointCountDart = int Function(Pointer<RlDnaReader> reader);

typedef RlDnaReaderGetJointNameC = Pointer<Utf8> Function(Pointer<RlDnaReader> reader, Uint16 index);
typedef RlDnaReaderGetJointNameDart = Pointer<Utf8> Function(Pointer<RlDnaReader> reader, int index);

typedef RlDnaReaderGetBlendShapeChannelCountC = Uint16 Function(Pointer<RlDnaReader> reader);
typedef RlDnaReaderGetBlendShapeChannelCountDart = int Function(Pointer<RlDnaReader> reader);

typedef RlDnaReaderGetBlendShapeChannelNameC = Pointer<Utf8> Function(Pointer<RlDnaReader> reader, Uint16 index);
typedef RlDnaReaderGetBlendShapeChannelNameDart = Pointer<Utf8> Function(Pointer<RlDnaReader> reader, int index);

typedef RlDnaReaderGetRawControlCountC = Uint16 Function(Pointer<RlDnaReader> reader);
typedef RlDnaReaderGetRawControlCountDart = int Function(Pointer<RlDnaReader> reader);

typedef RlDnaReaderGetRawControlNameC = Pointer<Utf8> Function(Pointer<RlDnaReader> reader, Uint16 index);
typedef RlDnaReaderGetRawControlNameDart = Pointer<Utf8> Function(Pointer<RlDnaReader> reader, int index);

typedef RlDnaReaderGetGuiControlCountC = Uint16 Function(Pointer<RlDnaReader> reader);
typedef RlDnaReaderGetGuiControlCountDart = int Function(Pointer<RlDnaReader> reader);

typedef RlDnaReaderGetGuiControlNameC = Pointer<Utf8> Function(Pointer<RlDnaReader> reader, Uint16 index);
typedef RlDnaReaderGetGuiControlNameDart = Pointer<Utf8> Function(Pointer<RlDnaReader> reader, int index);

typedef RlDnaReaderGetAnimatedMapCountC = Uint16 Function(Pointer<RlDnaReader> reader);
typedef RlDnaReaderGetAnimatedMapCountDart = int Function(Pointer<RlDnaReader> reader);

typedef RlDnaReaderGetAnimatedMapNameC = Pointer<Utf8> Function(Pointer<RlDnaReader> reader, Uint16 index);
typedef RlDnaReaderGetAnimatedMapNameDart = Pointer<Utf8> Function(Pointer<RlDnaReader> reader, int index);

// RigLogic functions
typedef RlRigLogicCreateC = Pointer<RlRigLogic> Function(Pointer<RlDnaReader> reader);
typedef RlRigLogicCreateDart = Pointer<RlRigLogic> Function(Pointer<RlDnaReader> reader);

typedef RlRigLogicDestroyC = Void Function(Pointer<RlRigLogic> rl);
typedef RlRigLogicDestroyDart = void Function(Pointer<RlRigLogic> rl);

typedef RlRigLogicCalculateC = Void Function(Pointer<RlRigLogic> rl, Pointer<RlRigInstance> inst);
typedef RlRigLogicCalculateDart = void Function(Pointer<RlRigLogic> rl, Pointer<RlRigInstance> inst);

// RigInstance functions
typedef RlRigInstanceCreateC = Pointer<RlRigInstance> Function(Pointer<RlRigLogic> rl);
typedef RlRigInstanceCreateDart = Pointer<RlRigInstance> Function(Pointer<RlRigLogic> rl);

typedef RlRigInstanceDestroyC = Void Function(Pointer<RlRigInstance> inst);
typedef RlRigInstanceDestroyDart = void Function(Pointer<RlRigInstance> inst);

typedef RlRigInstanceGetRawControlCountC = Uint16 Function(Pointer<RlRigInstance> inst);
typedef RlRigInstanceGetRawControlCountDart = int Function(Pointer<RlRigInstance> inst);

typedef RlRigInstanceGetRawControlC = Float Function(Pointer<RlRigInstance> inst, Uint16 index);
typedef RlRigInstanceGetRawControlDart = double Function(Pointer<RlRigInstance> inst, int index);

typedef RlRigInstanceSetRawControlC = Void Function(Pointer<RlRigInstance> inst, Uint16 index, Float value);
typedef RlRigInstanceSetRawControlDart = void Function(Pointer<RlRigInstance> inst, int index, double value);

typedef RlRigInstanceGetLodC = Uint16 Function(Pointer<RlRigInstance> inst);
typedef RlRigInstanceGetLodDart = int Function(Pointer<RlRigInstance> inst);

typedef RlRigInstanceSetLodC = Void Function(Pointer<RlRigInstance> inst, Uint16 lod);
typedef RlRigInstanceSetLodDart = void Function(Pointer<RlRigInstance> inst, int lod);

typedef RlRigInstanceGetOutputsC = Uint32 Function(Pointer<RlRigInstance> inst, Pointer<Pointer<Float>> outData);
typedef RlRigInstanceGetOutputsDart = int Function(Pointer<RlRigInstance> inst, Pointer<Pointer<Float>> outData);

class RigLogicBindings {
  static final RigLogicBindings instance = RigLogicBindings._init();

  late final DynamicLibrary _dylib;
  bool _isAvailable = false;

  late final RlDnaReaderCreateFromFileDart dnaReaderCreateFromFile;
  late final RlDnaReaderCreateFromMemoryDart dnaReaderCreateFromMemory;
  late final RlDnaReaderDestroyDart dnaReaderDestroy;
  late final RlDnaReaderGetNameDart dnaReaderGetName;
  late final RlDnaReaderGetLodCountDart dnaReaderGetLodCount;
  late final RlDnaReaderGetJointCountDart dnaReaderGetJointCount;
  late final RlDnaReaderGetJointNameDart dnaReaderGetJointName;
  late final RlDnaReaderGetBlendShapeChannelCountDart dnaReaderGetBlendShapeChannelCount;
  late final RlDnaReaderGetBlendShapeChannelNameDart dnaReaderGetBlendShapeChannelName;
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
    try {
      _dylib = _loadDynamicLibrary();
      dnaReaderCreateFromFile = _dylib.lookupFunction<RlDnaReaderCreateFromFileC, RlDnaReaderCreateFromFileDart>('rl_dna_reader_create_from_file');
      dnaReaderCreateFromMemory = _dylib.lookupFunction<RlDnaReaderCreateFromMemoryC, RlDnaReaderCreateFromMemoryDart>('rl_dna_reader_create_from_memory');
      dnaReaderDestroy = _dylib.lookupFunction<RlDnaReaderDestroyC, RlDnaReaderDestroyDart>('rl_dna_reader_destroy');
      dnaReaderGetName = _dylib.lookupFunction<RlDnaReaderGetNameC, RlDnaReaderGetNameDart>('rl_dna_reader_get_name');
      dnaReaderGetLodCount = _dylib.lookupFunction<RlDnaReaderGetLodCountC, RlDnaReaderGetLodCountDart>('rl_dna_reader_get_lod_count');
      dnaReaderGetJointCount = _dylib.lookupFunction<RlDnaReaderGetJointCountC, RlDnaReaderGetJointCountDart>('rl_dna_reader_get_joint_count');
      dnaReaderGetJointName = _dylib.lookupFunction<RlDnaReaderGetJointNameC, RlDnaReaderGetJointNameDart>('rl_dna_reader_get_joint_name');
      dnaReaderGetBlendShapeChannelCount = _dylib.lookupFunction<RlDnaReaderGetBlendShapeChannelCountC, RlDnaReaderGetBlendShapeChannelCountDart>('rl_dna_reader_get_blend_shape_channel_count');
      dnaReaderGetBlendShapeChannelName = _dylib.lookupFunction<RlDnaReaderGetBlendShapeChannelNameC, RlDnaReaderGetBlendShapeChannelNameDart>('rl_dna_reader_get_blend_shape_channel_name');
      dnaReaderGetRawControlCount = _dylib.lookupFunction<RlDnaReaderGetRawControlCountC, RlDnaReaderGetRawControlCountDart>('rl_dna_reader_get_raw_control_count');
      dnaReaderGetRawControlName = _dylib.lookupFunction<RlDnaReaderGetRawControlNameC, RlDnaReaderGetRawControlNameDart>('rl_dna_reader_get_raw_control_name');
      dnaReaderGetGuiControlCount = _dylib.lookupFunction<RlDnaReaderGetGuiControlCountC, RlDnaReaderGetGuiControlCountDart>('rl_dna_reader_get_gui_control_count');
      dnaReaderGetGuiControlName = _dylib.lookupFunction<RlDnaReaderGetGuiControlNameC, RlDnaReaderGetGuiControlNameDart>('rl_dna_reader_get_gui_control_name');
      dnaReaderGetAnimatedMapCount = _dylib.lookupFunction<RlDnaReaderGetAnimatedMapCountC, RlDnaReaderGetAnimatedMapCountDart>('rl_dna_reader_get_animated_map_count');
      dnaReaderGetAnimatedMapName = _dylib.lookupFunction<RlDnaReaderGetAnimatedMapNameC, RlDnaReaderGetAnimatedMapNameDart>('rl_dna_reader_get_animated_map_name');

      rigLogicCreate = _dylib.lookupFunction<RlRigLogicCreateC, RlRigLogicCreateDart>('rl_riglogic_create');
      rigLogicDestroy = _dylib.lookupFunction<RlRigLogicDestroyC, RlRigLogicDestroyDart>('rl_riglogic_destroy');
      rigLogicCalculate = _dylib.lookupFunction<RlRigLogicCalculateC, RlRigLogicCalculateDart>('rl_riglogic_calculate');

      rigInstanceCreate = _dylib.lookupFunction<RlRigInstanceCreateC, RlRigInstanceCreateDart>('rl_riginstance_create');
      rigInstanceDestroy = _dylib.lookupFunction<RlRigInstanceDestroyC, RlRigInstanceDestroyDart>('rl_riginstance_destroy');
      rigInstanceGetRawControlCount = _dylib.lookupFunction<RlRigInstanceGetRawControlCountC, RlRigInstanceGetRawControlCountDart>('rl_riginstance_get_raw_control_count');
      rigInstanceGetRawControl = _dylib.lookupFunction<RlRigInstanceGetRawControlC, RlRigInstanceGetRawControlDart>('rl_riginstance_get_raw_control');
      rigInstanceSetRawControl = _dylib.lookupFunction<RlRigInstanceSetRawControlC, RlRigInstanceSetRawControlDart>('rl_riginstance_set_raw_control');
      rigInstanceGetLod = _dylib.lookupFunction<RlRigInstanceGetLodC, RlRigInstanceGetLodDart>('rl_riginstance_get_lod');
      rigInstanceSetLod = _dylib.lookupFunction<RlRigInstanceSetLodC, RlRigInstanceSetLodDart>('rl_riginstance_set_lod');
      rigInstanceGetJointOutputs = _dylib.lookupFunction<RlRigInstanceGetOutputsC, RlRigInstanceGetOutputsDart>('rl_riginstance_get_joint_outputs');
      rigInstanceGetBlendShapeOutputs = _dylib.lookupFunction<RlRigInstanceGetOutputsC, RlRigInstanceGetOutputsDart>('rl_riginstance_get_blend_shape_outputs');
      rigInstanceGetAnimatedMapOutputs = _dylib.lookupFunction<RlRigInstanceGetOutputsC, RlRigInstanceGetOutputsDart>('rl_riginstance_get_animated_map_outputs');

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
      final candidates = [
        'flutter_riglogic.dll',
        'lib/flutter_riglogic.dll',
      ];
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

