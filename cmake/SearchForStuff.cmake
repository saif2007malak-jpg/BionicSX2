#-------------------------------------------------------------------------------
#                       Search all libraries on the system
#-------------------------------------------------------------------------------

if(PCSX2_TARGET_IOS)
    message(STATUS "iOS build: using bundled dependencies, skipping system packages")

    # Threads - iOS has pthreads
    find_package(Threads REQUIRED)

    # ZLIB - iOS SDK has libz
    find_library(ZLIB_LIBRARY z)
    if(ZLIB_LIBRARY)
        set(ZLIB_FOUND TRUE)
        set(ZLIB_LIBRARIES ${ZLIB_LIBRARY})
        set(ZLIB_INCLUDE_DIRS "")
        message(STATUS "iOS: Using iOS SDK zlib")
    endif()
    # ZLIB alias (for libchdr) - create IMPORTED target for iOS SDK zlib
    if(NOT TARGET ZLIB::ZLIB)
        add_library(ZLIB::ZLIB STATIC IMPORTED)
        set_target_properties(ZLIB::ZLIB PROPERTIES
            IMPORTED_LOCATION "${ZLIB_LIBRARY}"
        )
    endif()

    # Note: Bundled library add_subdirectory calls are at the bottom of this file.
    # The variables below are set assuming the bundled builds succeed.

    # PNG - bundled libpng (added to 3rdparty/libpng)
    # libpng CMakeLists.txt creates target 'png' and sets PNG_FOUND, PNG_LIBRARIES, PNG_INCLUDE_DIRS
    # If not found by the time it's used, we set a fallback.
    # Nothing to do here; find_package(PNG) is skipped below.

    # JPEG - bundled libjpeg-turbo
    # Nothing to do here; find_package(JPEG) is skipped below.

    # Zstd - bundled in 3rdparty/zstd
    # Nothing to do here; find_package(Zstd) is skipped below.

    # LZ4 - bundled in 3rdparty/lz4
    # Nothing to do here; find_package(LZ4) is skipped below.

    # WebP - bundled in 3rdparty/libwebp
    # Nothing to do here; find_package(WebP) is skipped below.

    # Freetype - bundled in 3rdparty/freetype
    # Nothing to do here; find_package(Freetype) is skipped below.

    # plutovg - bundled in 3rdparty/plutovg
    # Nothing to do here; find_package(plutovg) is skipped below.

    # plutosvg - bundled in 3rdparty/plutosvg
    # Nothing to do here; find_package(plutosvg) is skipped below.

    # SDL3 - not used on iOS (use GCController + UIKit)
    # Find call skipped below.

    # CURL - not used on iOS (use NSURLSession)
    # Find call skipped below in the UNIX/APPLE block.

    # FFMPEG - use bundled headers only on iOS
    set(FFMPEG_INCLUDE_DIRS "${CMAKE_SOURCE_DIR}/3rdparty/ffmpeg/include")
    message(STATUS "iOS: FFMPEG using bundled headers only")

    # Qt6 and KDDockWidgets - not used on iOS (native UI)
    # Find calls at bottom are skipped below.

else()
    # --- Original non-iOS find_package calls ---

    find_package(Git)

    # Require threads on all OSes.
    find_package(Threads REQUIRED)

    # Dependency libraries.
    # On macOS, Mono.framework contains an ancient version of libpng.  We don't want that.
    # Avoid it by telling cmake to avoid finding frameworks while we search for libpng.
    set(FIND_FRAMEWORK_BACKUP ${CMAKE_FIND_FRAMEWORK})
    set(CMAKE_FIND_FRAMEWORK NEVER)
    find_package(PNG 1.6.40 REQUIRED)
    find_package(JPEG REQUIRED) # No version because flatpak uses libjpeg-turbo.
    find_package(ZLIB REQUIRED) # v1.3, but Mac uses the SDK version.
    find_package(Zstd 1.5.5 REQUIRED)
    find_package(LZ4 REQUIRED)
    find_package(WebP REQUIRED) # v1.3.2, spews an error on Linux because no pkg-config.
    find_package(SDL3 3.2.6 REQUIRED)
    find_package(Freetype 2.12 REQUIRED)
    find_package(plutovg 1.1.0 REQUIRED)
    find_package(plutosvg 0.0.7 REQUIRED)

    if(USE_VULKAN)
        find_package(Shaderc REQUIRED)
    endif()

    # Platform-specific dependencies.
    if (WIN32)
        add_subdirectory(3rdparty/D3D12MemAlloc EXCLUDE_FROM_ALL)
        add_subdirectory(3rdparty/winpixeventruntime EXCLUDE_FROM_ALL)
        add_subdirectory(3rdparty/winwil EXCLUDE_FROM_ALL)
        set(FFMPEG_INCLUDE_DIRS "${CMAKE_SOURCE_DIR}/3rdparty/ffmpeg/include")
        find_package(Vtune)
    else()
        find_package(CURL REQUIRED)
        find_package(PCAP REQUIRED)
        find_package(Vtune)

        # Use bundled ffmpeg v4.x.x headers if we can't locate it in the system.
        # We'll try to load it dynamically at runtime.
        find_package(FFMPEG COMPONENTS avcodec avformat avutil swresample swscale)
        if(NOT FFMPEG_FOUND)
            message(WARNING "FFmpeg not found, using bundled headers.")
            set(FFMPEG_INCLUDE_DIRS "${CMAKE_SOURCE_DIR}/3rdparty/ffmpeg/include")
        endif()

        ## Use CheckLib package to find module
        include(CheckLib)

        if(UNIX AND NOT APPLE)
            if(LINUX)
                check_lib(LIBUDEV libudev libudev.h)
            endif()

            if(X11_API)
                find_package(X11 REQUIRED)
                if (NOT X11_Xrandr_FOUND)
                    message(FATAL_ERROR "XRandR extension is required")
                endif()
            endif()

            if(WAYLAND_API)
                find_package(ECM REQUIRED NO_MODULE)
                list(APPEND CMAKE_MODULE_PATH "${ECM_MODULE_PATH}")
                find_package(Wayland REQUIRED Egl)
            endif()

            if(USE_BACKTRACE)
                find_package(Libbacktrace REQUIRED)
            endif()

            find_package(PkgConfig REQUIRED)
            pkg_check_modules(DBUS REQUIRED dbus-1)
        endif()
    endif()

    set(CMAKE_FIND_FRAMEWORK ${FIND_FRAMEWORK_BACKUP})

    # Find the Qt components that we need.
    find_package(Qt6 6.7.3 COMPONENTS CoreTools Core GuiTools Gui WidgetsTools Widgets LinguistTools REQUIRED)

    if(WIN32)
        add_subdirectory(3rdparty/rainterface EXCLUDE_FROM_ALL)
    endif()

    # The docking system for the debugger.
    find_package(KDDockWidgets-qt6 2.0.0 REQUIRED)
    # Add an extra include path to work around a broken include directive.
    # TODO: Remove this the next time we update KDDockWidgets.
    get_target_property(KDDOCKWIDGETS_INCLUDE_DIRECTORY KDAB::kddockwidgets INTERFACE_INCLUDE_DIRECTORIES)
    target_include_directories(KDAB::kddockwidgets INTERFACE
        ${KDDOCKWIDGETS_INCLUDE_DIRECTORY}/kddockwidgets
    )
endif()

# --- Bundled 3rdparty libraries (used by both iOS and non-iOS) ---

add_subdirectory(3rdparty/fast_float EXCLUDE_FROM_ALL)
add_subdirectory(3rdparty/rapidyaml EXCLUDE_FROM_ALL)
add_subdirectory(3rdparty/lzma EXCLUDE_FROM_ALL)
add_subdirectory(3rdparty/libchdr EXCLUDE_FROM_ALL)
disable_compiler_warnings_for_target(libchdr)
add_subdirectory(3rdparty/soundtouch EXCLUDE_FROM_ALL)
add_subdirectory(3rdparty/simpleini EXCLUDE_FROM_ALL)
add_subdirectory(3rdparty/imgui EXCLUDE_FROM_ALL)
add_subdirectory(3rdparty/cpuinfo EXCLUDE_FROM_ALL)
disable_compiler_warnings_for_target(cpuinfo)
add_subdirectory(3rdparty/libzip EXCLUDE_FROM_ALL)
add_subdirectory(3rdparty/rcheevos EXCLUDE_FROM_ALL)
add_subdirectory(3rdparty/rapidjson EXCLUDE_FROM_ALL)
add_subdirectory(3rdparty/discord-rpc EXCLUDE_FROM_ALL)
add_subdirectory(3rdparty/freesurround EXCLUDE_FROM_ALL)

if(USE_OPENGL)
    add_subdirectory(3rdparty/glad EXCLUDE_FROM_ALL)
endif()

if(USE_VULKAN)
    add_subdirectory(3rdparty/vulkan EXCLUDE_FROM_ALL)
endif()

add_subdirectory(3rdparty/cubeb EXCLUDE_FROM_ALL)
disable_compiler_warnings_for_target(cubeb)
disable_compiler_warnings_for_target(speex)

# --- iOS bundled libraries (only when PCSX2_TARGET_IOS=ON) ---
if(PCSX2_TARGET_IOS)
    # libpng (also builds zlib if needed, but we use SDK zlib)
    if(EXISTS "${CMAKE_SOURCE_DIR}/3rdparty/libpng/CMakeLists.txt")
        add_subdirectory(3rdparty/libpng EXCLUDE_FROM_ALL)
        if(TARGET png_static)
            set(PNG_FOUND TRUE)
            set(PNG_LIBRARY png_static)
            set(PNG_LIBRARIES png_static)
            set(PNG_INCLUDE_DIRS "${CMAKE_SOURCE_DIR}/3rdparty/libpng" "${CMAKE_BINARY_DIR}/3rdparty/libpng")
            message(STATUS "iOS: Using bundled libpng (static)")
        endif()
    endif()

    # zstd
    if(EXISTS "${CMAKE_SOURCE_DIR}/3rdparty/zstd/CMakeLists.txt")
        add_subdirectory(3rdparty/zstd/build/cmake EXCLUDE_FROM_ALL)
        if(TARGET zstd)
            set(Zstd_FOUND TRUE)
            set(Zstd_LIBRARIES zstd)
            set(Zstd_INCLUDE_DIRS "${CMAKE_SOURCE_DIR}/3rdparty/zstd/lib/zstd.h")
            message(STATUS "iOS: Using bundled zstd")
        endif()
    endif()
    # Zstd alias (for libzip)
    if(TARGET zstd AND NOT TARGET Zstd::Zstd)
        add_library(Zstd::Zstd ALIAS zstd)
    endif()

    # lz4
    if(EXISTS "${CMAKE_SOURCE_DIR}/3rdparty/lz4/CMakeLists.txt")
        add_subdirectory(3rdparty/lz4 EXCLUDE_FROM_ALL)
        if(TARGET lz4)
            set(LZ4_FOUND TRUE)
            set(LZ4_LIBRARIES lz4)
            set(LZ4_INCLUDE_DIRS "${CMAKE_SOURCE_DIR}/3rdparty/lz4/lib")
            message(STATUS "iOS: Using bundled lz4")
        endif()
    endif()

    # libwebp — set flags as CACHE FORCE before add_subdirectory
    # (normal variables from toolchain don't override option() in libwebp's CMakeLists.txt)
    set(WEBP_BUILD_ANIM_UTILS OFF CACHE BOOL "" FORCE)
    set(WEBP_BUILD_CWEBP OFF CACHE BOOL "" FORCE)
    set(WEBP_BUILD_DWEBP OFF CACHE BOOL "" FORCE)
    set(WEBP_BUILD_IMG2WEBP OFF CACHE BOOL "" FORCE)
    set(WEBP_BUILD_WEBPINFO OFF CACHE BOOL "" FORCE)
    set(WEBP_BUILD_WEBPMUX OFF CACHE BOOL "" FORCE)
    set(WEBP_BUILD_EXTRAS OFF CACHE BOOL "" FORCE)
    set(WEBP_HAVE_OPENGL FALSE CACHE BOOL "" FORCE)
    set(WEBP_HAVE_VULKAN FALSE CACHE BOOL "" FORCE)

    if(EXISTS "${CMAKE_SOURCE_DIR}/3rdparty/libwebp/CMakeLists.txt")
        add_subdirectory(3rdparty/libwebp EXCLUDE_FROM_ALL)
        if(TARGET webp)
            set(WebP_FOUND TRUE)
            set(WebP_LIBRARIES webp)
            set(WebP_INCLUDE_DIRS "${CMAKE_SOURCE_DIR}/3rdparty/libwebp/src")
            message(STATUS "iOS: Using bundled libwebp")
        endif()
    endif()

    # freetype — set policy version before add_subdirectory to avoid CMake warnings/errors
    set(CMAKE_POLICY_VERSION_MINIMUM 3.5 CACHE STRING "" FORCE)

    if(EXISTS "${CMAKE_SOURCE_DIR}/3rdparty/freetype/CMakeLists.txt")
        add_subdirectory(3rdparty/freetype EXCLUDE_FROM_ALL)
        if(TARGET freetype)
            set(Freetype_FOUND TRUE)
            set(Freetype_LIBRARIES freetype)
            set(Freetype_INCLUDE_DIRS "${CMAKE_SOURCE_DIR}/3rdparty/freetype/include")
            message(STATUS "iOS: Using bundled freetype")
        endif()
    endif()
    # Freetype alias (for imgui)
    if(TARGET freetype AND NOT TARGET Freetype::Freetype)
        add_library(Freetype::Freetype ALIAS freetype)
    endif()

    # libjpeg-turbo - REMOVED: does not support add_subdirectory()
    # Per libjpeg-turbo/CMakeLists.txt:59, must use ExternalProject_Add()
    # Option B (RECOMMENDED): Use Apple's ImageIO framework for JPEG on iOS
    # No external library needed - iOS has native JPEG support via ImageIO
    # If JPEG support is needed later, implement an ImageIO-based loader in ios/platform/
    message(STATUS "iOS: JPEG support disabled (use ImageIO framework if needed)")

    # plutosvg (includes plutovg as a dependency - do NOT add plutovg separately)
    if(EXISTS "${CMAKE_SOURCE_DIR}/3rdparty/plutosvg/CMakeLists.txt")
        add_subdirectory(3rdparty/plutosvg EXCLUDE_FROM_ALL)
        if(TARGET plutosvg AND TARGET plutovg)
            set(plutovg_FOUND TRUE)
            set(plutovg_LIBRARIES plutovg)
            set(plutovg_INCLUDE_DIRS "${CMAKE_SOURCE_DIR}/3rdparty/plutosvg/plutovg/include")
            set(plutosvg_FOUND TRUE)
            set(plutosvg_LIBRARIES plutosvg)
            set(plutosvg_INCLUDE_DIRS "${CMAKE_SOURCE_DIR}/3rdparty/plutosvg/include")
            message(STATUS "iOS: Using bundled plutosvg (with plutovg)")
        endif()
    endif()
endif()

# --- Non-iOS bundled libraries (keep originals) ---
if(NOT PCSX2_TARGET_IOS)
    # Demangler for the debugger.
    add_subdirectory(3rdparty/demangler EXCLUDE_FROM_ALL)

    # Symbol table parser.
    add_subdirectory(3rdparty/ccc EXCLUDE_FROM_ALL)

    # Architecture-specific.
    if(_M_X86)
        add_subdirectory(3rdparty/zydis EXCLUDE_FROM_ALL)
    elseif(_M_ARM64)
        add_subdirectory(3rdparty/vixl EXCLUDE_FROM_ALL)
    endif()

    # Prevent fmt from being built with exceptions, or being thrown at call sites.
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -DFMT_USE_EXCEPTIONS=0 -DFMT_USE_RTTI=0")
    add_subdirectory(3rdparty/fmt EXCLUDE_FROM_ALL)

    # Deliberately at the end. We don't want to set the flag on third-party projects.
    if(MSVC)
        # Don't warn about "deprecated" POSIX functions.
        add_definitions("-D_CRT_NONSTDC_NO_WARNINGS" "-D_CRT_SECURE_NO_WARNINGS" "-DCRT_SECURE_NO_DEPRECATE")
    endif()
endif()

# --- iOS architecture-specific ---
if(PCSX2_TARGET_IOS AND _M_ARM64)
    add_subdirectory(3rdparty/vixl EXCLUDE_FROM_ALL)
endif()
