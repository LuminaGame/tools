# lumina_mouse_capture: the Windows side of the plugin.
cmake_minimum_required(VERSION 3.14)

set(PROJECT_NAME "lumina_mouse_capture")
project(${PROJECT_NAME} LANGUAGES CXX)

cmake_policy(VERSION 3.14...3.25)

set(PLUGIN_NAME "lumina_mouse_capture_plugin")

# pointer_capture.cpp is the state machine (tested against a fake OS in
# test/); win32_pointer_os.cpp is the only file that touches the pointer.
list(APPEND PLUGIN_SOURCES
  "lumina_mouse_capture_plugin.cpp"
  "lumina_mouse_capture_plugin.h"
  "pointer_capture.cpp"
  "pointer_capture.h"
  "pointer_os.h"
  "win32_pointer_os.cpp"
)

add_library(${PLUGIN_NAME} SHARED
  "include/lumina_mouse_capture/lumina_mouse_capture_plugin_c_api.h"
  "lumina_mouse_capture_plugin_c_api.cpp"
  ${PLUGIN_SOURCES}
)

apply_standard_settings(${PLUGIN_NAME})

set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL NOMINMAX)

target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter flutter_wrapper_plugin user32)

# List of absolute paths to libraries that should be bundled with the plugin.
set(lumina_mouse_capture_bundled_libraries
  ""
  PARENT_SCOPE
)
