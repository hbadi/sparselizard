# FindGMSH
# --------
# Locate an existing Gmsh SDK (the C++ API, not the standalone binary).
# Optional dependency: it only guards the HAVE_GMSH code paths.
#
# Set GMSH_ROOT to point at an SDK unpacked by hand.
#
# Result:
#   GMSH_FOUND
#   GMSH::GMSH

include(FindPackageHandleStandardArgs)

set(GMSH_ROOT "$ENV{GMSH_ROOT}" CACHE PATH "Root of an existing Gmsh SDK")

find_path(GMSH_INCLUDE_DIR
    NAMES gmsh.h
    HINTS "${GMSH_ROOT}/include")

find_library(GMSH_LIBRARY
    NAMES gmsh libgmsh
    HINTS "${GMSH_ROOT}/lib")

find_package_handle_standard_args(GMSH
    REQUIRED_VARS GMSH_LIBRARY GMSH_INCLUDE_DIR)

if(GMSH_FOUND AND NOT TARGET GMSH::GMSH)
    add_library(GMSH::GMSH INTERFACE IMPORTED)
    set_target_properties(GMSH::GMSH PROPERTIES
        INTERFACE_INCLUDE_DIRECTORIES "${GMSH_INCLUDE_DIR}"
        INTERFACE_LINK_LIBRARIES "${GMSH_LIBRARY}")
endif()

mark_as_advanced(GMSH_INCLUDE_DIR GMSH_LIBRARY)
