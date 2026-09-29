#pragma once
#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32)
#define ASSIMP_EXPORT __declspec(dllexport)
#else
#define ASSIMP_EXPORT __attribute__((visibility("default")))
#endif

/// Options for the `_ex` conversions (bit mask).
enum {
    /// Bake the source's unit scale and axis system into the scene so the GLB
    /// is standard glTF: metres, +Y up, +Z front. Applied when the source
    /// declares them (FBX GlobalSettings: UnitScaleFactor, UpAxis, FrontAxis
    /// and their signs); a source without them is left as imported.
    ASSIMP_CONVERT_NORMALIZE = 1u << 0,
    /// Remove Unreal collision hulls (meshes/nodes named UCX_, UBX_, USP_,
    /// UCP_) from the GLB and list them, with their points and triangles,
    /// in the report.
    ASSIMP_CONVERT_STRIP_COLLISION = 1u << 1,
};

/// "major.minor (commit <git hash>)" of the linked Assimp.
ASSIMP_EXPORT const char* assimp_get_version();

ASSIMP_EXPORT const char* assimp_get_last_error();

/// JSON report of the calling thread's last `_ex` conversion: source
/// metadata, the applied unit scale and axis rows, the animation takes (in
/// the order their per-channel glTF animations were written), the removed
/// collision hulls and scene counts. "{}" before the first one.
ASSIMP_EXPORT const char* assimp_get_last_report();

ASSIMP_EXPORT int assimp_convert_file_to_glb(
    const char* input_path,
    const char* output_path,
    unsigned int post_process_flags
);

ASSIMP_EXPORT int assimp_convert_memory_to_glb(
    const uint8_t* in_bytes,
    size_t in_len,
    const char* format_hint,
    uint8_t** out_bytes,
    size_t* out_len,
    unsigned int post_process_flags
);

/// [assimp_convert_file_to_glb] with [options] (ASSIMP_CONVERT_*); fills the
/// report read by [assimp_get_last_report].
ASSIMP_EXPORT int assimp_convert_file_to_glb_ex(
    const char* input_path,
    const char* output_path,
    unsigned int post_process_flags,
    unsigned int options
);

/// [assimp_convert_memory_to_glb] with [options] (ASSIMP_CONVERT_*).
ASSIMP_EXPORT int assimp_convert_memory_to_glb_ex(
    const uint8_t* in_bytes,
    size_t in_len,
    const char* format_hint,
    uint8_t** out_bytes,
    size_t* out_len,
    unsigned int post_process_flags,
    unsigned int options
);

ASSIMP_EXPORT void assimp_free_blob(uint8_t* blob);

#ifdef __cplusplus
}
#endif
