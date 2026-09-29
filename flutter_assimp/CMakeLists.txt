cmake_minimum_required(VERSION 3.19)
project(flutter_assimp_c CXX C)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

include_directories(
    src
    /usr/include
)

add_library(flutter_assimp SHARED
    src/assimp_bridge.cpp
)

target_link_libraries(flutter_assimp PRIVATE
    assimp
)
