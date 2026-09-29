# Include a source or pre-built dependency.
#
# Usage:
#   include(AddPackage)
#   add_package("mypkg"
#       VERSION 1.0.0
#       GIT_REPO git@your-git-host:your-org/mypkg.git
#       GIT_TAG v1.5
#       EXPECTED_TARGET MyPkg::mypkg
#       CONFIG_NAMESPACE MPKG
#       BUILD_FROM_SOURCE ON)
#
# Module dependencies:
#   CMakeParseArguments
#   FetchContent

include(FetchContent)

function(add_package package_name)
    message(STATUS "[package] Adding ${package_name}.")
    set(options)
    set(one_value_args
        VERSION
        GIT_TAG
        GIT_REPO
        BUILD_FROM_SOURCE
        BUILD_STANDALONE
        EXCLUDE_FROM_ALL
        EXPORT_SYMBOLS
        LIBRARY_TYPE
        BUILD_PIC
        EXPECTED_TARGET
        CONFIG_NAMESPACE
        TRANSITIVE
        COMPATIBILITY)
    set(multi_value_args)
    cmake_parse_arguments(ARG "${options}" "${one_value_args}" "${multi_value_args}" ${ARGN})

    if(TARGET ${ARG_EXPECTED_TARGET})
        message(STATUS "[package] ${package_name} already added, rely on existing targets.")
        return()
    endif()

    if(NOT ARG_BUILD_FROM_SOURCE)
        message(STATUS "[package] Find pre-built package ${package_name}.")
        find_package(${package_name} ${ARG_VERSION} ${ARG_UNPARSED_ARGUMENTS})
        return()
    endif()

    string(TOLOWER ${package_name} package_name_norm)
    string(TOUPPER ${package_name} package_name_external)

    if(DEFINED ENV{${package_name_external}_REPO_ROOT} AND NOT CME_NO_PREFETCH)
        set(git_repo $ENV{${package_name_external}_REPO_ROOT})
    else()
        set(git_repo ${ARG_GIT_REPO})
    endif()

    if(DEFINED ARG_EXCLUDE_FROM_ALL)
        set(declare_extra_args EXCLUDE_FROM_ALL)
    endif()

    FetchContent_Declare(${package_name_norm}
        GIT_REPOSITORY ${git_repo}
        GIT_TAG ${ARG_GIT_TAG}
        GIT_SHALLOW TRUE
        ${declare_extra_args})
    FetchContent_GetProperties(${package_name_norm})
    if(NOT ${package_name_norm}_POPULATED)
        message(STATUS "[package] Fetching ${package_name} from ${git_repo}")
        set(${ARG_CONFIG_NAMESPACE}_BUILD_BENCHMARKS OFF)
        set(${ARG_CONFIG_NAMESPACE}_BUILD_EXAMPLES OFF)
        set(${ARG_CONFIG_NAMESPACE}_BUILD_TESTS OFF)
        if(DEFINED ARG_BUILD_PIC)
            set(${ARG_CONFIG_NAMESPACE}_BUILD_PIC ${ARG_BUILD_PIC})
        endif()
        if(DEFINED ARG_BUILD_STANDALONE)
            set(${ARG_CONFIG_NAMESPACE}_BUILD_STANDALONE ${ARG_BUILD_STANDALONE})
        endif()
        if(DEFINED ARG_EXPORT_SYMBOLS)
            set(${ARG_CONFIG_NAMESPACE}_EXPORT_SYMBOLS ${ARG_EXPORT_SYMBOLS})
        endif()
        if(DEFINED ARG_LIBRARY_TYPE)
            set(${ARG_CONFIG_NAMESPACE}_LIBRARY_TYPE ${ARG_LIBRARY_TYPE} CACHE STRING "" FORCE)
        endif()
        FetchContent_MakeAvailable(${package_name_norm})
        message(STATUS "[package] ${package_name} added.")
    else()
        message(STATUS "[package] ${package_name} source already fetched, rely on existing package.")
    endif()
    set(${package_name_norm}_SOURCE_DIR ${${package_name_norm}_SOURCE_DIR} PARENT_SCOPE)
endfunction()
