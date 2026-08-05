# Helper functions shared by the sparselizard build.

# Collect sources from a list of directories and create the library target.
# Honours the standard BUILD_SHARED_LIBS switch instead of forcing SHARED.
function(custom_add_library_from_dir TARGET DIRLIST)
    foreach(d IN LISTS DIRLIST)
        file(GLOB SRC "${d}/*.cpp" "${d}/*.h" "${d}/*.hpp")
        list(APPEND TARGET_SRC ${SRC})
    endforeach()
    add_library(${TARGET} ${TARGET_SRC})
endfunction()

# Collect sources from a list of directories and create an executable target.
function(custom_add_executable_from_dir TARGET DIRLIST)
    foreach(d IN LISTS DIRLIST)
        file(GLOB SRC "${d}/*.cpp" "${d}/*.h" "${d}/*.hpp")
        list(APPEND TARGET_SRC ${SRC})
    endforeach()
    add_executable(${TARGET} ${TARGET_SRC})
endfunction()

function(custom_copy_file TARGET FROMDIRS TODIR GLOBS)
    foreach(d IN LISTS FROMDIRS)
        foreach(g IN LISTS GLOBS)
            file(GLOB SRC "${d}/${g}")
            foreach(f IN LISTS SRC)
                string(REGEX REPLACE "^.*/" "" DEST ${f})
                configure_file(${f} ${TODIR}/${DEST} COPYONLY)
            endforeach()
        endforeach()
    endforeach()
endfunction()

# Copy data files next to a target. The original implementation created symbolic
# links, which need developer mode or elevation on Windows; a copy behaves the
# same everywhere.
function(custom_symlink_file TARGET FROMDIRS TODIR GLOBS)
    foreach(d IN LISTS FROMDIRS)
        foreach(g IN LISTS GLOBS)
            file(GLOB SRC "${d}/${g}")
            foreach(f IN LISTS SRC)
                get_filename_component(filename ${f} NAME)
                if(NOT ${filename} STREQUAL "CMakeLists.txt")
                    configure_file(${f} ${TODIR}/${filename} COPYONLY)
                endif()
            endforeach()
        endforeach()
    endforeach()
endfunction()

# Bring an MSYS/Cygwin style path back to its native form.
#
# A PETSc or SLEPc configured from an MSYS2 shell records POSIX paths in its .pc
# file ("/d/Work/..."), and a MUMPS reached through PETSc's private link line is
# named the same way. A native CMake resolves none of those, and would silently
# drop them. The /<letter>/ prefix maps to <letter>:/ and nothing else changes.
function(_sl_native_path OUT_VAR P)
    set(_p "${P}")
    if(WIN32 AND NOT EXISTS "${_p}" AND _p MATCHES "^/([a-zA-Z])/(.*)$")
        set(_p "${CMAKE_MATCH_1}:/${CMAKE_MATCH_2}")
    endif()
    set(${OUT_VAR} "${_p}" PARENT_SCOPE)
endfunction()

# Keep only the directories that actually exist.
#
# pkg-config reports whatever was baked into the .pc file at configure time. A
# PETSc configured from an MSYS2 shell records POSIX paths ("/d/Work/..."), which
# a native CMake cannot resolve; CMake then rejects the imported target outright.
# Discarding the unusable entries leaves the ones found by find_path/find_library,
# which are native by construction.
function(_sl_existing_dirs OUT_VAR DIRS)
    set(_kept)
    foreach(_d IN LISTS DIRS)
        _sl_native_path(_d "${_d}")
        if(IS_DIRECTORY "${_d}")
            list(APPEND _kept "${_d}")
        endif()
    endforeach()
    if(_kept)
        list(REMOVE_DUPLICATES _kept)
    endif()
    set(${OUT_VAR} "${_kept}" PARENT_SCOPE)
endfunction()

# Derive, from a link line, the directories that must be on the loader path at
# run time.
#
# On Windows the import library and the DLL rarely sit together: oneMKL and the
# MUMPS superbuild put the .lib in lib/ and the .dll in the sibling bin/. Both
# candidates are therefore considered, and only the ones actually holding a
# shared library are kept.
#
#   _sl_runtime_dirs(<out_var> "<link line>")
function(_sl_runtime_dirs OUT_VAR LINE)
    string(REPLACE " " ";" _items "${LINE}")
    set(_cand)
    foreach(_it IN LISTS _items)
        if(_it MATCHES "^-L(.+)$")
            _sl_native_path(_d "${CMAKE_MATCH_1}")
            list(APPEND _cand "${_d}")
        elseif(IS_ABSOLUTE "${_it}" AND _it MATCHES "\\.(lib|a|so|dylib)$")
            _sl_native_path(_it "${_it}")
            get_filename_component(_d "${_it}" DIRECTORY)
            list(APPEND _cand "${_d}")
        endif()
    endforeach()

    set(_dirs)
    foreach(_d IN LISTS _cand)
        get_filename_component(_parent "${_d}" DIRECTORY)
        foreach(_try "${_d}" "${_parent}/bin")
            if(IS_DIRECTORY "${_try}")
                file(GLOB _shared "${_try}/*.dll" "${_try}/*.so*" "${_try}/*.dylib")
                if(_shared)
                    get_filename_component(_abs "${_try}" ABSOLUTE)
                    list(APPEND _dirs "${_abs}")
                endif()
            endif()
        endforeach()
    endforeach()
    if(_dirs)
        list(REMOVE_DUPLICATES _dirs)
    endif()
    set(${OUT_VAR} "${_dirs}" PARENT_SCOPE)
endfunction()

# Turn a pkg-config style link interface into absolute library paths.
#
# pkg-config yields bare names ("-lpetsc"). Passing those straight to the linker
# breaks in two common cases: the MSVC linker has no -l, and icx in its clang-cl
# mode silently *ignores* -l and still returns 0, so a missing library surfaces
# much later as an unresolved symbol. Resolving every name to a full path with
# find_library keeps the behaviour identical on every toolchain.
#
#   _sl_resolve_libs(<out_var> "<names>" "<dirs>")
function(_sl_resolve_libs OUT_VAR NAMES DIRS)
    set(_resolved)
    foreach(_name IN LISTS NAMES)
        if(IS_ABSOLUTE "${_name}" OR _name MATCHES "\\.(lib|a|so|dylib)$")
            list(APPEND _resolved "${_name}")
            continue()
        endif()
        # "lib" prefix is not implicit for MSVC-style toolchains, hence lib${_name}.
        find_library(_sl_lib_${_name}
            NAMES ${_name} lib${_name}
            HINTS ${DIRS}
            NO_DEFAULT_PATH)
        if(_sl_lib_${_name})
            list(APPEND _resolved "${_sl_lib_${_name}}")
        else()
            find_library(_sl_sys_${_name} NAMES ${_name} lib${_name})
            if(_sl_sys_${_name})
                list(APPEND _resolved "${_sl_sys_${_name}}")
            else()
                # Leave it to the linker: system libraries such as Kernel32 have
                # no import library to locate on the search paths we were given.
                list(APPEND _resolved "${_name}")
            endif()
        endif()
    endforeach()
    set(${OUT_VAR} "${_resolved}" PARENT_SCOPE)
endfunction()
