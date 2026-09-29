# Creates a custom uncrustify target to format the given files
# whenever a build of the specified target is triggered
#
# Usage:
#   include(Uncrustify)
#   uncrustify(target_name uncrustify.cfg file1.cpp file2.h file3.cpp ...)
#
# Module dependencies:
#   FindUncrustify.cmake
#   ExpandCommand.cmake

if(NOT Uncrustify_FOUND)
    find_package(Uncrustify)
endif()

include(ExpandCommand)

function(uncrustify target_name conf_path file_list)
    if(NOT Uncrustify_EXECUTABLE)
        return()
    endif()

    cmake_parse_arguments(ARG "QUIET" "" "" ${ARGN})
    if(ARG_QUIET)
        set(uncrustify_args "-q")
    endif()

    set(uncrustify_target uncrustify-${target_name})
    expandable_command(uncrustify_cmd ${CMAKE_CURRENT_SOURCE_DIR}
        ${Uncrustify_EXECUTABLE}
        -c ${conf_path}
        --replace
        --no-backup
        ${uncrustify_args}
        ${file_list})
    add_custom_target(${uncrustify_target}
        COMMAND ${uncrustify_cmd}
        VERBATIM)

    # Make sure source code formatting is done before the build of the
    # specified target is started
    add_dependencies(${target_name} ${uncrustify_target})

    set_property(TARGET ${uncrustify_target} PROPERTY FOLDER formatting)
endfunction()
