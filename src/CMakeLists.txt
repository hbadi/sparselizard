set(SRC_DIR_LIST
  ${CMAKE_CURRENT_SOURCE_DIR}
  ${CMAKE_CURRENT_SOURCE_DIR}/resolution
  ${CMAKE_CURRENT_SOURCE_DIR}/shapefunction
  ${CMAKE_CURRENT_SOURCE_DIR}/shapefunction/lagrange
  ${CMAKE_CURRENT_SOURCE_DIR}/shapefunction/hierarchical
  ${CMAKE_CURRENT_SOURCE_DIR}/shapefunction/hierarchical/h1
  ${CMAKE_CURRENT_SOURCE_DIR}/shapefunction/hierarchical/hcurl
  ${CMAKE_CURRENT_SOURCE_DIR}/mesh
  ${CMAKE_CURRENT_SOURCE_DIR}/formulation
  ${CMAKE_CURRENT_SOURCE_DIR}/field
  ${CMAKE_CURRENT_SOURCE_DIR}/io
  ${CMAKE_CURRENT_SOURCE_DIR}/io/nastran
  ${CMAKE_CURRENT_SOURCE_DIR}/io/paraview
  ${CMAKE_CURRENT_SOURCE_DIR}/io/gmsh
  ${CMAKE_CURRENT_SOURCE_DIR}/geometry
  ${CMAKE_CURRENT_SOURCE_DIR}/expression
  ${CMAKE_CURRENT_SOURCE_DIR}/expression/operation
  ${CMAKE_CURRENT_SOURCE_DIR}/gausspoint)

custom_add_library_from_dir(sparselizard "${SRC_DIR_LIST}")
custom_copy_file(sparselizard "${SRC_DIR_LIST}" "${SPARSELIZARD_INCLUDE_STAGE_DIR}" "*.h")

foreach(_d IN LISTS SRC_DIR_LIST)
    target_include_directories(sparselizard PUBLIC $<BUILD_INTERFACE:${_d}>)
endforeach()
target_include_directories(sparselizard PUBLIC
    $<BUILD_INTERFACE:${SPARSELIZARD_INCLUDE_STAGE_DIR}>
    $<INSTALL_INTERFACE:${CMAKE_INSTALL_INCLUDEDIR}/sparselizard>)
target_compile_features(sparselizard PUBLIC cxx_std_11)

# What an application inherits merely by including sparselizard.h. Stated on the
# target so that a CMake consumer, the generated property sheet and the NuGet
# package all take it from one place instead of restating it three times.
#
# /Zc:preprocessor  the PetscDefined() macros need a conforming preprocessor;
#                   MSVC's traditional one mis-expands them, ~120 errors.
# _CRT_SECURE_NO_WARNINGS  petscstring.h calls strncpy/strncat, which /sdl
#                   promotes from warning C4996 to an error.
target_compile_options(sparselizard INTERFACE
    $<$<CXX_COMPILER_ID:MSVC>:/Zc:preprocessor>)
target_compile_definitions(sparselizard INTERFACE
    $<$<CXX_COMPILER_ID:MSVC>:_CRT_SECURE_NO_WARNINGS>)

# --- Required dependencies ---------------------------------------------------
find_package(PETSc REQUIRED)
find_package(SLEPc REQUIRED)
find_package(CBLAS REQUIRED)

target_link_libraries(sparselizard PUBLIC SLEPc::SLEPc PETSc::PETSc CBLAS::CBLAS)
target_compile_definitions(sparselizard PUBLIC HAVE_PETSC HAVE_SLEPC HAVE_BLAS)

# --- Optional dependencies ---------------------------------------------------
if(SPARSELIZARD_ENABLE_MPI)
    find_package(MPI REQUIRED COMPONENTS CXX)
    target_link_libraries(sparselizard PUBLIC MPI::MPI_CXX)
    target_compile_definitions(sparselizard PUBLIC HAVE_MPI)
else()
    # slmpi.cpp includes <mpi.h> unconditionally. A PETSc configured with
    # --with-mpi=0 ships the MPIUNI stub for exactly this case; without it the
    # header has to come from somewhere else.
    find_path(MPIUNI_INCLUDE_DIR
        NAMES mpi.h
        HINTS "${PETSC_DIR}/include/petsc/mpiuni"
        NO_DEFAULT_PATH)
    if(MPIUNI_INCLUDE_DIR)
        target_include_directories(sparselizard PUBLIC ${MPIUNI_INCLUDE_DIR})
        message(STATUS "MPI disabled, using the PETSc MPIUNI stub at ${MPIUNI_INCLUDE_DIR}")
    else()
        message(WARNING
            "MPI is disabled and no MPIUNI stub was found under PETSC_DIR. "
            "src/slmpi.cpp includes <mpi.h> and will not compile. Either enable "
            "SPARSELIZARD_ENABLE_MPI or point PETSC_DIR at a PETSc built with --with-mpi=0.")
    endif()
endif()

if(SPARSELIZARD_ENABLE_GMSH)
    find_package(GMSH REQUIRED)
    target_link_libraries(sparselizard PUBLIC GMSH::GMSH)
    target_compile_definitions(sparselizard PUBLIC HAVE_GMSH)
endif()

if(SPARSELIZARD_ENABLE_OPENMP)
    find_package(OpenMP REQUIRED COMPONENTS CXX)
    target_link_libraries(sparselizard PUBLIC OpenMP::OpenMP_CXX)
endif()

target_include_directories(sparselizard PUBLIC $<BUILD_INTERFACE:${CMAKE_CURRENT_BINARY_DIR}>)

# --- Runtime search path ------------------------------------------------------
# Third-party shared libraries stay where they were installed; only their
# directories are recorded, so nothing has to be copied or kept in sync. The
# list feeds the CTest environment and the generated helper script below, and is
# a cache variable so that an extra directory can be appended by hand.
# sparselizard's own shared library first. The examples get away without it
# because they are built into the same directory and the loader searches the one
# holding the executable, but a binary built anywhere else does not.
set(_rt_dirs "${CMAKE_RUNTIME_OUTPUT_DIRECTORY}" "${CMAKE_LIBRARY_OUTPUT_DIRECTORY}")
list(APPEND _rt_dirs ${SLEPc_RUNTIME_DIRS})
get_filename_component(_cxx_bin "${CMAKE_CXX_COMPILER}" DIRECTORY)
if(IS_DIRECTORY "${_cxx_bin}")
    list(APPEND _rt_dirs "${_cxx_bin}")   # libmmd, svml_dispmd, libifcoremd
endif()
foreach(_b IN LISTS BLAS_LIBRARIES)
    if(IS_ABSOLUTE "${_b}")
        get_filename_component(_bd "${_b}" DIRECTORY)
        get_filename_component(_bp "${_bd}" DIRECTORY)
        foreach(_try "${_bd}" "${_bp}/bin")
            if(IS_DIRECTORY "${_try}")
                list(APPEND _rt_dirs "${_try}")
            endif()
        endforeach()
    endif()
endforeach()
# Only the additions are a cache entry. The derived part is recomputed at every
# configure: a plain "set(... CACHE ...)" never overwrites an existing entry, so
# caching the derived list would freeze the first result and quietly ignore any
# later correction.
set(SPARSELIZARD_RUNTIME_PATHS_EXTRA "" CACHE STRING
    "Extra directories to add to the loader search path when running the binaries")
list(APPEND _rt_dirs ${SPARSELIZARD_RUNTIME_PATHS_EXTRA})
list(REMOVE_DUPLICATES _rt_dirs)
set(SPARSELIZARD_RUNTIME_PATHS "${_rt_dirs}" PARENT_SCOPE)
set(SPARSELIZARD_RUNTIME_PATHS "${_rt_dirs}")

message(STATUS "Runtime search path:")
foreach(_d IN LISTS SPARSELIZARD_RUNTIME_PATHS)
    message(STATUS "    ${_d}")
endforeach()

# A small helper for running a binary by hand, outside ctest. Sourcing it is the
# only manual step, and it is generated from the same list, so it cannot drift.
if(WIN32)
    set(_env_script "${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/sparselizard-env.cmd")
    set(_body "@echo off\r\nrem Generated by CMake -- prepends the dependency directories to PATH.\r\n")
    foreach(_d IN LISTS SPARSELIZARD_RUNTIME_PATHS)
        file(TO_NATIVE_PATH "${_d}" _nd)
        string(APPEND _body "set \"PATH=${_nd};%PATH%\"\r\n")
    endforeach()
    string(APPEND _body "echo sparselizard: dependency directories added to PATH\r\n")
else()
    set(_env_script "${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/sparselizard-env.sh")
    set(_body "# Generated by CMake -- source this file.\n")
    foreach(_d IN LISTS SPARSELIZARD_RUNTIME_PATHS)
        string(APPEND _body "export LD_LIBRARY_PATH=\"${_d}:\${LD_LIBRARY_PATH}\"\n")
    endforeach()
endif()
file(WRITE "${_env_script}" "${_body}")
message(STATUS "Runtime helper .... ${_env_script}")

# A Visual Studio project cannot consume a CMake package, so the same
# information is emitted a second time as an MSBuild property sheet. Adding it
# through the Property Manager is the whole setup: it carries the include
# directories, the compiler requirements, the link line and the loader search
# path. Generated from the variables just computed, so it cannot drift from the
# CMake target. This is also the file the NuGet package ships as
# build/native/sparselizard.props.
if(WIN32)
    include("${CMAKE_SOURCE_DIR}/cMake/writepropertysheet.cmake")
    sparselizard_write_property_sheet(
        "${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/sparselizard.props"
        INCLUDE_DIRS "${SPARSELIZARD_INCLUDE_STAGE_DIR};${PETSc_INCLUDE_DIR};${PETSc_CONF_INCLUDE_DIR}"
        LIBRARY_DIRS "${CMAKE_ARCHIVE_OUTPUT_DIRECTORY}"
        LIBRARIES    "sparselizard.lib"
        RUNTIME_DIRS "${SPARSELIZARD_RUNTIME_PATHS}")
    message(STATUS "MSBuild sheet ..... ${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/sparselizard.props")
endif()

# --- Installation and CMake package -------------------------------------------
# Exporting the target is what lets an application write
#
#     find_package(sparselizard REQUIRED)
#     target_link_libraries(app PRIVATE sparselizard::sparselizard)
#
# and inherit the include directories, the PUBLIC dependencies and the compiler
# requirements above, instead of restating them by hand.
set(SPARSELIZARD_CMAKE_DIR "${CMAKE_INSTALL_LIBDIR}/cmake/sparselizard")

install(TARGETS sparselizard EXPORT sparselizardTargets
        RUNTIME DESTINATION "${CMAKE_INSTALL_BINDIR}"
        LIBRARY DESTINATION "${CMAKE_INSTALL_LIBDIR}"
        ARCHIVE DESTINATION "${CMAKE_INSTALL_LIBDIR}"
        INCLUDES DESTINATION "${CMAKE_INSTALL_INCLUDEDIR}/sparselizard")
install(DIRECTORY "${SPARSELIZARD_INCLUDE_STAGE_DIR}/"
        DESTINATION "${CMAKE_INSTALL_INCLUDEDIR}/sparselizard"
        FILES_MATCHING PATTERN "*.h")
install(EXPORT sparselizardTargets
        NAMESPACE sparselizard::
        DESTINATION "${SPARSELIZARD_CMAKE_DIR}")

include(CMakePackageConfigHelpers)
configure_package_config_file(
    "${CMAKE_SOURCE_DIR}/cMake/sparselizardConfig.cmake.in"
    "${CMAKE_CURRENT_BINARY_DIR}/sparselizardConfig.cmake"
    INSTALL_DESTINATION "${SPARSELIZARD_CMAKE_DIR}")
write_basic_package_version_file(
    "${CMAKE_CURRENT_BINARY_DIR}/sparselizardConfigVersion.cmake"
    VERSION "${PROJECT_VERSION}"
    COMPATIBILITY SameMinorVersion)
install(FILES
        "${CMAKE_CURRENT_BINARY_DIR}/sparselizardConfig.cmake"
        "${CMAKE_CURRENT_BINARY_DIR}/sparselizardConfigVersion.cmake"
        DESTINATION "${SPARSELIZARD_CMAKE_DIR}")
# find_dependency(PETSc) in the config file resolves through these.
install(FILES
        "${CMAKE_SOURCE_DIR}/cMake/FindPETSc.cmake"
        "${CMAKE_SOURCE_DIR}/cMake/FindSLEPc.cmake"
        "${CMAKE_SOURCE_DIR}/cMake/FindCBLAS.cmake"
        "${CMAKE_SOURCE_DIR}/cMake/FindGMSH.cmake"
        "${CMAKE_SOURCE_DIR}/cMake/functions.cmake"
        DESTINATION "${SPARSELIZARD_CMAKE_DIR}/modules")

# --- Configuration summary ---------------------------------------------------
# Emitted here rather than at the top level: the find_package results live in
# this scope.
message(STATUS "")
message(STATUS "Sparselizard configuration")
message(STATUS "  build type ........ ${CMAKE_BUILD_TYPE}")
message(STATUS "  shared library .... ${BUILD_SHARED_LIBS}")
message(STATUS "  C++ compiler ...... ${CMAKE_CXX_COMPILER_ID} ${CMAKE_CXX_COMPILER_VERSION}")
message(STATUS "  PETSc ............. ${PETSc_VERSION}  ${PETSc_LIBRARY}")
message(STATUS "  SLEPc ............. ${SLEPc_VERSION}  ${SLEPc_LIBRARY}")
message(STATUS "  BLAS .............. ${BLAS_LIBRARIES}")
message(STATUS "  cblas header ...... ${CBLAS_INCLUDE_DIR}/${CBLAS_HEADER_NAME}")
message(STATUS "  OpenMP ............ ${SPARSELIZARD_ENABLE_OPENMP}")
message(STATUS "  MPI ............... ${SPARSELIZARD_ENABLE_MPI}")
message(STATUS "  Gmsh .............. ${SPARSELIZARD_ENABLE_GMSH}")
message(STATUS "")
