# Find uncrustify
#
# Module dependencies:
#   FindPackageHandleStandardArgs
#
# Cache Variables:
#   UNCRUSTIFY_ROOT_DIR
#
# Non-cache variables for users of the module:
#   Uncrustify_EXECUTABLE
#   Uncrustify_FOUND
#   Uncrustify_VERSION

file(TO_CMAKE_PATH "${UNCRUSTIFY_ROOT_DIR}" UNCRUSTIFY_ROOT_DIR)
set(UNCRUSTIFY_ROOT_DIR
    "${UNCRUSTIFY_ROOT_DIR}"
    CACHE
    PATH
    "Path to directory containing uncrustify executable")

if(UNCRUSTIFY_ROOT_DIR)
    find_program(Uncrustify_EXECUTABLE
        NAMES uncrustify
        PATHS "${UNCRUSTIFY_ROOT_DIR}"
        NO_DEFAULT_PATH
        DOC "Path to uncrustify executable")
else()
    find_program(Uncrustify_EXECUTABLE
        NAMES uncrustify
        DOC "Path to uncrustify executable")
endif()

mark_as_advanced(Uncrustify_EXECUTABLE Uncrustify_FOUND Uncrustify_VERSION)

include(FindPackageHandleStandardArgs)
find_package_handle_standard_args(Uncrustify
    FOUND_VAR Uncrustify_FOUND
    REQUIRED_VARS Uncrustify_EXECUTABLE
    VERSION_VAR Uncrustify_VERSION)

