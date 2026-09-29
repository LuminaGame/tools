# lumina_mouse_capture (lumina todo/input/04): the Linux side of the plugin.
cmake_minimum_required(VERSION 3.10)

set(PROJECT_NAME "lumina_mouse_capture")
project(${PROJECT_NAME} LANGUAGES C CXX)

set(PLUGIN_NAME "lumina_mouse_capture_plugin")

list(APPEND PLUGIN_SOURCES
  "lumina_mouse_capture_plugin.cc"
  "mouse_capture_core.cc"
)

add_library(${PLUGIN_NAME} SHARED
  ${PLUGIN_SOURCES}
)

apply_standard_settings(${PLUGIN_NAME})

set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)

target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter)
target_link_libraries(${PLUGIN_NAME} PRIVATE PkgConfig::GTK)

# Wayland pointer lock: the pointer-constraints and relative-pointer protocols
# are generated with wayland-scanner from the system's wayland-protocols.
# Without them the plugin still builds and reports no Wayland support.
find_package(PkgConfig REQUIRED)
pkg_check_modules(LMC_WAYLAND_CLIENT IMPORTED_TARGET wayland-client)
pkg_get_variable(LMC_WAYLAND_PROTOCOLS_DIR wayland-protocols pkgdatadir)
find_program(LMC_WAYLAND_SCANNER wayland-scanner)
set(LMC_PROTOCOLS pointer-constraints relative-pointer)
set(LMC_HAVE_PROTOCOLS FALSE)
if(LMC_WAYLAND_CLIENT_FOUND AND LMC_WAYLAND_SCANNER AND LMC_WAYLAND_PROTOCOLS_DIR)
  set(LMC_HAVE_PROTOCOLS TRUE)
  foreach(proto ${LMC_PROTOCOLS})
    if(NOT EXISTS "${LMC_WAYLAND_PROTOCOLS_DIR}/unstable/${proto}/${proto}-unstable-v1.xml")
      set(LMC_HAVE_PROTOCOLS FALSE)
    endif()
  endforeach()
endif()

if(LMC_HAVE_PROTOCOLS)
  set(LMC_GEN_DIR "${CMAKE_CURRENT_BINARY_DIR}/wayland-protocols")
  file(MAKE_DIRECTORY "${LMC_GEN_DIR}")
  foreach(proto ${LMC_PROTOCOLS})
    set(xml "${LMC_WAYLAND_PROTOCOLS_DIR}/unstable/${proto}/${proto}-unstable-v1.xml")
    set(header "${LMC_GEN_DIR}/${proto}-unstable-v1-client-protocol.h")
    set(code "${LMC_GEN_DIR}/${proto}-unstable-v1-protocol.c")
    add_custom_command(OUTPUT "${header}"
      COMMAND ${LMC_WAYLAND_SCANNER} client-header "${xml}" "${header}"
      DEPENDS "${xml}")
    add_custom_command(OUTPUT "${code}"
      COMMAND ${LMC_WAYLAND_SCANNER} private-code "${xml}" "${code}"
      DEPENDS "${xml}")
    list(APPEND LMC_PROTOCOL_HEADERS "${header}")
    list(APPEND LMC_PROTOCOL_SOURCES "${code}")
  endforeach()
  # Generated C, compiled without the plugin's -Werror.
  add_library(lumina_mouse_capture_wayland_protocols OBJECT
    ${LMC_PROTOCOL_SOURCES} ${LMC_PROTOCOL_HEADERS})
  set_target_properties(lumina_mouse_capture_wayland_protocols PROPERTIES
    POSITION_INDEPENDENT_CODE ON
    C_VISIBILITY_PRESET hidden)
  target_link_libraries(lumina_mouse_capture_wayland_protocols PRIVATE PkgConfig::LMC_WAYLAND_CLIENT)
  target_sources(${PLUGIN_NAME} PRIVATE
    $<TARGET_OBJECTS:lumina_mouse_capture_wayland_protocols> ${LMC_PROTOCOL_HEADERS})
  target_include_directories(${PLUGIN_NAME} PRIVATE "${LMC_GEN_DIR}")
  target_compile_definitions(${PLUGIN_NAME} PRIVATE LUMINA_MC_WAYLAND_PROTOCOLS=1)
  target_link_libraries(${PLUGIN_NAME} PRIVATE PkgConfig::LMC_WAYLAND_CLIENT)
else()
  message(WARNING "lumina_mouse_capture: wayland-client, wayland-scanner or "
    "wayland-protocols (pointer-constraints, relative-pointer) not found; "
    "building without the Wayland pointer lock.")
endif()

# List of absolute paths to libraries that should be bundled with the plugin.
set(lumina_mouse_capture_bundled_libraries
  ""
  PARENT_SCOPE
)
