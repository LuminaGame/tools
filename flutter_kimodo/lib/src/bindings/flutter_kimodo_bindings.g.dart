// AUTO-GENERATED STYLE — keep in lockstep with src/flutter_kimodo.h and
// src/kimodo/kimodo_capi.h. Regenerate with `dart run tool/ffigen.dart` (needs
// libclang); test/bindings_lockstep_test.dart fails when a declaration in the
// headers has no binding here.

// ignore_for_file: type=lint, unused_import, unused_element
// ignore_for_file: camel_case_types, non_constant_identifier_names
// ignore_for_file: constant_identifier_names

import 'dart:ffi' as ffi;

// --- kimodo/kimodo_capi.h ---------------------------------------------------

const int KIMODO_CAPI_ABI_VERSION = 1;

final class kimodo_model extends ffi.Opaque {}

final class kimodo_motion extends ffi.Opaque {}

enum kimodo_device {
  KIMODO_DEVICE_AUTO(0),
  KIMODO_DEVICE_CPU(1),
  KIMODO_DEVICE_VULKAN(2);

  final int value;
  const kimodo_device(this.value);

  static kimodo_device fromValue(int value) => switch (value) {
    0 => KIMODO_DEVICE_AUTO,
    1 => KIMODO_DEVICE_CPU,
    2 => KIMODO_DEVICE_VULKAN,
    _ => throw ArgumentError('Unknown value for kimodo_device: $value'),
  };
}

final class kimodo_runtime_options extends ffi.Struct {
  @ffi.Uint32()
  external int size;

  @ffi.Uint32()
  external int threads;

  @ffi.UnsignedInt()
  external int deviceAsInt;

  external ffi.Pointer<ffi.Char> backend_dir;
}

final class kimodo_generation_options extends ffi.Struct {
  @ffi.Uint32()
  external int size;

  @ffi.Uint64()
  external int seed;

  @ffi.Uint32()
  external int frames;

  @ffi.Uint32()
  external int diffusion_steps;

  @ffi.Float()
  external double text_cfg_weight;

  @ffi.Float()
  external double constraint_cfg_weight;
}

final class kimodo_embedding extends ffi.Struct {
  external ffi.Pointer<ffi.Float> data;

  @ffi.Uint32()
  external int values;
}

// --- flutter_kimodo.h -------------------------------------------------------

@ffi.Native<
  ffi.Int32 Function(ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Char>, ffi.Int32)
>()
external int flutter_kimodo_open(
  ffi.Pointer<ffi.Char> runtime_dir,
  ffi.Pointer<ffi.Char> err,
  int err_len,
);

@ffi.Native<ffi.Int32 Function()>()
external int flutter_kimodo_is_open();

@ffi.Native<ffi.Pointer<ffi.Char> Function()>()
external ffi.Pointer<ffi.Char> flutter_kimodo_library_path();

@ffi.Native<ffi.Int32 Function()>()
external int flutter_kimodo_abi_version();

@ffi.Native<ffi.Pointer<ffi.Char> Function()>()
external ffi.Pointer<ffi.Char> flutter_kimodo_backends();

@ffi.Native<
  ffi.Int32 Function(
    ffi.Int32,
    ffi.Int32,
    ffi.Int32,
    ffi.Pointer<ffi.Char>,
    ffi.Int32,
  )
>()
external int flutter_kimodo_configure(
  int device,
  int threads,
  int vulkan_device,
  ffi.Pointer<ffi.Char> err,
  int err_len,
);

@ffi.Native<ffi.Int32 Function()>()
external int flutter_kimodo_vulkan_device_count();

@ffi.Native<ffi.Int32 Function(ffi.Int32, ffi.Pointer<ffi.Char>, ffi.Int32)>()
external int flutter_kimodo_vulkan_device_name(
  int index,
  ffi.Pointer<ffi.Char> buf,
  int buf_len,
);

@ffi.Native<ffi.Int32 Function(ffi.Int32)>()
external int flutter_kimodo_vulkan_device_type(int index);

@ffi.Native<
  ffi.Pointer<kimodo_model> Function(
    ffi.Pointer<ffi.Char>,
    ffi.Pointer<ffi.Char>,
    ffi.Pointer<ffi.Char>,
    ffi.Int32,
  )
>()
external ffi.Pointer<kimodo_model> flutter_kimodo_model_load(
  ffi.Pointer<ffi.Char> motion_gguf,
  ffi.Pointer<ffi.Char> text_gguf,
  ffi.Pointer<ffi.Char> err,
  int err_len,
);

@ffi.Native<ffi.Void Function(ffi.Pointer<kimodo_model>)>()
external void flutter_kimodo_model_free(ffi.Pointer<kimodo_model> model);

@ffi.Native<
  ffi.Pointer<kimodo_motion> Function(
    ffi.Pointer<kimodo_model>,
    ffi.Pointer<ffi.Char>,
    ffi.Pointer<kimodo_generation_options>,
    ffi.Pointer<ffi.Char>,
    ffi.Int32,
  )
>()
external ffi.Pointer<kimodo_motion> flutter_kimodo_generate(
  ffi.Pointer<kimodo_model> model,
  ffi.Pointer<ffi.Char> prompt,
  ffi.Pointer<kimodo_generation_options> options,
  ffi.Pointer<ffi.Char> err,
  int err_len,
);

@ffi.Native<
  ffi.Pointer<kimodo_motion> Function(
    ffi.Pointer<kimodo_model>,
    ffi.Pointer<ffi.Pointer<ffi.Char>>,
    ffi.Pointer<ffi.Uint32>,
    ffi.Uint32,
    ffi.Uint32,
    ffi.Pointer<kimodo_generation_options>,
    ffi.Pointer<ffi.Char>,
    ffi.Int32,
  )
>()
external ffi.Pointer<kimodo_motion> flutter_kimodo_generate_sequence(
  ffi.Pointer<kimodo_model> model,
  ffi.Pointer<ffi.Pointer<ffi.Char>> prompts,
  ffi.Pointer<ffi.Uint32> frames,
  int count,
  int transition_frames,
  ffi.Pointer<kimodo_generation_options> options,
  ffi.Pointer<ffi.Char> err,
  int err_len,
);

@ffi.Native<ffi.Void Function(ffi.Pointer<kimodo_motion>)>()
external void flutter_kimodo_motion_free(ffi.Pointer<kimodo_motion> motion);

@ffi.Native<ffi.Int32 Function(ffi.Pointer<kimodo_motion>)>()
external int flutter_kimodo_motion_frames(ffi.Pointer<kimodo_motion> motion);

@ffi.Native<ffi.Int32 Function(ffi.Pointer<kimodo_motion>)>()
external int flutter_kimodo_motion_joints(ffi.Pointer<kimodo_motion> motion);

@ffi.Native<ffi.Pointer<ffi.Float> Function(ffi.Pointer<kimodo_motion>)>()
external ffi.Pointer<ffi.Float> flutter_kimodo_motion_local_rotations_xyzw(
  ffi.Pointer<kimodo_motion> motion,
);

@ffi.Native<ffi.Pointer<ffi.Float> Function(ffi.Pointer<kimodo_motion>)>()
external ffi.Pointer<ffi.Float> flutter_kimodo_motion_root_positions(
  ffi.Pointer<kimodo_motion> motion,
);
