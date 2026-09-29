#include "riglogic_c.h"

#include <trio/Stream.h>
#include <trio/streams/FileStream.h>
#include <trio/streams/MemoryStream.h>
#include <dna/BinaryStreamReader.h>
#include <riglogic/RigLogic.h>
#include <status/Status.h>

#include <cstring>

enum class StreamType { File, Memory };

struct rl_dna_reader_t {
    trio::BoundedIOStream* stream;
    dna::BinaryStreamReader* reader;
    StreamType type;
};

struct rl_riglogic_t {
    rl4::RigLogic* rigLogic;
};

struct rl_riginstance_t {
    rl4::RigInstance* instance;
};

extern "C" {

RL_C_API rl_dna_reader_t* rl_dna_reader_create_from_file(const char* path) {
    if (!path) return nullptr;
    auto* stream = trio::FileStream::create(path, trio::AccessMode::Read, trio::OpenMode::Binary);
    if (!stream) {
        return nullptr;
    }
    auto* reader = dna::BinaryStreamReader::create(stream);
    if (!reader) {
        trio::FileStream::destroy(stream);
        return nullptr;
    }
    reader->read();
    if (!sc::Status::isOk()) {
        dna::BinaryStreamReader::destroy(reader);
        trio::FileStream::destroy(stream);
        return nullptr;
    }
    auto* result = new rl_dna_reader_t();
    result->stream = stream;
    result->reader = reader;
    result->type = StreamType::File;
    return result;
}

RL_C_API rl_dna_reader_t* rl_dna_reader_create_from_memory(const void* data, size_t size) {
    if (!data || size == 0) return nullptr;
    auto* stream = trio::MemoryStream::create(size);
    if (!stream) return nullptr;
    stream->open();
    stream->write(static_cast<const char*>(data), size);
    stream->seek(0);
    auto* reader = dna::BinaryStreamReader::create(stream);
    if (!reader) {
        stream->close();
        trio::MemoryStream::destroy(stream);
        return nullptr;
    }
    reader->read();
    if (!sc::Status::isOk()) {
        dna::BinaryStreamReader::destroy(reader);
        stream->close();
        trio::MemoryStream::destroy(stream);
        return nullptr;
    }
    auto* result = new rl_dna_reader_t();
    result->stream = stream;
    result->reader = reader;
    result->type = StreamType::Memory;
    return result;
}

RL_C_API void rl_dna_reader_destroy(rl_dna_reader_t* reader) {
    if (!reader) return;
    if (reader->reader) {
        dna::BinaryStreamReader::destroy(reader->reader);
        reader->reader = nullptr;
    }
    if (reader->stream) {
        reader->stream->close();
        if (reader->type == StreamType::File) {
            trio::FileStream::destroy(static_cast<trio::FileStream*>(reader->stream));
        } else {
            trio::MemoryStream::destroy(static_cast<trio::MemoryStream*>(reader->stream));
        }
        reader->stream = nullptr;
    }
    delete reader;
}

RL_C_API const char* rl_dna_reader_get_name(const rl_dna_reader_t* reader) {
    if (!reader || !reader->reader) return "";
    return reader->reader->getName().c_str();
}

RL_C_API uint16_t rl_dna_reader_get_lod_count(const rl_dna_reader_t* reader) {
    if (!reader || !reader->reader) return 0;
    return reader->reader->getLODCount();
}

RL_C_API uint16_t rl_dna_reader_get_joint_count(const rl_dna_reader_t* reader) {
    if (!reader || !reader->reader) return 0;
    return reader->reader->getJointCount();
}

RL_C_API const char* rl_dna_reader_get_joint_name(const rl_dna_reader_t* reader, uint16_t index) {
    if (!reader || !reader->reader || index >= reader->reader->getJointCount()) return "";
    return reader->reader->getJointName(index).c_str();
}

RL_C_API uint16_t rl_dna_reader_get_blend_shape_channel_count(const rl_dna_reader_t* reader) {
    if (!reader || !reader->reader) return 0;
    return reader->reader->getBlendShapeChannelCount();
}

RL_C_API const char* rl_dna_reader_get_blend_shape_channel_name(const rl_dna_reader_t* reader, uint16_t index) {
    if (!reader || !reader->reader || index >= reader->reader->getBlendShapeChannelCount()) return "";
    return reader->reader->getBlendShapeChannelName(index).c_str();
}

RL_C_API uint16_t rl_dna_reader_get_raw_control_count(const rl_dna_reader_t* reader) {
    if (!reader || !reader->reader) return 0;
    return reader->reader->getRawControlCount();
}

RL_C_API const char* rl_dna_reader_get_raw_control_name(const rl_dna_reader_t* reader, uint16_t index) {
    if (!reader || !reader->reader || index >= reader->reader->getRawControlCount()) return "";
    return reader->reader->getRawControlName(index).c_str();
}

RL_C_API uint16_t rl_dna_reader_get_gui_control_count(const rl_dna_reader_t* reader) {
    if (!reader || !reader->reader) return 0;
    return reader->reader->getGUIControlCount();
}

RL_C_API const char* rl_dna_reader_get_gui_control_name(const rl_dna_reader_t* reader, uint16_t index) {
    if (!reader || !reader->reader || index >= reader->reader->getGUIControlCount()) return "";
    return reader->reader->getGUIControlName(index).c_str();
}

RL_C_API uint16_t rl_dna_reader_get_animated_map_count(const rl_dna_reader_t* reader) {
    if (!reader || !reader->reader) return 0;
    return reader->reader->getAnimatedMapCount();
}

RL_C_API const char* rl_dna_reader_get_animated_map_name(const rl_dna_reader_t* reader, uint16_t index) {
    if (!reader || !reader->reader || index >= reader->reader->getAnimatedMapCount()) return "";
    return reader->reader->getAnimatedMapName(index).c_str();
}

// --- RigLogic ---
RL_C_API rl_riglogic_t* rl_riglogic_create(rl_dna_reader_t* reader) {
    if (!reader || !reader->reader) return nullptr;
    auto* rl = rl4::RigLogic::create(reader->reader);
    if (!rl) return nullptr;
    auto* result = new rl_riglogic_t();
    result->rigLogic = rl;
    return result;
}

RL_C_API void rl_riglogic_destroy(rl_riglogic_t* rl) {
    if (!rl) return;
    if (rl->rigLogic) {
        rl4::RigLogic::destroy(rl->rigLogic);
        rl->rigLogic = nullptr;
    }
    delete rl;
}

RL_C_API void rl_riglogic_calculate(rl_riglogic_t* rl, rl_riginstance_t* inst) {
    if (!rl || !rl->rigLogic || !inst || !inst->instance) return;
    rl->rigLogic->calculate(inst->instance);
}

// --- RigInstance ---
RL_C_API rl_riginstance_t* rl_riginstance_create(rl_riglogic_t* rl) {
    if (!rl || !rl->rigLogic) return nullptr;
    auto* inst = rl4::RigInstance::create(rl->rigLogic);
    if (!inst) return nullptr;
    auto* result = new rl_riginstance_t();
    result->instance = inst;
    return result;
}

RL_C_API void rl_riginstance_destroy(rl_riginstance_t* inst) {
    if (!inst) return;
    if (inst->instance) {
        rl4::RigInstance::destroy(inst->instance);
        inst->instance = nullptr;
    }
    delete inst;
}

RL_C_API uint16_t rl_riginstance_get_raw_control_count(const rl_riginstance_t* inst) {
    if (!inst || !inst->instance) return 0;
    return inst->instance->getRawControlCount();
}

RL_C_API float rl_riginstance_get_raw_control(const rl_riginstance_t* inst, uint16_t index) {
    if (!inst || !inst->instance) return 0.0f;
    return inst->instance->getRawControl(index);
}

RL_C_API void rl_riginstance_set_raw_control(rl_riginstance_t* inst, uint16_t index, float value) {
    if (!inst || !inst->instance) return;
    inst->instance->setRawControl(index, value);
}

RL_C_API uint16_t rl_riginstance_get_lod(const rl_riginstance_t* inst) {
    if (!inst || !inst->instance) return 0;
    return inst->instance->getLOD();
}

RL_C_API void rl_riginstance_set_lod(rl_riginstance_t* inst, uint16_t lod) {
    if (!inst || !inst->instance) return;
    inst->instance->setLOD(lod);
}

RL_C_API uint32_t rl_riginstance_get_joint_outputs(const rl_riginstance_t* inst, const float** out_data) {
    if (!inst || !inst->instance || !out_data) {
        if (out_data) *out_data = nullptr;
        return 0;
    }
    auto view = inst->instance->getJointOutputs();
    *out_data = view.data();
    return static_cast<uint32_t>(view.size());
}

RL_C_API uint32_t rl_riginstance_get_blend_shape_outputs(const rl_riginstance_t* inst, const float** out_data) {
    if (!inst || !inst->instance || !out_data) {
        if (out_data) *out_data = nullptr;
        return 0;
    }
    auto view = inst->instance->getBlendShapeOutputs();
    *out_data = view.data();
    return static_cast<uint32_t>(view.size());
}

RL_C_API uint32_t rl_riginstance_get_animated_map_outputs(const rl_riginstance_t* inst, const float** out_data) {
    if (!inst || !inst->instance || !out_data) {
        if (out_data) *out_data = nullptr;
        return 0;
    }
    auto view = inst->instance->getAnimatedMapOutputs();
    *out_data = view.data();
    return static_cast<uint32_t>(view.size());
}

} // extern "C"
