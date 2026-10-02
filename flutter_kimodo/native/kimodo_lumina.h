/*
 * kimodo_lumina.h -- C entry points flutter_kimodo adds to kimodo.dll.
 *
 * Compiled into the kimodo library by tool/kimodo/CMakeLists.txt (it links
 * the C++ API, which kimodo_capi.h does not expose): multi-prompt sequences,
 * the process-wide backend settings the runtime reads from the environment,
 * and what the build contains. Every entry point is an exception firewall.
 */
#pragma once

#include <kimodo/kimodo_capi.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Backends compiled into this build: "cpu" or "cpu,vulkan". */
KIMODO_API const char *kimodo_lumina_backends(void);

/*
 * Sets the backend the next model load and generation use, for the whole
 * process: device AUTO (Vulkan when built and a device exists, else CPU),
 * CPU, or VULKAN; `threads` > 0 caps the CPU threads (0 = all cores);
 * `vulkan_device` >= 0 is the index into vkEnumeratePhysicalDevices that GGML
 * uses (GGML_VK_VISIBLE_DEVICES), -1 leaves GGML's choice (the first
 * dedicated GPU). GGML reads the Vulkan device list once per process, so the
 * device must be chosen before the first model is loaded. Returns 1, or 0 and
 * a reason in `err`.
 */
KIMODO_API int kimodo_lumina_configure(kimodo_device device, int threads, int vulkan_device, char *err, int err_len);

/*
 * Generates one motion from `count` (1..16) prompts played in order, segment
 * i lasting frames[i] (2..300) frames, joined by `transition_frames` (1..60,
 * shorter than every following segment) blended frames. Returns an owning
 * motion (free with kimodo_motion_free) or NULL with a reason in `err`.
 */
KIMODO_API kimodo_motion *kimodo_lumina_generate_sequence(
    kimodo_model *model,
    const char *const *prompts,
    const uint32_t *frames,
    uint32_t count,
    uint32_t transition_frames,
    const kimodo_generation_options *options,
    char *err,
    int err_len);

#ifdef __cplusplus
}
#endif
