# Orchestrates the creation of all possible linter targets and additionally
# creates wrapper targets that can trigger the execution of all linters
#
# Usage:
#   include(Analysis)
#   analyze_targets(target1 target2 ...)
#
# Module dependencies:
#   ClangTidy.cmake
#   ClangStaticAnalyzer.cmake
#   CppCheck.cmake
#   Infer.cmake

include(ClangTidy)
include(ClangStaticAnalyzer)
include(CppCheck)
include(Infer)

function(_analyze_target target_name parent_target_name all_clangtidy_target_name
                                                        all_clang_static_analyzer_target_name
                                                        all_cppcheck_target_name
                                                        all_infer_target_name)
    clangtidy_targets(${target_name})
    if(TARGET "${target_name}-clangtidy")
        add_dependencies(${parent_target_name} "${target_name}-clangtidy")
        add_dependencies(${all_clangtidy_target_name} "${target_name}-clangtidy")
        message(STATUS "[analysis] ${target_name}-clangtidy added.")
    endif()

    clang_static_analyze_targets(${target_name})
    if(TARGET "${target_name}-clang-static-analyze")
        add_dependencies(${parent_target_name} "${target_name}-clang-static-analyze")
        add_dependencies(${all_clang_static_analyzer_target_name} "${target_name}-clang-static-analyze")
        message(STATUS "[analysis] ${target_name}-clang-static-analyze added.")
    endif()

    cppcheck_targets(${target_name})
    if(TARGET "${target_name}-cppcheck")
        add_dependencies(${parent_target_name} "${target_name}-cppcheck")
        add_dependencies(${all_cppcheck_target_name} "${target_name}-cppcheck")
        message(STATUS "[analysis] ${target_name}-cppcheck added.")
    endif()

    infer_targets(${target_name})
    if(TARGET "${target_name}-infer")
        add_dependencies(${parent_target_name} "${target_name}-infer")
        add_dependencies(${all_infer_target_name} "${target_name}-infer")
        message(STATUS "[analysis] ${target_name}-infer added.")
    endif()

endfunction()

function(analyze_targets)
    set(wrapper_target_name analysis)
    set(all_analysis_target_name all-analysis)
    set(all_clangtidy_target_name all-clangtidy)
    set(all_clang_static_analyzer_target_name all-clang-static-analyze)
    set(all_cppcheck_target_name all-cppcheck)
    set(all_infer_target_name all-infer)
    set(label_name "static-analysis")

    # Set up global analysis targets (which will trigger the requested analysis type for all available targets)
    if(NOT TARGET ${all_analysis_target_name})
        add_custom_target(${all_analysis_target_name})
        set_property(TARGET ${all_analysis_target_name} PROPERTY FOLDER ${label_name})
    endif()

    if(NOT TARGET ${all_clangtidy_target_name})
        add_custom_target(${all_clangtidy_target_name})
        set_property(TARGET ${all_clangtidy_target_name} PROPERTY FOLDER ${label_name})
        add_dependencies(${all_analysis_target_name} ${all_clangtidy_target_name})
    endif()

    if(NOT TARGET ${all_clang_static_analyzer_target_name})
        add_custom_target(${all_clang_static_analyzer_target_name})
        set_property(TARGET ${all_clang_static_analyzer_target_name} PROPERTY FOLDER ${label_name})
        add_dependencies(${all_analysis_target_name} ${all_clang_static_analyzer_target_name})
    endif()

    if(NOT TARGET ${all_cppcheck_target_name})
        add_custom_target(${all_cppcheck_target_name})
        set_property(TARGET ${all_cppcheck_target_name} PROPERTY FOLDER ${label_name})
        add_dependencies(${all_analysis_target_name} ${all_cppcheck_target_name})
    endif()

    if(NOT TARGET ${all_infer_target_name})
        add_custom_target(${all_infer_target_name})
        set_property(TARGET ${all_infer_target_name} PROPERTY FOLDER ${label_name})
        add_dependencies(${all_analysis_target_name} ${all_infer_target_name})
    endif()

    foreach(target_name IN LISTS ARGN)
        if(TARGET ${target_name})
            set(analysis_target_name "${target_name}-${wrapper_target_name}")
            add_custom_target(${analysis_target_name})
            set_property(TARGET ${analysis_target_name} PROPERTY FOLDER ${label_name})
            _analyze_target(${target_name}
                            ${analysis_target_name}
                            ${all_clangtidy_target_name}
                            ${all_clang_static_analyzer_target_name}
                            ${all_cppcheck_target_name}
                            ${all_infer_target_name})
        endif()
    endforeach()
endfunction()
