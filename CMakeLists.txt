# Thanks to S. Matsievskiy for bringing cmake to the project.

cmake_minimum_required(VERSION 3.21 FATAL_ERROR)

# 2022.5.11 is what the library reports at runtime: sl::getversion() returns
# 202205 and sl::getsubversion() returns 11, the "friendly fox" release. The
# version is needed here so that the installed package can be version-checked by
# find_package(sparselizard 2022.5).
project(Sparselizard VERSION 2022.5.11 LANGUAGES CXX)

list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cMake")
include(GNUInstallDirs)
include(cMake/functions.cmake)

# --- Options -----------------------------------------------------------------
#
# Dependencies are never downloaded or built by this project. Install them with
# a package manager, or build them separately and point the cache variables at
# the result:
#
#   PETSC_DIR / PETSC_ARCH   an existing PETSc  (also read from the environment)
#   SLEPC_DIR                an existing SLEPc  (idem)
#   GMSH_ROOT                an existing Gmsh SDK
#   BLA_VENDOR               picks the BLAS, e.g. Intel10_64lp_seq for oneMKL
#
# BUILD_SHARED_LIBS is the stock CMake switch and selects a shared or a static
# libsparselizard.

option(SPARSELIZARD_ENABLE_MPI "Build with MPI support" OFF)
option(SPARSELIZARD_ENABLE_GMSH "Build with the Gmsh API" OFF)
option(SPARSELIZARD_ENABLE_OPENMP "Build with OpenMP" ON)
option(SPARSELIZARD_BUILD_SIMULATIONS "Build the simulation targets" ON)
option(SPARSELIZARD_BUILD_EXAMPLES "Build every example under examples/" OFF)
option(BUILD_SHARED_LIBS "Build shared libraries" ON)
option(SPARSELIZARD_BUILD_NUGET "Add a 'nuget' target packing a native NuGet (Windows)" OFF)

# Name objects foo.obj rather than foo.cpp.obj. The Ninja and Makefile
# generators append the source extension by default, which only matters when two
# sources in one directory share a stem across languages; every source here is
# .cpp. The Visual Studio generators already replace.
set(CMAKE_CXX_OUTPUT_EXTENSION_REPLACE 1)
set(CMAKE_C_OUTPUT_EXTENSION_REPLACE 1)

if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE "Release" CACHE STRING "Choose the type of build" FORCE)
    set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
        Debug Release RelWithDebInfo MinSizeRel)
endif()

# C++ sources going into a shared library must be position independent; on
# Windows, a shared library also needs an export table, and sparselizard carries
# no __declspec annotations.
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
set(CMAKE_WINDOWS_EXPORT_ALL_SYMBOLS ON)

# Every executable, and on Windows the shared library too, lands in a single
# bin/ directory. This is what keeps one copy of sparselizard.dll for all the
# example binaries: the Windows loader searches the directory holding the
# executable image, never the current directory, so an example started from its
# own data directory still finds the library next to its own .exe.
#
# On Unix the shared object is a LIBRARY artefact and goes to lib/; the relative
# RPATH below plays the same role.
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/lib")
set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/lib")
set(SPARSELIZARD_INCLUDE_STAGE_DIR "${CMAKE_BINARY_DIR}/include")

set(CMAKE_BUILD_RPATH_USE_ORIGIN ON)
set(CMAKE_INSTALL_RPATH "$ORIGIN/../${CMAKE_INSTALL_LIBDIR}")

enable_testing()

add_subdirectory(src)

if(SPARSELIZARD_BUILD_SIMULATIONS)
    add_subdirectory(simulations)
endif()

if(SPARSELIZARD_BUILD_EXAMPLES)
    add_subdirectory(examples)
endif()
