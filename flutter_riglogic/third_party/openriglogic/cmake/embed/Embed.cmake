# Create a custom embed target that generates a header file containing the
# binary data of the specified input file in a const char array, along with
# the size of the data, whenever a build of the specified target is triggered.
#
# Usage:
#   include(Embed)
#   embed(target_name "/path/to/input.bin" "/path/to/header.h")
#
# Module dependencies:
#   CMakeParseArguments

if(NOT EMBED_EXECUTE)
    # This branch executes at configuration time when included
    if(EMBED_SCRIPT)
        return()
    endif()

    set(EMBED_SOURCE_DIR "${CMAKE_CURRENT_LIST_DIR}")
    set(EMBED_SCRIPT "${CMAKE_CURRENT_LIST_FILE}")
    set(EMBED_DEFAULT_PROLOGUE "#pragma once")
    set(EMBED_DEFAULT_EPILOGUE "")
    set(EMBED_DEFAULT_DATA_VARNAME "buffer")
    set(EMBED_DEFAULT_SIZE_VARNAME "buffer_size")

    macro(set_default variable default_value)
        if(NOT ${variable})
            set(${variable} ${default_value})
        endif()
    endmacro()

    function(embed target_name input_path output_path)
        set(options REMOVE_INPUT)
        set(one_value_args PROLOGUE
                        EPILOGUE
                        DATA_VARNAME
                        SIZE_VARNAME)
        set(multi_value_args)
        cmake_parse_arguments(EMBED "${options}" "${one_value_args}" "${multi_value_args}" ${ARGN})

        set_default(EMBED_PROLOGUE "${EMBED_DEFAULT_PROLOGUE}")
        set_default(EMBED_EPILOGUE "${EMBED_DEFAULT_EPILOGUE}")
        set_default(EMBED_DATA_VARNAME "${EMBED_DEFAULT_DATA_VARNAME}")
        set_default(EMBED_SIZE_VARNAME "${EMBED_DEFAULT_SIZE_VARNAME}")

        set(EMBED_COMMAND "${CMAKE_COMMAND}"
            "-D" "EMBED_EXECUTE=TRUE"
            "-D" "EMBED_SOURCE_DIR=${EMBED_SOURCE_DIR}"
            "-D" "EMBED_PROLOGUE=${EMBED_PROLOGUE}"
            "-D" "EMBED_EPILOGUE=${EMBED_EPILOGUE}"
            "-D" "EMBED_DATA_VARNAME=${EMBED_DATA_VARNAME}"
            "-D" "EMBED_SIZE_VARNAME=${EMBED_SIZE_VARNAME}"
            "-D" "EMBED_REMOVE_INPUT=${EMBED_REMOVE_INPUT}"
            "-D" "EMBED_INPUT_PATH=${input_path}"
            "-D" "EMBED_OUTPUT_PATH=${output_path}"
            "-P" "${EMBED_SCRIPT}")

        set(embed_target_name "${target_name}-embed")
        add_custom_target(${embed_target_name}
            COMMAND ${EMBED_COMMAND}
            BYPRODUCTS ${output_path}
            VERBATIM)

        # Make sure embedding is done before the build of the
        # specified target is started
        add_dependencies(${target_name} ${embed_target_name})
        set_property(TARGET ${embed_target_name} PROPERTY FOLDER embed)
        set(EMBED_TARGET "${embed_target_name}" PARENT_SCOPE)
    endfunction()
else()
    # This branch executes at build time and performs the actual embedding
    file(READ ${EMBED_INPUT_PATH} EMBED_DATA HEX)
    # Convert concatenated hex values to C-style hex notation to initialize array
    string(REGEX REPLACE "([0-9a-f][0-9a-f])" "0x\\1, " EMBED_DATA ${EMBED_DATA})
    # Drop last two characters (trailing comma + whitespace)
    string(LENGTH ${EMBED_DATA} EMBED_SIZE)
    math(EXPR EMBED_SIZE "${EMBED_SIZE}-2")
    string(SUBSTRING ${EMBED_DATA} 0 ${EMBED_SIZE} EMBED_DATA)

    configure_file("${EMBED_SOURCE_DIR}/Template.h.in" ${EMBED_OUTPUT_PATH} @ONLY)

    if(EMBED_REMOVE_INPUT)
        file(REMOVE ${EMBED_INPUT_PATH})
    endif()
endif()
