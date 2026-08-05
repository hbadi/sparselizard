# One executable per examples/<name>/main.cpp, discovered rather than listed, so
# that adding an example needs no edit here.
#
# Layout produced in the build tree:
#
#   bin/<name>            every executable, next to the shared library
#   examples/<name>/      one working directory per example
#
# The split is forced by the examples themselves: they reference their mesh
# relatively, as in mesh("1d.msh"), and write their results relatively too, as in
# write(all, "u.vtu", 2). Several examples use the same file names -- disk.msh,
# quad.msh, cmut2d.msh, u.vtu -- so a shared working directory would have them
# overwrite each other. The binaries, on the other hand, are all unique and can
# share one directory, which is what keeps a single copy of the shared library.

file(GLOB _example_mains CONFIGURE_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/*/main.cpp")
list(SORT _example_mains)

# Loader search path for the tests. CTest applies this per test, so running an
# example needs no prepared shell and no copied library: the third-party shared
# libraries stay where they were installed and only their directories travel.
if(WIN32)
    set(_path_var PATH)
elseif(APPLE)
    set(_path_var DYLD_LIBRARY_PATH)
else()
    set(_path_var LD_LIBRARY_PATH)
endif()

set(_env_mod)
foreach(_d IN LISTS SPARSELIZARD_RUNTIME_PATHS)
    file(TO_NATIVE_PATH "${_d}" _nd)
    list(APPEND _env_mod "${_path_var}=path_list_prepend:${_nd}")
endforeach()

set(_example_targets)

set(_skipped_examples)

foreach(_main IN LISTS _example_mains)
    get_filename_component(_dir "${_main}" DIRECTORY)
    get_filename_component(_name "${_dir}" NAME)

    # An example that reaches for an optional dependency cannot be built when
    # that dependency is off. Read the requirement from the source instead of
    # maintaining a list here, so that a failure means a real defect rather than
    # a disabled option.
    file(READ "${_main}" _src)
    if(_src MATCHES "gmsh\\.h" AND NOT SPARSELIZARD_ENABLE_GMSH)
        list(APPEND _skipped_examples "${_name} (needs SPARSELIZARD_ENABLE_GMSH)")
        continue()
    endif()

    add_executable(${_name} "${_main}")
    target_link_libraries(${_name} PRIVATE sparselizard)
    list(APPEND _example_targets ${_name})

    # Stage the data files next to nothing but themselves.
    set(_workdir "${CMAKE_BINARY_DIR}/examples/${_name}")
    file(MAKE_DIRECTORY "${_workdir}")

    file(GLOB _data "${_dir}/*")
    foreach(_f IN LISTS _data)
        if(NOT IS_DIRECTORY "${_f}" AND NOT _f STREQUAL _main)
            get_filename_component(_fn "${_f}" NAME)
            configure_file("${_f}" "${_workdir}/${_fn}" COPYONLY)
        endif()
    endforeach()

    # Running an example is then a matter of ctest -R <name>, which takes care of
    # the working directory. Started by hand it is
    #   cd examples/<name> && ../../bin/<name>
    add_test(NAME ${_name}
             COMMAND $<TARGET_FILE:${_name}>
             WORKING_DIRECTORY "${_workdir}")
    set_tests_properties(${_name} PROPERTIES
        ENVIRONMENT_MODIFICATION "${_env_mod}"
        TIMEOUT 600)
endforeach()

# Convenience target: build every example without building anything else.
if(_example_targets)
    add_custom_target(examples DEPENDS ${_example_targets})
    list(LENGTH _example_targets _n)
    message(STATUS "Examples: ${_n} target(s)")
endif()

foreach(_s IN LISTS _skipped_examples)
    message(STATUS "Examples: skipping ${_s}")
endforeach()
