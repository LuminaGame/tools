# The capture state machine's tests against a fake OS layer. Links only the
# state machine: the real Win32 layer (win32_pointer_os.cpp) is not part of
# this target, so nothing it builds can clip, hide or move the pointer.
cmake_minimum_required(VERSION 3.14)
project(lumina_mouse_capture_tests LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_executable(pointer_capture_tests
  pointer_capture_test.cpp
  ../pointer_capture.cpp
)
target_compile_definitions(pointer_capture_tests PRIVATE
  WIN32_LEAN_AND_MEAN NOMINMAX UNICODE _UNICODE)
if(MSVC)
  target_compile_options(pointer_capture_tests PRIVATE /W4 /WX /utf-8)
endif()
