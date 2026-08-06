# FindSLEPc
# ---------
# Locate an existing SLEPc installation. Same contract as FindPETSc: nothing is
# downloaded, discovery goes through pkg-config first, then SLEPC_DIR.
#
# SLEPc always sits on top of PETSc, so PETSc::PETSc is pulled in as a
# dependency of the imported target.
#
# Result:
#   SLEPc_FOUND
#   SLEPc::SLEPc
#   SLEPc_VERSION

include(FindPackageHandleStandardArgs)
include("${CMAKE_CURRENT_LIST_DIR}/functions.cmake")

set(SLEPC_DIR "$ENV{SLEPC_DIR}" CACHE PATH "Root of an existing SLEPc installation")

find_package(PETSc QUIET)

find_package(PkgConfig QUIET)
if(PkgConfig_FOUND)
    if(SLEPC_DIR)
        if(PETSC_ARCH)
            set(ENV{PKG_CONFIG_PATH} "${SLEPC_DIR}/${PETSC_ARCH}/lib/pkgconfig:$ENV{PKG_CONFIG_PATH}")
        endif()
        set(ENV{PKG_CONFIG_PATH} "${SLEPC_DIR}/lib/pkgconfig:$ENV{PKG_CONFIG_PATH}")
    endif()

    # SLEPc is built against one PETSc, so where PETSc ships several variants
    # SLEPc ships the matching ones under the same names. FindPETSc has already
    # run and settled PETSC_VARIANT; follow it rather than choose again, since a
    # SLEPc from one variant over a PETSc from another links but does not work.
    set(_slepc_modules SLEPc slepc)
    if(PETSC_VARIANT)
        set(_slepc_modules "slepc-${PETSC_VARIANT}")
    endif()

    foreach(_m IN LISTS _slepc_modules)
        pkg_check_modules(PC_SLEPC QUIET "${_m}")
        if(PC_SLEPC_FOUND)
            break()
        endif()
    endforeach()
endif()

find_path(SLEPc_INCLUDE_DIR
    NAMES slepc.h
    HINTS ${PC_SLEPC_INCLUDE_DIRS} "${SLEPC_DIR}/include")

find_path(SLEPc_CONF_INCLUDE_DIR
    NAMES slepcconf.h
    HINTS ${PC_SLEPC_INCLUDE_DIRS} "${SLEPC_DIR}/${PETSC_ARCH}/include" "${SLEPC_DIR}/include")

find_library(SLEPc_LIBRARY
    NAMES slepc libslepc
    HINTS ${PC_SLEPC_LIBRARY_DIRS} "${SLEPC_DIR}/${PETSC_ARCH}/lib" "${SLEPC_DIR}/lib")

if(PC_SLEPC_VERSION)
    set(SLEPc_VERSION "${PC_SLEPC_VERSION}")
elseif(SLEPc_INCLUDE_DIR AND EXISTS "${SLEPc_INCLUDE_DIR}/slepcversion.h")
    file(STRINGS "${SLEPc_INCLUDE_DIR}/slepcversion.h" _v REGEX "#define SLEPC_VERSION_(MAJOR|MINOR|SUBMINOR) ")
    string(REGEX REPLACE ".*MAJOR[ \t]+([0-9]+).*" "\\1" _major "${_v}")
    string(REGEX REPLACE ".*MINOR[ \t]+([0-9]+).*" "\\1" _minor "${_v}")
    string(REGEX REPLACE ".*SUBMINOR[ \t]+([0-9]+).*" "\\1" _patch "${_v}")
    set(SLEPc_VERSION "${_major}.${_minor}.${_patch}")
endif()

find_package_handle_standard_args(SLEPc
    REQUIRED_VARS SLEPc_LIBRARY SLEPc_INCLUDE_DIR SLEPc_CONF_INCLUDE_DIR PETSc_FOUND
    VERSION_VAR SLEPc_VERSION)

if(SLEPc_FOUND AND NOT TARGET SLEPc::SLEPc)
    get_filename_component(_slepc_libdir "${SLEPc_LIBRARY}" DIRECTORY)
    get_filename_component(_petsc_libdir "${PETSc_LIBRARY}" DIRECTORY)
    _sl_existing_dirs(_slepc_libdirs
        "${PC_SLEPC_LIBRARY_DIRS};${PC_PETSC_LIBRARY_DIRS};${_slepc_libdir};${_petsc_libdir}")
    if(PC_SLEPC_LIBRARIES)
        _sl_resolve_libs(_slepc_libs "${PC_SLEPC_LIBRARIES}" "${_slepc_libdirs}")
    else()
        set(_slepc_libs "${SLEPc_LIBRARY}")
    endif()
    list(APPEND _slepc_libs PETSc::PETSc)

    _sl_existing_dirs(_slepc_incs
        "${SLEPc_INCLUDE_DIR};${SLEPc_CONF_INCLUDE_DIR};${PC_SLEPC_INCLUDE_DIRS}")

    add_library(SLEPc::SLEPc INTERFACE IMPORTED)
    set_target_properties(SLEPc::SLEPc PROPERTIES
        INTERFACE_INCLUDE_DIRECTORIES "${_slepc_incs}"
        INTERFACE_LINK_LIBRARIES "${_slepc_libs}")

    # Directories the loader will need at run time. The full private link line
    # names every dependency PETSc was built against -- MUMPS, BLAS and the rest
    # -- which is exactly the set of shared libraries the executables will look
    # for. Nothing is copied; only the paths are recorded.
    # pkg_check_modules already exposes the static link line; prefer it over
    # spawning pkg-config again, whose environment would have to be reproduced.
    set(_rt_line "")
    foreach(_v PC_SLEPC_STATIC_LDFLAGS PC_SLEPC_STATIC_LDFLAGS_OTHER
               PC_PETSC_STATIC_LDFLAGS PC_PETSC_STATIC_LDFLAGS_OTHER)
        if(${_v})
            string(REPLACE ";" " " _flat "${${_v}}")
            string(APPEND _rt_line " ${_flat}")
        endif()
    endforeach()
    string(APPEND _rt_line " ${SLEPc_LIBRARY} ${PETSc_LIBRARY}")
    _sl_runtime_dirs(SLEPc_RUNTIME_DIRS "${_rt_line}")
    set(SLEPc_RUNTIME_DIRS "${SLEPc_RUNTIME_DIRS}" CACHE INTERNAL
        "Directories holding the shared libraries needed by SLEPc at run time")
endif()

mark_as_advanced(SLEPc_INCLUDE_DIR SLEPc_CONF_INCLUDE_DIR SLEPc_LIBRARY)
