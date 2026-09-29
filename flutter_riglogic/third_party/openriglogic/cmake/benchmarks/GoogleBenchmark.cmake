if (TARGET benchmark)
    return()
endif()

if(DEFINED ENV{GOOGLEBENCHMARK_REPO_ROOT} AND NOT CME_NO_PREFETCH)
    set(git_repo $ENV{GOOGLEBENCHMARK_REPO_ROOT})
else()
    set(git_repo https://github.com/google/benchmark.git)
endif()

include(FetchContent)
FetchContent_Declare(googlebenchmark GIT_REPOSITORY ${git_repo} GIT_TAG ${GOOGLEBENCHMARK_VERSION} GIT_SHALLOW TRUE EXCLUDE_FROM_ALL)
FetchContent_GetProperties(googlebenchmark)
if(NOT googlebenchmark_POPULATED)
    message(STATUS "Fetching GoogleBenchmark from ${git_repo}")
    # Don't build tests for google-benchmark
    set(BENCHMARK_ENABLE_TESTING OFF CACHE BOOL "" FORCE)
    # Add googlebenchmark directly to our build. This defines the benchmark target.
    FetchContent_MakeAvailable(googlebenchmark)
    set_target_properties(benchmark PROPERTIES FOLDER ext)
endif()
