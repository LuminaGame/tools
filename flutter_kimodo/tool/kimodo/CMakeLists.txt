# Builds kimodo.cpp (a checkout at KIMODO_SOURCE_DIR) with flutter_kimodo's C
# entry points (native/kimodo_lumina.cpp) compiled into the kimodo library.
# Driven by tool/build_kimodo.ps1 / tool/build_kimodo.sh.
cmake_minimum_required(VERSION 3.25)
project(kimodo_lumina LANGUAGES C CXX)

set(KIMODO_SOURCE_DIR "" CACHE PATH "kimodo.cpp checkout (with its ggml submodule)")
if(NOT EXISTS "${KIMODO_SOURCE_DIR}/CMakeLists.txt")
  message(FATAL_ERROR "KIMODO_SOURCE_DIR does not hold kimodo.cpp: ${KIMODO_SOURCE_DIR}")
endif()

add_subdirectory("${KIMODO_SOURCE_DIR}" kimodo)

set(LUMINA_NATIVE_DIR "${CMAKE_CURRENT_LIST_DIR}/../../native")
target_sources(kimodo PRIVATE "${LUMINA_NATIVE_DIR}/kimodo_lumina.cpp")
target_include_directories(kimodo PUBLIC "$<BUILD_INTERFACE:${LUMINA_NATIVE_DIR}>")

if(NOT WIN32)
  # Find the ggml libraries next to libkimodo.so wherever it is unpacked.
  foreach(t kimodo ggml ggml-base ggml-cpu ggml-vulkan)
    if(TARGET ${t})
      set_target_properties(${t} PROPERTIES BUILD_RPATH "\$ORIGIN" INSTALL_RPATH "\$ORIGIN")
    endif()
  endforeach()
endif()
