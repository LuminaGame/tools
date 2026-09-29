#ifndef RIGLOGIC_C_H
#define RIGLOGIC_C_H

#include <stdint.h>
#include <stddef.h>

#if defined(_WIN32) || defined(__CYGWIN__)
  #ifdef RIGLOGIC_EXPORTS
    #define RL_C_API __declspec(dllexport)
  #else
    #define RL_C_API __declspec(dllimport)
  #endif
#else
  #define RL_C_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef struct rl_dna_reader_t rl_dna_reader_t;
typedef struct rl_riglogic_t rl_riglogic_t;
typedef struct rl_riginstance_t rl_riginstance_t;

// --- DNA Reader ---
RL_C_API rl_dna_reader_t* rl_dna_reader_create_from_file(const char* path);
RL_C_API rl_dna_reader_t* rl_dna_reader_create_from_memory(const void* data, size_t size);
RL_C_API void rl_dna_reader_destroy(rl_dna_reader_t* reader);

RL_C_API const char* rl_dna_reader_get_name(const rl_dna_reader_t* reader);
RL_C_API uint16_t rl_dna_reader_get_lod_count(const rl_dna_reader_t* reader);
RL_C_API uint16_t rl_dna_reader_get_joint_count(const rl_dna_reader_t* reader);
RL_C_API const char* rl_dna_reader_get_joint_name(const rl_dna_reader_t* reader, uint16_t index);
RL_C_API uint16_t rl_dna_reader_get_blend_shape_channel_count(const rl_dna_reader_t* reader);
RL_C_API const char* rl_dna_reader_get_blend_shape_channel_name(const rl_dna_reader_t* reader, uint16_t index);
RL_C_API uint16_t rl_dna_reader_get_raw_control_count(const rl_dna_reader_t* reader);
RL_C_API const char* rl_dna_reader_get_raw_control_name(const rl_dna_reader_t* reader, uint16_t index);
RL_C_API uint16_t rl_dna_reader_get_gui_control_count(const rl_dna_reader_t* reader);
RL_C_API const char* rl_dna_reader_get_gui_control_name(const rl_dna_reader_t* reader, uint16_t index);
RL_C_API uint16_t rl_dna_reader_get_animated_map_count(const rl_dna_reader_t* reader);
RL_C_API const char* rl_dna_reader_get_animated_map_name(const rl_dna_reader_t* reader, uint16_t index);

// --- RigLogic ---
RL_C_API rl_riglogic_t* rl_riglogic_create(rl_dna_reader_t* reader);
RL_C_API void rl_riglogic_destroy(rl_riglogic_t* rl);
RL_C_API void rl_riglogic_calculate(rl_riglogic_t* rl, rl_riginstance_t* inst);

// --- RigInstance ---
RL_C_API rl_riginstance_t* rl_riginstance_create(rl_riglogic_t* rl);
RL_C_API void rl_riginstance_destroy(rl_riginstance_t* inst);

RL_C_API uint16_t rl_riginstance_get_raw_control_count(const rl_riginstance_t* inst);
RL_C_API float rl_riginstance_get_raw_control(const rl_riginstance_t* inst, uint16_t index);
RL_C_API void rl_riginstance_set_raw_control(rl_riginstance_t* inst, uint16_t index, float value);

RL_C_API uint16_t rl_riginstance_get_lod(const rl_riginstance_t* inst);
RL_C_API void rl_riginstance_set_lod(rl_riginstance_t* inst, uint16_t lod);

RL_C_API uint32_t rl_riginstance_get_joint_outputs(const rl_riginstance_t* inst, const float** out_data);
RL_C_API uint32_t rl_riginstance_get_blend_shape_outputs(const rl_riginstance_t* inst, const float** out_data);
RL_C_API uint32_t rl_riginstance_get_animated_map_outputs(const rl_riginstance_t* inst, const float** out_data);

#ifdef __cplusplus
}
#endif

#endif // RIGLOGIC_C_H

