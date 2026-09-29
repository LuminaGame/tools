if (TARGET gtest)
    return()
endif()

if(DEFINED ENV{GOOGLETEST_REPO_ROOT} AND NOT CME_NO_PREFETCH)
    set(git_repo $ENV{GOOGLETEST_REPO_ROOT})
else()
    set(git_repo https://github.com/google/googletest.git)
endif()

include(FetchContent)
FetchContent_Declare(googletest GIT_REPOSITORY ${git_repo} GIT_TAG ${GOOGLETEST_VERSION} GIT_SHALLOW TRUE EXCLUDE_FROM_ALL)
FetchContent_GetProperties(googletest)
if(NOT googletest_POPULATED)
    message(STATUS "Fetching GoogleTest from ${git_repo}")
    # Prevent overriding the parent project's compiler/linker settings on Windows
    set(gtest_force_shared_crt ON CACHE BOOL "" FORCE)
    # Add googletest directly to our build. This defines the gtest and gtest_main targets.
    FetchContent_MakeAvailable(googletest)
    set_target_properties(gtest gtest_main gmock gmock_main PROPERTIES FOLDER ext)
endif()
