// C entry points flutter_kimodo adds to kimodo.dll (see kimodo_lumina.h).
#include "kimodo_lumina.h"

#include <kimodo/kimodo.hpp>

#include <algorithm>
#include <cstdlib>
#include <cstring>
#include <memory>
#include <string>
#include <vector>

// The C API's handles, defined in kimodo.cpp's src/capi.cpp; repeated
// token for token so this file can reach the C++ model behind a handle.
struct kimodo_model { std::unique_ptr<kimodo::model> value; std::string last_error; };
struct kimodo_motion { kimodo::motion_data value; };

namespace {
void write_error(char *buffer, int length, const std::string &message) noexcept {
    if (!buffer || length <= 0) return;
    const size_t n = std::min(message.size(), static_cast<size_t>(length - 1));
    std::memcpy(buffer, message.data(), n);
    buffer[n] = '\0';
}

void set_env(const char *name, const char *value) {
#if defined(_WIN32)
    // _putenv_s writes the CRT's copy that GGML's getenv reads (and the
    // process block); kimodo.dll and the ggml DLLs share the dynamic CRT.
    _putenv_s(name, value ? value : "");
#else
    if (value) setenv(name, value, 1); else unsetenv(name);
#endif
}
} // namespace

extern "C" {

const char *kimodo_lumina_backends(void) {
#if defined(KIMODO_HAVE_GGML_VULKAN)
    return "cpu,vulkan";
#else
    return "cpu";
#endif
}

int kimodo_lumina_configure(kimodo_device device, int threads, int vulkan_device, char *err, int err_len) {
    try {
        if (device != KIMODO_DEVICE_AUTO && device != KIMODO_DEVICE_CPU && device != KIMODO_DEVICE_VULKAN) {
            write_error(err, err_len, "unknown device");
            return 0;
        }
#if !defined(KIMODO_HAVE_GGML_VULKAN)
        if (device == KIMODO_DEVICE_VULKAN) {
            write_error(err, err_len, "this kimodo build has no Vulkan backend");
            return 0;
        }
#endif
        if (threads < 0) { write_error(err, err_len, "threads must be >= 0"); return 0; }
        set_env("KIMODO_BACKEND", device == KIMODO_DEVICE_CPU ? "cpu" : nullptr);
        const std::string t = std::to_string(threads);
        set_env("KIMODO_THREADS", threads > 0 ? t.c_str() : nullptr);
        const std::string v = std::to_string(vulkan_device);
        set_env("GGML_VK_VISIBLE_DEVICES", vulkan_device >= 0 ? v.c_str() : nullptr);
        return 1;
    } catch (const std::exception &e) { write_error(err, err_len, e.what()); return 0; }
    catch (...) { write_error(err, err_len, "unknown C++ exception"); return 0; }
}

kimodo_motion *kimodo_lumina_generate_sequence(
    kimodo_model *model, const char *const *prompts, const uint32_t *frames, uint32_t count,
    uint32_t transition_frames, const kimodo_generation_options *options, char *err, int err_len) {
    auto fail = [&](const std::string &message) -> kimodo_motion * {
        if (model) model->last_error = message;
        write_error(err, err_len, message);
        return nullptr;
    };
    try {
        if (!model || !model->value) return fail("invalid model");
        if (!options || options->size != sizeof(*options)) return fail("invalid kimodo_generation_options");
        if (!prompts || !frames || count == 0) return fail("a sequence needs at least one prompt");
        std::vector<kimodo::prompt_segment> segments;
        segments.reserve(count);
        for (uint32_t i = 0; i < count; ++i) {
            if (!prompts[i]) return fail("prompt " + std::to_string(i) + " is NULL");
            segments.push_back({prompts[i], frames[i]});
        }
        auto generated = model->value->generate_text_sequence(
            segments, transition_frames, options->diffusion_steps, options->seed,
            options->text_cfg_weight, options->constraint_cfg_weight);
        if (!generated) return fail(generated.error());
        model->last_error.clear();
        return new kimodo_motion{std::move(*generated)};
    } catch (const std::exception &e) { return fail(e.what()); }
    catch (...) { return fail("unknown C++ exception"); }
}

kimodo_motion *kimodo_lumina_generate_conditioned(
    kimodo_model *model, const char *prompt, uint32_t frames,
    const float *observed_motion, const float *motion_mask,
    const kimodo_generation_options *options, char *err, int err_len) {
    auto fail = [&](const std::string &message) -> kimodo_motion * {
        if (model) model->last_error = message;
        write_error(err, err_len, message);
        return nullptr;
    };
    try {
        if (!model || !model->value) return fail("invalid model");
        if (!options || options->size != sizeof(*options)) return fail("invalid kimodo_generation_options");
        if (!prompt) return fail("prompt is NULL");
        if (!observed_motion || !motion_mask) return fail("observed_motion and motion_mask are required");
        
        std::span<const float> obs(observed_motion, static_cast<size_t>(frames) * 369);
        std::span<const float> mask(motion_mask, static_cast<size_t>(frames) * 369);

        auto generated = model->value->generate_text(
            prompt, frames, options->diffusion_steps, options->seed,
            options->text_cfg_weight, options->constraint_cfg_weight,
            obs, mask);
        
        if (!generated) return fail(generated.error());
        model->last_error.clear();
        return new kimodo_motion{std::move(*generated)};
    } catch (const std::exception &e) { return fail(e.what()); }
    catch (...) { return fail("unknown C++ exception"); }
}

} // extern "C"
