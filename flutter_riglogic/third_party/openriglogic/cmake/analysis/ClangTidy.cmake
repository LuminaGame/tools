# Creates a custom clang-tidy target for each given target
#
# Usage:
#   include(ClangTidy)
#   set_target_properties(target1 PROPERTIES SOURCE_ROOT "/path/to/src1")
#   set_target_properties(target2 PROPERTIES SOURCE_ROOT "/path/to/src2")
#   clangtidy_targets(target1 target2 ...)
#
# or in order to use CMake's built-in clang-tidy support
# without adding a custom clang-tidy target:
#
#   auto_clangtidy_targets(target1 target2 ...)
#
# Module dependencies:
#   FindClangTidy.cmake
#   FindRunClangTidy.cmake

if(NOT ClangTidy_FOUND)
    find_package(ClangTidy)
endif()
if(NOT RunClangTidy_FOUND)
    find_package(RunClangTidy)
endif()

function(_clangtidy_target target_name)
    set(include_dirs "$<TARGET_PROPERTY:${target_name},INCLUDE_DIRECTORIES>")
    set(source_root "$<TARGET_PROPERTY:${target_name},SOURCE_ROOT>")
    get_filename_component(project_bin_dir ${CME_COMPILATION_DATABASE_PATH} DIRECTORY)
    add_custom_target(${target_name}-clangtidy
        COMMAND
            ${RunClangTidy_EXECUTABLE}
            "-clang-tidy-binary=${ClangTidy_EXECUTABLE}"
            "-p=${project_bin_dir}"
            "-header-filter=($<JOIN:$<FILTER:${include_dirs},EXCLUDE,${project_bin_dir}/.*>,|>)/.*"
            "-quiet"
            "${source_root}/.*"
        WORKING_DIRECTORY ${project_bin_dir}
        VERBATIM)
    set_property(TARGET ${target_name}-clangtidy PROPERTY
        FOLDER static-analysis)
endfunction()

# Add a custom analysis target for running clang-tidy
function(clangtidy_targets)
    if(NOT ClangTidy_EXECUTABLE OR NOT RunClangTidy_EXECUTABLE)
        return()
    endif()

    if(NOT CMAKE_EXPORT_COMPILE_COMMANDS OR NOT (CMAKE_GENERATOR MATCHES "Make|Ninja"))
        message(STATUS "No compilation database available with the selected generator.")
        return()
    endif()

    if(NOT DEFINED CME_COMPILATION_DATABASE_PATH)
        message(STATUS "No compilation database available.")
        return()
    endif()

    foreach(target_name IN LISTS ARGN)
        _clangtidy_target(${target_name})
    endforeach()
endfunction()

# Use CMake's built-in clang-tidy support to integrate the tool
function(auto_clangtidy_targets)
    if(NOT ClangTidy_EXECUTABLE)
        return()
    endif()

    foreach(target_name IN LISTS ARGN)
        set_target_properties(${target_name} PROPERTIES
            CXX_CLANG_TIDY ${ClangTidy_EXECUTABLE})
    endforeach()
endfunction()

