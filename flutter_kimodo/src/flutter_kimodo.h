/*
 * flutter_kimodo.h -- the C surface flutter_kimodo's Dart bindings call.
 *
 * flutter_kimodo.{dll,so} is built by the native-assets hook from
 * flutter_kimodo.c and has no link-time dependency on kimodo: it loads the
 * prebuilt kimodo library (and through it the ggml backends) from its own
 * folder at flutter_kimodo_open, so the libraries are found wherever the
 * bundle puts them, and forwards to the kimodo C API (kimodo/kimodo_capi.h,
 * vendored from the pinned kimodo.cpp commit) and to the entry points
 * flutter_kimodo compiles into kimodo (native/kimodo_lumina.h).
 *
 * Every function except flutter_kimodo_open, flutter_kimodo_is_open and the
 * Vulkan device queries needs a successful flutter_kimodo_open first.
 */
#ifndef FLUTTER_KIMODO_H
#define FLUTTER_KIMODO_H

#include <stdint.h>

#include "kimodo/kimodo_capi.h"

#if defined(_WIN32)
#define FFI_PLUGIN_EXPORT __declspec(dllexport)
#else
#define FFI_PLUGIN_EXPORT __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Loads the kimodo library: from `runtime_dir` when it is non-NULL and
 * non-empty, else from the folder holding flutter_kimodo itself. Idempotent.
 * Returns 1, or 0 with the reason in `err`.
 */
FFI_PLUGIN_EXPORT int32_t flutter_kimodo_open(const char *runtime_dir, char *err, int32_t err_len);

/* 1 once flutter_kimodo_open succeeded. */
FFI_PLUGIN_EXPORT int32_t flutter_kimodo_is_open(void);

/* Absolute path of the loaded kimodo library ("" before flutter_kimodo_open). */
FFI_PLUGIN_EXPORT const char *flutter_kimodo_library_path(void);

/* kimodo_abi_version() of the loaded library. */
FFI_PLUGIN_EXPORT int32_t flutter_kimodo_abi_version(void);

/* Backends compiled into the loaded library: "cpu" or "cpu,vulkan". */
FFI_PLUGIN_EXPORT const char *flutter_kimodo_backends(void);

/*
 * Process-wide backend for the next model load (kimodo_lumina_configure):
 * device 0 auto, 1 CPU, 2 Vulkan; threads 0 = all cores; vulkan_device = the
 * vkEnumeratePhysicalDevices index to use (flutter_kimodo_vulkan_device_*),
 * -1 = the first dedicated GPU. Must precede the first model load of the
 * process. Returns 1, or 0 with the reason in `err`.
 */
FFI_PLUGIN_EXPORT int32_t flutter_kimodo_configure(int32_t device, int32_t threads, int32_t vulkan_device,
                                                   char *err, int32_t err_len);

/*
 * The Vulkan physical devices in vkEnumeratePhysicalDevices order (the order
 * GGML_VK_VISIBLE_DEVICES indexes), read through the system Vulkan loader.
 * Count is 0 without a loader or device.
 */
FFI_PLUGIN_EXPORT int32_t flutter_kimodo_vulkan_device_count(void);

/* Writes device `index`'s name into `buf`; returns its length or -1. */
FFI_PLUGIN_EXPORT int32_t flutter_kimodo_vulkan_device_name(int32_t index, char *buf, int32_t buf_len);

/* VkPhysicalDeviceType of device `index` (1 integrated, 2 discrete, 3 virtual, 4 CPU, 0 other) or -1. */
FFI_PLUGIN_EXPORT int32_t flutter_kimodo_vulkan_device_type(int32_t index);

/*
 * kimodo_model_load: the motion GGUF and the text encoder GGUF (with
 * tokenizer.gguf in the same folder). NULL with the reason in `err` on
 * failure.
 */
FFI_PLUGIN_EXPORT kimodo_model *flutter_kimodo_model_load(const char *motion_gguf, const char *text_gguf,
                                                          char *err, int32_t err_len);
FFI_PLUGIN_EXPORT void flutter_kimodo_model_free(kimodo_model *model);

/* kimodo_generate: one prompt. Blocking (seconds to minutes). */
FFI_PLUGIN_EXPORT kimodo_motion *flutter_kimodo_generate(kimodo_model *model, const char *prompt,
                                                         const kimodo_generation_options *options,
                                                         char *err, int32_t err_len);

/* kimodo_lumina_generate_sequence: prompts played in order. Blocking. */
FFI_PLUGIN_EXPORT kimodo_motion *flutter_kimodo_generate_sequence(kimodo_model *model,
                                                                  const char *const *prompts,
                                                                  const uint32_t *frames, uint32_t count,
                                                                  uint32_t transition_frames,
                                                                  const kimodo_generation_options *options,
                                                                  char *err, int32_t err_len);

FFI_PLUGIN_EXPORT void flutter_kimodo_motion_free(kimodo_motion *motion);
FFI_PLUGIN_EXPORT int32_t flutter_kimodo_motion_frames(const kimodo_motion *motion);
FFI_PLUGIN_EXPORT int32_t flutter_kimodo_motion_joints(const kimodo_motion *motion);
/* Borrowed [frames, joints, 4] parent-local rotations (x, y, z, w). */
FFI_PLUGIN_EXPORT const float *flutter_kimodo_motion_local_rotations_xyzw(const kimodo_motion *motion);
/* Borrowed [frames, 3] root (hips) positions in metres, Y up, +Z forward. */
FFI_PLUGIN_EXPORT const float *flutter_kimodo_motion_root_positions(const kimodo_motion *motion);

#ifdef __cplusplus
}
#endif

#endif /* FLUTTER_KIMODO_H */
