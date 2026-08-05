# sparselizard_stage_nuget
# ------------------------
# Lay out a native NuGet package, so that consuming sparselizard from Visual
# Studio is one package reference and nothing else. NuGet imports
# build/native/<id>.props and .targets into the project automatically, which is
# what carries the include directories, the compiler requirements, the link line
# and the copy of the shared libraries to the output directory.
#
# The package is self-contained: every shared library the application needs at
# run time is inside it and gets copied next to the executable, which is the one
# directory the Windows loader always searches. Nothing has to be installed
# alongside and no PATH entry is needed.
#
# The Microsoft C and C++ runtime is the one exception. MSVCP140.dll and
# VCRUNTIME140.dll come from the Visual C++ redistributable, which is present on
# any machine with Visual Studio and is serviced by Windows Update; copying them
# next to the executable would freeze a version that security updates then never
# reach.
#
# Picking the MKL pieces cannot be done by globbing its bin directory: that also
# holds the SYCL, ScaLAPACK and BLACS variants, none of which is reachable from
# here. The list below is the closure of what actually gets loaded, and the
# indirect half of it is the part that is easy to get wrong -- see the comment
# on SPARSELIZARD_NUGET_MKL_RUNTIME.

function(sparselizard_stage_nuget _stage)
    cmake_parse_arguments(SN "" "VERSION" "RUNTIME_DIRS;PETSC_INCLUDE_DIRS" ${ARGN})

    file(REMOVE_RECURSE "${_stage}")
    file(MAKE_DIRECTORY "${_stage}/build/native/lib/x64")
    file(MAKE_DIRECTORY "${_stage}/build/native/bin/x64")

    # --- headers and import library -------------------------------------------
    file(GLOB _headers "${SPARSELIZARD_INCLUDE_STAGE_DIR}/*.h")
    file(COPY ${_headers} DESTINATION "${_stage}/build/native/include")
    file(COPY "${CMAKE_SOURCE_DIR}/LICENSE" "${CMAKE_SOURCE_DIR}/COPYRIGHT"
         DESTINATION "${_stage}")

    # densemat.h and its neighbours include <petscmat.h> and friends, so the
    # PETSc headers are part of sparselizard's public interface and travel with
    # it. Two directories: the source tree, and the arch tree holding the
    # petscconf.h written by configure. They are numbered rather than named after
    # their origin so that the include order is visible in the property sheet.
    set(_petsc_inc_names "")
    set(_i 0)
    foreach(_d IN LISTS SN_PETSC_INCLUDE_DIRS)
        if(NOT IS_DIRECTORY "${_d}")
            continue()
        endif()
        set(_name "include-petsc${_i}")
        file(COPY "${_d}/" DESTINATION "${_stage}/build/native/${_name}")
        list(APPEND _petsc_inc_names "${_name}")
        math(EXPR _i "${_i} + 1")
    endforeach()

    # --- shared libraries ------------------------------------------------------
    # sparselizard and its non-Intel dependencies, taken from the directories
    # already computed for the helper script so nothing is listed by hand.
    set(_dlls "")
    foreach(_d IN LISTS SN_RUNTIME_DIRS)
        string(FIND "${_d}" "oneAPI" _is_intel)
        if(NOT _is_intel EQUAL -1)
            continue()
        endif()
        file(GLOB _found "${_d}/*.dll")
        list(APPEND _dlls ${_found})
    endforeach()

    # The Intel half, by name. Two of the three groups are loaded indirectly and
    # so appear in no import table:
    #
    #   mkl_intel_thread.3.dll delay-loads mkl_core.3.dll and libiomp5md.dll,
    #   and mkl_core.3.dll then picks a kernel matching the CPU it finds itself
    #   on, through LoadLibrary. Ship the whole dispatch set, otherwise the
    #   package works on the machine that built it and fails elsewhere. Both
    #   failures surface as 0xC06D007E on the first BLAS call, naming no module.
    set(_mkl
        mkl_core.3.dll mkl_intel_thread.3.dll mkl_sequential.3.dll
        mkl_def.3.dll mkl_mc3.3.dll mkl_avx2.3.dll mkl_avx512.3.dll mkl_avx10.3.dll
        mkl_vml_def.3.dll mkl_vml_cmpt.3.dll mkl_vml_mc3.3.dll
        mkl_vml_avx2.3.dll mkl_vml_avx512.3.dll mkl_vml_avx10.3.dll)
    # libifcoremd is the Fortran runtime MUMPS is built against; the other three
    # back the Intel compiler's own intrinsics and OpenMP.
    set(_intel_rt libiomp5md.dll libifcoremd.dll svml_dispmd.dll libmmd.dll)

    foreach(_n IN LISTS _mkl _intel_rt)
        set(_hit "")
        foreach(_d IN LISTS SN_RUNTIME_DIRS)
            if(EXISTS "${_d}/${_n}")
                set(_hit "${_d}/${_n}")
                break()
            endif()
        endforeach()
        if(_hit)
            list(APPEND _dlls "${_hit}")
        else()
            message(WARNING "Not found, package will be incomplete: ${_n}")
        endif()
    endforeach()
    # The same library can sit in two of those directories, for instance a
    # mumps.dll copied next to the build output and the one in its own install
    # tree. Keep the first, so the order of SPARSELIZARD_RUNTIME_PATHS decides.
    set(_packed "")
    foreach(_f IN LISTS _dlls)
        get_filename_component(_n "${_f}" NAME)
        if(_n IN_LIST _packed)
            continue()
        endif()
        list(APPEND _packed "${_n}")
        message(STATUS "  packing ${_n}")
        file(COPY "${_f}" DESTINATION "${_stage}/build/native/bin/x64")
    endforeach()

    # --- import library --------------------------------------------------------
    set(_implib "${CMAKE_ARCHIVE_OUTPUT_DIRECTORY}/sparselizard.lib")
    if(EXISTS "${_implib}")
        file(COPY "${_implib}" DESTINATION "${_stage}/build/native/lib/x64")
    else()
        message(FATAL_ERROR
            "No sparselizard.lib in ${CMAKE_ARCHIVE_OUTPUT_DIRECTORY}. "
            "Build the library before staging the package.")
    endif()

    # --- property sheet --------------------------------------------------------
    # Paths relative to the sheet, so the package works wherever NuGet unpacks it.
    include("${CMAKE_SOURCE_DIR}/cMake/writepropertysheet.cmake")
    sparselizard_write_property_sheet("${_stage}/build/native/sparselizard.props"
        RELATIVE_TO_SHEET
        INCLUDE_DIRS "include;${_petsc_inc_names}"
        LIBRARY_DIRS "lib/x64"
        LIBRARIES    "sparselizard.lib"
        RUNTIME_DIRS "bin/x64")

    # --- targets ---------------------------------------------------------------
    # The shared libraries land next to the executable, which is the one place
    # the Windows loader always searches. That is what removes the PATH problem
    # rather than working around it with a debugger environment.
    file(WRITE "${_stage}/build/native/sparselizard.targets"
"<?xml version=\"1.0\" encoding=\"utf-8\"?>
<!-- sparselizard ${SN_VERSION}. Generated by CMake, do not edit. -->
<Project ToolsVersion=\"4.0\" xmlns=\"http://schemas.microsoft.com/developer/msbuild/2003\">
  <!-- NuGet imports the .props before the toolset settings, where
       ExternalIncludePath is still empty and assigning to it would suppress the
       toolset's own default of the CRT and SDK directories. The sheet skips the
       append there; this file is imported last, so it happens here instead. See
       the comment in sparselizard.props. -->
  <PropertyGroup Condition=\"'\$(SparselizardExternalApplied)' != 'true'\">
    <ExternalIncludePath>\$(ExternalIncludePath);\$(SparselizardIncludeDirs)</ExternalIncludePath>
    <SparselizardExternalApplied>true</SparselizardExternalApplied>
  </PropertyGroup>

  <ItemGroup>
    <SparselizardRuntime Include=\"\$(MSBuildThisFileDirectory)bin\\x64\\*.dll\" />
  </ItemGroup>
  <Target Name=\"SparselizardCopyRuntime\" AfterTargets=\"Build\"
          Inputs=\"@(SparselizardRuntime)\"
          Outputs=\"@(SparselizardRuntime->'\$(OutDir)%(Filename)%(Extension)')\">
    <Copy SourceFiles=\"@(SparselizardRuntime)\"
          DestinationFolder=\"\$(OutDir)\"
          SkipUnchangedFiles=\"true\"
          UseHardlinksIfPossible=\"true\" />
  </Target>
</Project>
")

    # --- nuspec ----------------------------------------------------------------
    # GPL v2 or later. A package makes linking one click, and the obligation
    # travels with it; the licence and the copyright notice ship inside.
    file(WRITE "${_stage}/sparselizard.nuspec"
"<?xml version=\"1.0\" encoding=\"utf-8\"?>
<package xmlns=\"http://schemas.microsoft.com/packaging/2013/05/nuspec.xsd\">
  <metadata>
    <id>sparselizard</id>
    <version>${SN_VERSION}</version>
    <authors>A. Halbach and contributors</authors>
    <owners>A. Halbach and contributors</owners>
    <projectUrl>http://sparselizard.org</projectUrl>
    <license type=\"expression\">GPL-2.0-or-later</license>
    <requireLicenseAcceptance>true</requireLicenseAcceptance>
    <description>General purpose finite element library for multiphysics simulation, x64, MSVC. Self-contained: adding this package sets the include directories, the compiler settings PETSc requires, the link line, and copies every shared library it needs next to the executable, PETSc, SLEPc, MUMPS and oneMKL included. The only prerequisite is the Visual C++ redistributable. Needs the release C runtime including in Debug builds: sparselizard exchanges std::string and std::vector with the application, which the debug CRT lays out differently.</description>
    <copyright>See the COPYRIGHT file</copyright>
    <tags>native finite-element fem multiphysics petsc slepc</tags>
  </metadata>
  <files>
    <file src=\"build\\**\" target=\"build\" />
    <file src=\"LICENSE\" target=\"LICENSE\" />
    <file src=\"COPYRIGHT\" target=\"COPYRIGHT\" />
  </files>
</package>
")
endfunction()
