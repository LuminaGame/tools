# Creates a custom infer target for each given target
#
# Usage:
#   include(Infer)
#   infer_targets(target1 target2 ...)
#
# Module dependencies:
#   Findinfer.cmake

if(NOT infer_FOUND)
    find_package(infer)
endif()

option(CME_INFER_CRASH_WORKAROUND "Enable workaround to avoid crashes under Ubuntu / WSL (reduced performance)" ON)

function(_infer_target target_name)
    get_filename_component(project_bin_dir ${CME_COMPILATION_DATABASE_PATH} DIRECTORY)
    if(CME_INFER_CRASH_WORKAROUND)
        set(infer_flags -j 1)
    endif()
    add_custom_target(${target_name}-infer
        COMMAND ${infer_EXECUTABLE} run --compilation-database ${CME_COMPILATION_DATABASE_PATH} ${infer_flags}
        WORKING_DIRECTORY ${project_bin_dir}
        VERBATIM)
    set_property(TARGET ${target_name}-infer PROPERTY
        FOLDER static-analysis)
endfunction()

function(infer_targets)
    if(NOT infer_EXECUTABLE)
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
        _infer_target(${target_name})
    endforeach()
endfunction()
