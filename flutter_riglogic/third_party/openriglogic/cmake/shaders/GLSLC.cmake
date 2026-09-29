# Create a custom glslc target to compile the given shaders
# whenever a build of the specified target is triggered
#
# Usage:
#   include(GLSLC)
#   glslc(target_name "/path/to/shader" "/path/to/output.spv")
#
# Module dependencies:
#   FindGLSLC.cmake
#   ExpandCommand.cmake

if(NOT GLSLC_FOUND)
    find_package(GLSLC)
endif()

include(ExpandCommand)

function(glslc target_name shader_path output_path)
    if(NOT GLSLC_EXECUTABLE)
        message(WARNING "GLSLC executable not found. Set \
                         -DGLSLC_ROOT_DIR=/path/to/glslc to enable it.")
        return()
    endif()

    expandable_command(glslc_cmd ${CMAKE_CURRENT_SOURCE_DIR}
        ${GLSLC_EXECUTABLE}
        ${shader_path}
        $<IF:$<CONFIG:Debug>,-g -O0,-O>
        -o ${output_path})

    set(glslc_target_name "${target_name}-glslc")
    add_custom_target(${glslc_target_name}
        COMMAND ${glslc_cmd}
        BYPRODUCTS ${output_path}
        VERBATIM)

    # Make sure the shader is compiled before the build of the
    # specified target is started
    add_dependencies(${target_name} ${glslc_target_name})
    set_property(TARGET ${glslc_target_name} PROPERTY FOLDER shaders)
    set(GLSLC_TARGET "${glslc_target_name}" PARENT_SCOPE)
endfunction()
