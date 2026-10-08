/// `@Native` bindings to the C API in `src/riglogic_c.h`, resolved against
/// the code asset the package's native-assets hook builds
/// (`package:flutter_riglogic/src/riglogic_native.dart`).
///
/// Use them through `RigLogicBindings`, which falls back to opening the
/// library by path when the host runs without native assets.
library;

import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter_riglogic/src/bindings.dart';

@Native<Pointer<RlDnaReader> Function(Pointer<Utf8>)>(
  symbol: 'rl_dna_reader_create_from_file',
)
external Pointer<RlDnaReader> dnaReaderCreateFromFile(Pointer<Utf8> path);

@Native<Pointer<RlDnaReader> Function(Pointer<Uint8>, Size)>(
  symbol: 'rl_dna_reader_create_from_memory',
)
external Pointer<RlDnaReader> dnaReaderCreateFromMemory(
  Pointer<Uint8> data,
  int size,
);

@Native<Void Function(Pointer<RlDnaReader>)>(symbol: 'rl_dna_reader_destroy')
external void dnaReaderDestroy(Pointer<RlDnaReader> reader);

@Native<Pointer<Utf8> Function(Pointer<RlDnaReader>)>(
  symbol: 'rl_dna_reader_get_name',
)
external Pointer<Utf8> dnaReaderGetName(Pointer<RlDnaReader> reader);

@Native<Uint16 Function(Pointer<RlDnaReader>)>(
  symbol: 'rl_dna_reader_get_lod_count',
)
external int dnaReaderGetLodCount(Pointer<RlDnaReader> reader);

@Native<Uint16 Function(Pointer<RlDnaReader>)>(
  symbol: 'rl_dna_reader_get_joint_count',
)
external int dnaReaderGetJointCount(Pointer<RlDnaReader> reader);

@Native<Pointer<Utf8> Function(Pointer<RlDnaReader>, Uint16)>(
  symbol: 'rl_dna_reader_get_joint_name',
)
external Pointer<Utf8> dnaReaderGetJointName(
  Pointer<RlDnaReader> reader,
  int index,
);

@Native<Uint16 Function(Pointer<RlDnaReader>)>(
  symbol: 'rl_dna_reader_get_blend_shape_channel_count',
)
external int dnaReaderGetBlendShapeChannelCount(Pointer<RlDnaReader> reader);

@Native<Pointer<Utf8> Function(Pointer<RlDnaReader>, Uint16)>(
  symbol: 'rl_dna_reader_get_blend_shape_channel_name',
)
external Pointer<Utf8> dnaReaderGetBlendShapeChannelName(
  Pointer<RlDnaReader> reader,
  int index,
);

@Native<Uint16 Function(Pointer<RlDnaReader>)>(
  symbol: 'rl_dna_reader_get_raw_control_count',
)
external int dnaReaderGetRawControlCount(Pointer<RlDnaReader> reader);

@Native<Pointer<Utf8> Function(Pointer<RlDnaReader>, Uint16)>(
  symbol: 'rl_dna_reader_get_raw_control_name',
)
external Pointer<Utf8> dnaReaderGetRawControlName(
  Pointer<RlDnaReader> reader,
  int index,
);

@Native<Uint16 Function(Pointer<RlDnaReader>)>(
  symbol: 'rl_dna_reader_get_gui_control_count',
)
external int dnaReaderGetGuiControlCount(Pointer<RlDnaReader> reader);

@Native<Pointer<Utf8> Function(Pointer<RlDnaReader>, Uint16)>(
  symbol: 'rl_dna_reader_get_gui_control_name',
)
external Pointer<Utf8> dnaReaderGetGuiControlName(
  Pointer<RlDnaReader> reader,
  int index,
);

@Native<Uint16 Function(Pointer<RlDnaReader>)>(
  symbol: 'rl_dna_reader_get_animated_map_count',
)
external int dnaReaderGetAnimatedMapCount(Pointer<RlDnaReader> reader);

@Native<Pointer<Utf8> Function(Pointer<RlDnaReader>, Uint16)>(
  symbol: 'rl_dna_reader_get_animated_map_name',
)
external Pointer<Utf8> dnaReaderGetAnimatedMapName(
  Pointer<RlDnaReader> reader,
  int index,
);

@Native<Pointer<RlRigLogic> Function(Pointer<RlDnaReader>)>(
  symbol: 'rl_riglogic_create',
)
external Pointer<RlRigLogic> riglogicCreate(Pointer<RlDnaReader> reader);

@Native<Void Function(Pointer<RlRigLogic>)>(symbol: 'rl_riglogic_destroy')
external void riglogicDestroy(Pointer<RlRigLogic> rl);

@Native<Void Function(Pointer<RlRigLogic>, Pointer<RlRigInstance>)>(
  symbol: 'rl_riglogic_calculate',
)
external void riglogicCalculate(
  Pointer<RlRigLogic> rl,
  Pointer<RlRigInstance> inst,
);

@Native<Pointer<RlRigInstance> Function(Pointer<RlRigLogic>)>(
  symbol: 'rl_riginstance_create',
)
external Pointer<RlRigInstance> riginstanceCreate(Pointer<RlRigLogic> rl);

@Native<Void Function(Pointer<RlRigInstance>)>(symbol: 'rl_riginstance_destroy')
external void riginstanceDestroy(Pointer<RlRigInstance> inst);

@Native<Uint16 Function(Pointer<RlRigInstance>)>(
  symbol: 'rl_riginstance_get_raw_control_count',
)
external int riginstanceGetRawControlCount(Pointer<RlRigInstance> inst);

@Native<Float Function(Pointer<RlRigInstance>, Uint16)>(
  symbol: 'rl_riginstance_get_raw_control',
)
external double riginstanceGetRawControl(
  Pointer<RlRigInstance> inst,
  int index,
);

@Native<Void Function(Pointer<RlRigInstance>, Uint16, Float)>(
  symbol: 'rl_riginstance_set_raw_control',
)
external void riginstanceSetRawControl(
  Pointer<RlRigInstance> inst,
  int index,
  double value,
);

@Native<Uint16 Function(Pointer<RlRigInstance>)>(
  symbol: 'rl_riginstance_get_lod',
)
external int riginstanceGetLod(Pointer<RlRigInstance> inst);

@Native<Void Function(Pointer<RlRigInstance>, Uint16)>(
  symbol: 'rl_riginstance_set_lod',
)
external void riginstanceSetLod(Pointer<RlRigInstance> inst, int lod);

@Native<Uint32 Function(Pointer<RlRigInstance>, Pointer<Pointer<Float>>)>(
  symbol: 'rl_riginstance_get_joint_outputs',
)
external int riginstanceGetJointOutputs(
  Pointer<RlRigInstance> inst,
  Pointer<Pointer<Float>> outData,
);

@Native<Uint32 Function(Pointer<RlRigInstance>, Pointer<Pointer<Float>>)>(
  symbol: 'rl_riginstance_get_blend_shape_outputs',
)
external int riginstanceGetBlendShapeOutputs(
  Pointer<RlRigInstance> inst,
  Pointer<Pointer<Float>> outData,
);

@Native<Uint32 Function(Pointer<RlRigInstance>, Pointer<Pointer<Float>>)>(
  symbol: 'rl_riginstance_get_animated_map_outputs',
)
external int riginstanceGetAnimatedMapOutputs(
  Pointer<RlRigInstance> inst,
  Pointer<Pointer<Float>> outData,
);
