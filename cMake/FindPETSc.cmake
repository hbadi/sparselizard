# FindPETSc
# ---------
# Locate an existing PETSc installation. Nothing is downloaded or built here:
# either the library comes from a package manager, or it was built beforehand.
#
# Discovery order:
#   1. pkg-config (PETSc ships PETSc.pc, and so do the distribution packages)
#   2. PETSC_DIR / PETSC_ARCH, the conventional PETSc variables, taken from the
#      cache or the environment
#
# Result:
#   PETSc_FOUND
#   PETSc::PETSc      imported target carrying includes and link interface
#   PETSc_VERSION
#   PETSC_VARIANT     the variant that was selected, empty for a plain install

include(FindPackageHandleStandardArgs)
include("${CMAKE_CURRENT_LIST_DIR}/functions.cmake")

set(PETSC_DIR "$ENV{PETSC_DIR}" CACHE PATH "Root of an existing PETSc installation")
set(PETSC_ARCH "$ENV{PETSC_ARCH}" CACHE STRING "PETSc architecture (empty for a prefix install)")

# Some distributions ship one PETSc per scalar type and parallel model rather
# than one library, each with its own headers, its own import library and its
# own .pc. MSYS2 names them <scalar><parallel>o, where the scalar is s, d, c or
# z for real single, real double, complex single or complex double, and the
# parallel model is m for MPI, s for sequential and t for OpenMP. sparselizard
# needs a real double one; among those, only the sequential and OpenMP variants
# exist on every platform, since the MPI ones are absent on aarch64.
set(PETSC_VARIANT "$ENV{PETSC_VARIANT}" CACHE STRING
    "PETSc variant to use when the installation ships several, e.g. dto")
set(_petsc_preferred_variants dto dso dmo)

# --- 1. pkg-config -----------------------------------------------------------
find_package(PkgConfig QUIET)
if(PkgConfig_FOUND)
    if(PETSC_DIR)
        if(PETSC_ARCH)
            list(APPEND CMAKE_PREFIX_PATH "${PETSC_DIR}/${PETSC_ARCH}")
            set(ENV{PKG_CONFIG_PATH} "${PETSC_DIR}/${PETSC_ARCH}/lib/pkgconfig:$ENV{PKG_CONFIG_PATH}")
        endif()
        set(ENV{PKG_CONFIG_PATH} "${PETSC_DIR}/lib/pkgconfig:$ENV{PKG_CONFIG_PATH}")
    endif()

    # An explicit variant is taken as given and nothing else is tried, so that a
    # typo fails here rather than silently linking a different scalar type.
    if(PETSC_VARIANT)
        set(_petsc_modules "petsc-${PETSC_VARIANT}")
    else()
        set(_petsc_modules PETSc petsc)
        foreach(_v IN LISTS _petsc_preferred_variants)
            list(APPEND _petsc_modules "petsc-${_v}")
        endforeach()
    endif()

    foreach(_m IN LISTS _petsc_modules)
        pkg_check_modules(PC_PETSC QUIET "${_m}")
        if(PC_PETSC_FOUND)
            if(NOT PETSC_VARIANT AND _m MATCHES "^petsc-(.+)$")
                set(PETSC_VARIANT "${CMAKE_MATCH_1}" CACHE STRING
                    "PETSc variant to use when the installation ships several, e.g. dto" FORCE)
                message(STATUS "PETSc ships several variants, selected '${PETSC_VARIANT}'")
            endif()
            break()
        endif()
    endforeach()
endif()

# --- 2. headers --------------------------------------------------------------
find_path(PETSc_INCLUDE_DIR
    NAMES petsc.h
    HINTS ${PC_PETSC_INCLUDE_DIRS} "${PETSC_DIR}/include")

# petscconf.h lives in the arch tree for an in-place build, next to petsc.h for
# a prefix install.
find_path(PETSc_CONF_INCLUDE_DIR
    NAMES petscconf.h
    HINTS ${PC_PETSC_INCLUDE_DIRS} "${PETSC_DIR}/${PETSC_ARCH}/include" "${PETSC_DIR}/include")

# --- 3. library --------------------------------------------------------------
find_library(PETSc_LIBRARY
    NAMES petsc libpetsc
    HINTS ${PC_PETSC_LIBRARY_DIRS} "${PETSC_DIR}/${PETSC_ARCH}/lib" "${PETSC_DIR}/lib")

# --- 4. version --------------------------------------------------------------
if(PC_PETSC_VERSION)
    set(PETSc_VERSION "${PC_PETSC_VERSION}")
elseif(PETSc_INCLUDE_DIR AND EXISTS "${PETSc_INCLUDE_DIR}/petscversion.h")
    file(STRINGS "${PETSc_INCLUDE_DIR}/petscversion.h" _v REGEX "#define PETSC_VERSION_(MAJOR|MINOR|SUBMINOR) ")
    string(REGEX REPLACE ".*MAJOR[ \t]+([0-9]+).*" "\\1" _major "${_v}")
    string(REGEX REPLACE ".*MINOR[ \t]+([0-9]+).*" "\\1" _minor "${_v}")
    string(REGEX REPLACE ".*SUBMINOR[ \t]+([0-9]+).*" "\\1" _patch "${_v}")
    set(PETSc_VERSION "${_major}.${_minor}.${_patch}")
endif()

find_package_handle_standard_args(PETSc
    REQUIRED_VARS PETSc_LIBRARY PETSc_INCLUDE_DIR PETSc_CONF_INCLUDE_DIR
    VERSION_VAR PETSc_VERSION)

if(PETSc_FOUND AND NOT TARGET PETSc::PETSc)
    # Prefer the whole pkg-config link interface when we have one: it already
    # carries whatever PETSc was configured against. The directories found by
    # find_library are appended as hints, since the ones coming from the .pc file
    # may be unusable (see _sl_existing_dirs).
    get_filename_component(_petsc_libdir "${PETSc_LIBRARY}" DIRECTORY)
    _sl_existing_dirs(_petsc_libdirs "${PC_PETSC_LIBRARY_DIRS};${_petsc_libdir}")
    if(PC_PETSC_LIBRARIES)
        _sl_resolve_libs(_petsc_libs "${PC_PETSC_LIBRARIES}" "${_petsc_libdirs}")
    else()
        set(_petsc_libs "${PETSc_LIBRARY}")
    endif()

    _sl_existing_dirs(_petsc_incs
        "${PETSc_INCLUDE_DIR};${PETSc_CONF_INCLUDE_DIR};${PC_PETSC_INCLUDE_DIRS}")

    # A PETSc configured with --with-cxx=0 never probed a C++ compiler, so the
    # C++ half of its petscconf.h is missing. petscmacros.h still refers to it
    # from every C++ translation unit, and the compiler stops on undeclared
    # identifiers. Exactly two macros are concerned in the PETSc headers, so
    # supply the values configure would have written rather than requiring a
    # rebuild. Each is filled in only when genuinely absent, so a PETSc built
    # with C++ support keeps its own.
    set(_petsc_defs)
    if(EXISTS "${PETSc_CONF_INCLUDE_DIR}/petscconf.h")
        set(_petsc_cxx_fallbacks
            "PETSC_FUNCTION_NAME_CXX=__func__"    # standard since C++11
            "PETSC_CXX_RESTRICT=__restrict")      # accepted by gcc, clang and msvc
        foreach(_def IN LISTS _petsc_cxx_fallbacks)
            string(REGEX REPLACE "=.*$" "" _name "${_def}")
            file(STRINGS "${PETSc_CONF_INCLUDE_DIR}/petscconf.h" _hit
                 REGEX "^#define[ \t]+${_name}[ \t]")
            if(NOT _hit)
                list(APPEND _petsc_defs "${_def}")
            endif()
        endforeach()
        if(_petsc_defs)
            message(STATUS "PETSc was built without C++ support, supplying: ${_petsc_defs}")
        endif()
    endif()

    add_library(PETSc::PETSc INTERFACE IMPORTED)
    set_target_properties(PETSc::PETSc PROPERTIES
        INTERFACE_INCLUDE_DIRECTORIES "${_petsc_incs}"
        INTERFACE_LINK_LIBRARIES "${_petsc_libs}"
        INTERFACE_COMPILE_DEFINITIONS "${_petsc_defs}")
endif()

mark_as_advanced(PETSc_INCLUDE_DIR PETSc_CONF_INCLUDE_DIR PETSc_LIBRARY)
