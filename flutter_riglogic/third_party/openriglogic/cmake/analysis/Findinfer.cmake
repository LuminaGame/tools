# Find infer
#
# Module dependencies:
#   FindPackageHandleStandardArgs
#
# Cache Variables:
#   INFER_ROOT_DIR
#
# Non-cache variables for users of the module:
#   infer_EXECUTABLE
#   infer_FOUND
#   infer_VERSION

file(TO_CMAKE_PATH "${INFER_ROOT_DIR}" INFER_ROOT_DIR)
set(INFER_ROOT_DIR
    "${INFER_ROOT_DIR}"
    CACHE
    PATH
    "Path to directory containing infer executable")

if(INFER_ROOT_DIR)
    find_program(infer_EXECUTABLE
        NAMES infer
        PATHS "${INFER_ROOT_DIR}"
        PATH_SUFFIXES cli
        NO_DEFAULT_PATH
        DOC "Path to infer executable")
else()
    find_program(infer_EXECUTABLE
        NAMES infer
        DOC "Path to infer executable")
endif()

mark_as_advanced(infer_EXECUTABLE infer_FOUND infer_VERSION)

include(FindPackageHandleStandardArgs)
find_package_handle_standard_args(infer
    FOUND_VAR infer_FOUND
    REQUIRED_VARS infer_EXECUTABLE
    VERSION_VAR infer_VERSION)
