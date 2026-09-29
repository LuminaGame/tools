# Find glslc
#
# Module dependencies:
#   FindPackageHandleStandardArgs
#
# Cache Variables:
#   GLSLC_ROOT_DIR
#
# Non-cache variables for users of the module:
#   GLSLC_EXECUTABLE
#   GLSLC_FOUND
#   GLSLC_VERSION

file(TO_CMAKE_PATH "${GLSLC_ROOT_DIR}" GLSLC_ROOT_DIR)
set(GLSLC_ROOT_DIR
    "${GLSLC_ROOT_DIR}"
    CACHE
    PATH
    "Path to directory containing glslc executable")

if(GLSLC_ROOT_DIR)
    find_program(GLSLC_EXECUTABLE
        NAMES glslc
        PATHS "${GLSLC_ROOT_DIR}"
        NO_DEFAULT_PATH
        DOC "Path to glslc executable")
else()
    find_program(GLSLC_EXECUTABLE
        NAMES glslc
        DOC "Path to glslc executable")
endif()

mark_as_advanced(GLSLC_EXECUTABLE GLSLC_FOUND GLSLC_VERSION)

include(FindPackageHandleStandardArgs)
find_package_handle_standard_args(GLSLC
    FOUND_VAR GLSLC_FOUND
    REQUIRED_VARS GLSLC_EXECUTABLE
    VERSION_VAR GLSLC_VERSION)

