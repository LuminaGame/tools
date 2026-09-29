# Create uninstall target
#
# Usage:
#   include(Uninstall)
#   create_uninstall_target()

set(UNINSTALL_SOURCE_DIR "${CMAKE_CURRENT_LIST_DIR}")

macro(create_uninstall_target)
    if(NOT TARGET uninstall)
        configure_file("${UNINSTALL_SOURCE_DIR}/Uninstall.cmake.in" "${CMAKE_CURRENT_BINARY_DIR}/Uninstall.cmake" IMMEDIATE @ONLY)
        add_custom_target(uninstall COMMAND ${CMAKE_COMMAND} -P ${CMAKE_CURRENT_BINARY_DIR}/Uninstall.cmake)
    endif()
endmacro()
