// flutter_kimodo: loads the prebuilt kimodo library at run time and forwards
// to it (see flutter_kimodo.h).
#include "flutter_kimodo.h"

#include <stdio.h>
#include <string.h>

#if defined(_WIN32)
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
typedef HMODULE fk_lib;
#define FK_KIMODO_LIB "kimodo.dll"
#define FK_VULKAN_LIB "vulkan-1.dll"
#else
#include <dlfcn.h>
typedef void *fk_lib;
#if defined(__APPLE__)
#define FK_KIMODO_LIB "libkimodo.dylib"
#define FK_VULKAN_LIB "libvulkan.1.dylib"
#else
#define FK_KIMODO_LIB "libkimodo.so"
#define FK_VULKAN_LIB "libvulkan.so.1"
#endif
#endif

#define FK_PATH_MAX 4096

static void fk_error(char *buf, int32_t len, const char *message) {
  if (!buf || len <= 0) return;
  snprintf(buf, (size_t)len, "%s", message);
}

// --- kimodo entry points ----------------------------------------------------

typedef int (*abi_version_fn)(void);
typedef kimodo_model *(*model_load_fn)(const char *, const char *, const char *, const kimodo_runtime_options *,
                                       char *, int);
typedef void (*model_free_fn)(kimodo_model *);
typedef kimodo_motion *(*generate_fn)(kimodo_model *, const char *, const kimodo_generation_options *, char *, int);
typedef void (*motion_free_fn)(kimodo_motion *);
typedef int (*motion_int_fn)(const kimodo_motion *);
typedef const float *(*motion_data_fn)(const kimodo_motion *);
typedef const char *(*backends_fn)(void);
typedef int (*configure_fn)(kimodo_device, int, int, char *, int);
typedef kimodo_motion *(*sequence_fn)(kimodo_model *, const char *const *, const uint32_t *, uint32_t, uint32_t,
                                      const kimodo_generation_options *, char *, int);

static struct {
  fk_lib lib;
  char path[FK_PATH_MAX];
  abi_version_fn abi_version;
  model_load_fn model_load;
  model_free_fn model_free;
  generate_fn generate;
  motion_free_fn motion_free;
  motion_int_fn motion_frames;
  motion_int_fn motion_joints;
  motion_data_fn motion_rotations;
  motion_data_fn motion_roots;
  backends_fn backends;
  configure_fn configure;
  sequence_fn sequence;
} K;

static void *fk_symbol(fk_lib lib, const char *name) {
#if defined(_WIN32)
  return (void *)GetProcAddress(lib, name);
#else
  return dlsym(lib, name);
#endif
}

// The folder holding this library (with a trailing separator).
static int fk_own_dir(char *out, size_t len) {
#if defined(_WIN32)
  HMODULE self = NULL;
  if (!GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                          (LPCSTR)(void *)&fk_own_dir, &self))
    return 0;
  wchar_t wide[FK_PATH_MAX];
  DWORD n = GetModuleFileNameW(self, wide, FK_PATH_MAX);
  if (n == 0 || n >= FK_PATH_MAX) return 0;
  while (n > 0 && wide[n - 1] != L'\\' && wide[n - 1] != L'/') n--;
  wide[n] = 0;
  return WideCharToMultiByte(CP_UTF8, 0, wide, -1, out, (int)len, NULL, NULL) > 0;
#else
  Dl_info info;
  if (!dladdr((void *)&fk_own_dir, &info) || !info.dli_fname) return 0;
  snprintf(out, len, "%s", info.dli_fname);
  char *slash = strrchr(out, '/');
  if (!slash) return 0;
  slash[1] = 0;
  return 1;
#endif
}

static fk_lib fk_load(const char *path, char *err, int32_t err_len) {
#if defined(_WIN32)
  wchar_t wide[FK_PATH_MAX];
  if (!MultiByteToWideChar(CP_UTF8, 0, path, -1, wide, FK_PATH_MAX)) {
    fk_error(err, err_len, "invalid library path");
    return NULL;
  }
  // The altered search path resolves kimodo's own imports (ggml*.dll) in
  // kimodo.dll's folder first, not in the host executable's.
  HMODULE lib = LoadLibraryExW(wide, NULL, LOAD_WITH_ALTERED_SEARCH_PATH);
  if (!lib) {
    char message[FK_PATH_MAX + 64];
    snprintf(message, sizeof message, "cannot load %s (Windows error %lu)", path, (unsigned long)GetLastError());
    fk_error(err, err_len, message);
  }
  return lib;
#else
  void *lib = dlopen(path, RTLD_NOW | RTLD_LOCAL);
  if (!lib) {
    const char *reason = dlerror();
    char message[FK_PATH_MAX + 512];
    snprintf(message, sizeof message, "cannot load %s: %s", path, reason ? reason : "unknown error");
    fk_error(err, err_len, message);
  }
  return lib;
#endif
}

int32_t flutter_kimodo_open(const char *runtime_dir, char *err, int32_t err_len) {
  if (K.lib) return 1;
  char dir[FK_PATH_MAX];
  if (runtime_dir && *runtime_dir) {
    size_t n = strlen(runtime_dir);
    int needs_slash = runtime_dir[n - 1] != '/' && runtime_dir[n - 1] != '\\';
    snprintf(dir, sizeof dir, "%s%s", runtime_dir, needs_slash ? "/" : "");
  } else if (!fk_own_dir(dir, sizeof dir)) {
    fk_error(err, err_len, "cannot find the folder of flutter_kimodo");
    return 0;
  }
  char path[FK_PATH_MAX];
  snprintf(path, sizeof path, "%s%s", dir, FK_KIMODO_LIB);
  fk_lib lib = fk_load(path, err, err_len);
  if (!lib) return 0;
#define FK_BIND(field, type, name)                                     \
  K.field = (type)fk_symbol(lib, name);                                \
  if (!K.field) {                                                      \
    char message[FK_PATH_MAX + 128];                                   \
    snprintf(message, sizeof message, "%s lacks %s", path, name);      \
    fk_error(err, err_len, message);                                   \
    return 0;                                                          \
  }
  FK_BIND(abi_version, abi_version_fn, "kimodo_abi_version");
  FK_BIND(model_load, model_load_fn, "kimodo_model_load");
  FK_BIND(model_free, model_free_fn, "kimodo_model_free");
  FK_BIND(generate, generate_fn, "kimodo_generate");
  FK_BIND(motion_free, motion_free_fn, "kimodo_motion_free");
  FK_BIND(motion_frames, motion_int_fn, "kimodo_motion_frames");
  FK_BIND(motion_joints, motion_int_fn, "kimodo_motion_joints");
  FK_BIND(motion_rotations, motion_data_fn, "kimodo_motion_local_rotations_xyzw");
  FK_BIND(motion_roots, motion_data_fn, "kimodo_motion_root_positions");
  FK_BIND(backends, backends_fn, "kimodo_lumina_backends");
  FK_BIND(configure, configure_fn, "kimodo_lumina_configure");
  FK_BIND(sequence, sequence_fn, "kimodo_lumina_generate_sequence");
#undef FK_BIND
  if (K.abi_version() != KIMODO_CAPI_ABI_VERSION) {
    char message[256];
    snprintf(message, sizeof message, "kimodo ABI %d, flutter_kimodo expects %d", K.abi_version(),
             KIMODO_CAPI_ABI_VERSION);
    fk_error(err, err_len, message);
    return 0;
  }
  snprintf(K.path, sizeof K.path, "%s", path);
  K.lib = lib;
  return 1;
}

int32_t flutter_kimodo_is_open(void) { return K.lib != NULL; }

const char *flutter_kimodo_library_path(void) { return K.path; }

int32_t flutter_kimodo_abi_version(void) { return K.lib ? K.abi_version() : -1; }

const char *flutter_kimodo_backends(void) { return K.lib ? K.backends() : ""; }

int32_t flutter_kimodo_configure(int32_t device, int32_t threads, int32_t vulkan_device, char *err,
                                 int32_t err_len) {
  if (!K.lib) {
    fk_error(err, err_len, "kimodo is not loaded");
    return 0;
  }
  return K.configure((kimodo_device)device, threads, vulkan_device, err, err_len);
}

kimodo_model *flutter_kimodo_model_load(const char *motion_gguf, const char *text_gguf, char *err, int32_t err_len) {
  if (!K.lib) {
    fk_error(err, err_len, "kimodo is not loaded");
    return NULL;
  }
  kimodo_runtime_options options;
  memset(&options, 0, sizeof options);
  options.size = sizeof options;
  options.device = KIMODO_DEVICE_AUTO;
  return K.model_load(motion_gguf, text_gguf, NULL, &options, err, err_len);
}

void flutter_kimodo_model_free(kimodo_model *model) {
  if (K.lib && model) K.model_free(model);
}

kimodo_motion *flutter_kimodo_generate(kimodo_model *model, const char *prompt,
                                       const kimodo_generation_options *options, char *err, int32_t err_len) {
  if (!K.lib) {
    fk_error(err, err_len, "kimodo is not loaded");
    return NULL;
  }
  return K.generate(model, prompt, options, err, err_len);
}

kimodo_motion *flutter_kimodo_generate_sequence(kimodo_model *model, const char *const *prompts,
                                                const uint32_t *frames, uint32_t count, uint32_t transition_frames,
                                                const kimodo_generation_options *options, char *err,
                                                int32_t err_len) {
  if (!K.lib) {
    fk_error(err, err_len, "kimodo is not loaded");
    return NULL;
  }
  return K.sequence(model, prompts, frames, count, transition_frames, options, err, err_len);
}

void flutter_kimodo_motion_free(kimodo_motion *motion) {
  if (K.lib && motion) K.motion_free(motion);
}

int32_t flutter_kimodo_motion_frames(const kimodo_motion *motion) { return K.lib ? K.motion_frames(motion) : 0; }

int32_t flutter_kimodo_motion_joints(const kimodo_motion *motion) { return K.lib ? K.motion_joints(motion) : 0; }

const float *flutter_kimodo_motion_local_rotations_xyzw(const kimodo_motion *motion) {
  return K.lib ? K.motion_rotations(motion) : NULL;
}

const float *flutter_kimodo_motion_root_positions(const kimodo_motion *motion) {
  return K.lib ? K.motion_roots(motion) : NULL;
}

// --- Vulkan devices ---------------------------------------------------------
// The few Vulkan 1.0 declarations needed to list the physical devices, so no
// Vulkan SDK is needed to build this file.

typedef struct {
  int32_t sType;  // VK_STRUCTURE_TYPE_APPLICATION_INFO = 0
  const void *pNext;
  const char *pApplicationName;
  uint32_t applicationVersion;
  const char *pEngineName;
  uint32_t engineVersion;
  uint32_t apiVersion;
} fk_vk_application_info;

typedef struct {
  int32_t sType;  // VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO = 1
  const void *pNext;
  uint32_t flags;
  const fk_vk_application_info *pApplicationInfo;
  uint32_t enabledLayerCount;
  const char *const *ppEnabledLayerNames;
  uint32_t enabledExtensionCount;
  const char *const *ppEnabledExtensionNames;
} fk_vk_instance_create_info;

// VkPhysicalDeviceProperties begins with apiVersion, driverVersion, vendorID,
// deviceID, deviceType, then deviceName[256]; the whole struct is 824 bytes.
typedef struct {
  uint32_t apiVersion;
  uint32_t driverVersion;
  uint32_t vendorID;
  uint32_t deviceID;
  int32_t deviceType;
  char deviceName[256];
} fk_vk_properties_head;


#if defined(_WIN32)
#define FK_VKAPI __stdcall
#else
#define FK_VKAPI
#endif

#define FK_MAX_DEVICES 16
static int fk_vk_listed = 0;
static int32_t fk_vk_count = 0;
static char fk_vk_names[FK_MAX_DEVICES][256];
static int32_t fk_vk_types[FK_MAX_DEVICES];

static void fk_vk_list(void) {
  if (fk_vk_listed) return;
  fk_vk_listed = 1;
#if defined(_WIN32)
  HMODULE vk = LoadLibraryA(FK_VULKAN_LIB);
#else
  void *vk = dlopen(FK_VULKAN_LIB, RTLD_NOW | RTLD_LOCAL);
#endif
  if (!vk) return;
  int32_t(FK_VKAPI * create)(const fk_vk_instance_create_info *, const void *, void **) =
      (int32_t(FK_VKAPI *)(const fk_vk_instance_create_info *, const void *, void **))fk_symbol(vk, "vkCreateInstance");
  int32_t(FK_VKAPI * enumerate)(void *, uint32_t *, void **) =
      (int32_t(FK_VKAPI *)(void *, uint32_t *, void **))fk_symbol(vk, "vkEnumeratePhysicalDevices");
  void(FK_VKAPI * properties)(void *, void *) =
      (void(FK_VKAPI *)(void *, void *))fk_symbol(vk, "vkGetPhysicalDeviceProperties");
  void(FK_VKAPI * destroy)(void *, const void *) =
      (void(FK_VKAPI *)(void *, const void *))fk_symbol(vk, "vkDestroyInstance");
  if (!create || !enumerate || !properties || !destroy) return;
  fk_vk_application_info app;
  memset(&app, 0, sizeof app);
  app.pApplicationName = "flutter_kimodo";
  app.apiVersion = (1u << 22);  // VK_API_VERSION_1_0
  fk_vk_instance_create_info info;
  memset(&info, 0, sizeof info);
  info.sType = 1;
  info.pApplicationInfo = &app;
  void *instance = NULL;
  if (create(&info, NULL, &instance) != 0 || !instance) return;
  uint32_t count = FK_MAX_DEVICES;
  void *devices[FK_MAX_DEVICES];
  int32_t result = enumerate(instance, &count, devices);
  if (result == 0 || result == 5 /* VK_INCOMPLETE */) {
    for (uint32_t i = 0; i < count && i < FK_MAX_DEVICES; i++) {
      uint64_t storage[256];  // 2048 bytes, aligned, > sizeof(VkPhysicalDeviceProperties)
      memset(storage, 0, sizeof storage);
      properties(devices[i], storage);
      const fk_vk_properties_head *head = (const fk_vk_properties_head *)storage;
      snprintf(fk_vk_names[i], sizeof fk_vk_names[i], "%s", head->deviceName);
      fk_vk_types[i] = head->deviceType;
      fk_vk_count = (int32_t)(i + 1);
    }
  }
  destroy(instance, NULL);
}

int32_t flutter_kimodo_vulkan_device_count(void) {
  fk_vk_list();
  return fk_vk_count;
}

int32_t flutter_kimodo_vulkan_device_name(int32_t index, char *buf, int32_t buf_len) {
  fk_vk_list();
  if (index < 0 || index >= fk_vk_count) return -1;
  if (buf && buf_len > 0) snprintf(buf, (size_t)buf_len, "%s", fk_vk_names[index]);
  return (int32_t)strlen(fk_vk_names[index]);
}

int32_t flutter_kimodo_vulkan_device_type(int32_t index) {
  fk_vk_list();
  if (index < 0 || index >= fk_vk_count) return -1;
  int32_t type = fk_vk_types[index];
  return type >= 1 && type <= 4 ? type : 0;
}
