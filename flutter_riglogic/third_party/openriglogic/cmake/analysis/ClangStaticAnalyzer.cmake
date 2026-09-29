# Creates a custom clang-static-analyze target for each given target
#
# Usage:
#   include(ClangStaticAnalyzer)
#   clang_static_analyze_targets(target1 target2 ...)

if(NOT Python3_FOUND)
    find_package(Python3 COMPONENTS Interpreter)
endif()

set(CLANG_STATIC_ANALYZER_RUNNER_SCRIPT_DIR ${CMAKE_CURRENT_LIST_DIR})

function(_clang_static_analyze_target target_name)
    set(source_root "$<TARGET_PROPERTY:${target_name},SOURCE_ROOT>")
    add_custom_target(${target_name}-clang-static-analyze
        COMMAND ${Python3_EXECUTABLE} "${CLANG_STATIC_ANALYZER_RUNNER_SCRIPT_DIR}/ClangStaticAnalyzer.py" --compilation-database ${CME_COMPILATION_DATABASE_PATH} --include-dir ${source_root}
        WORKING_DIRECTORY ${PROJECT_BINARY_DIR}
        VERBATIM)
    set_property(TARGET ${target_name}-clang-static-analyze PROPERTY
        FOLDER static-analysis)
endfunction()

function(clang_static_analyze_targets)
    if(NOT Python3_EXECUTABLE)
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
        _clang_static_analyze_target(${target_name})
    endforeach()
endfunction()
