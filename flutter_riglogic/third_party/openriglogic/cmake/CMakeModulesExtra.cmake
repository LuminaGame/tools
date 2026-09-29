set(CMakeModulesExtra_DIRS "${CMAKE_CURRENT_LIST_DIR}/analysis"
                           "${CMAKE_CURRENT_LIST_DIR}/benchmarks"
                           "${CMAKE_CURRENT_LIST_DIR}/embed"
                           "${CMAKE_CURRENT_LIST_DIR}/formatting"
                           "${CMAKE_CURRENT_LIST_DIR}/install"
                           "${CMAKE_CURRENT_LIST_DIR}/packages"
                           "${CMAKE_CURRENT_LIST_DIR}/sanitizers"
                           "${CMAKE_CURRENT_LIST_DIR}/shaders"
                           "${CMAKE_CURRENT_LIST_DIR}/snapshot"
                           "${CMAKE_CURRENT_LIST_DIR}/symbols"
                           "${CMAKE_CURRENT_LIST_DIR}/tests"
                           "${CMAKE_CURRENT_LIST_DIR}/utilities"
                           "${CMAKE_CURRENT_LIST_DIR}/version")
list(APPEND CMAKE_MODULE_PATH ${CMakeModulesExtra_DIRS})