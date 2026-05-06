# iOS Platform Layer CMakeLists.txt
# Included when PCSX2_TARGET_IOS=ON
# Provides real iOS implementations for HostSys, CocoaTools, AudioStream, FileSystem

message(STATUS "Configuring iOS platform layer...")

# iOS platform source files
set(ios_platform_sources
    ${CMAKE_CURRENT_SOURCE_DIR}/HostSys_iOS.cpp
    ${CMAKE_CURRENT_SOURCE_DIR}/FileSystem_iOS.cpp
)

set(ios_platform_mm_sources
    ${CMAKE_CURRENT_SOURCE_DIR}/CocoaTools.mm
    ${CMAKE_CURRENT_SOURCE_DIR}/AudioStream_iOS.mm
)

# Add Objective-C++ sources (must be .mm for iOS frameworks)
foreach(mm_file IN LISTS ios_platform_mm_sources)
    if(EXISTS ${mm_file})
        set_source_files_properties(${mm_file} PROPERTIES LANGUAGE OBJCXX)
        list(APPEND ios_platform_sources ${mm_file})
    endif()
endforeach()

# Add iOS platform sources to PCSX2 target
if(TARGET PCSX2)
    target_sources(PCSX2 PRIVATE ${ios_platform_sources})
    message(STATUS "Added iOS platform sources: ${ios_platform_sources}")
else()
    # If PCSX2 target doesn't exist yet, create a library
    add_library(ios_platform OBJECT ${ios_platform_sources})
    target_include_directories(ios_platform PRIVATE
        ${CMAKE_SOURCE_DIR}/common
        ${CMAKE_SOURCE_DIR}/common/Darwin
        ${CMAKE_SOURCE_DIR}/Host
    )
    target_link_libraries(ios_platform PRIVATE PCSX2_FLAGS)
    message(STATUS "Created ios_platform library for iOS")
endif()

# Link iOS-specific frameworks
if(APPLE AND IOS)
    find_library(UIKIT_LIBRARY UIKit)
    find_library(METAL_LIBRARY Metal)
    find_library(QUARTZCORE_LIBRARY QuartzCore)
    find_library(AUDIO_TOOLBOX_LIBRARY AudioToolbox)
    find_library(AVFOUNDATION_LIBRARY AVFoundation)

    target_link_libraries(PCSX2_FLAGS INTERFACE
        ${UIKIT_LIBRARY}
        ${METAL_LIBRARY}
        ${QUARTZCORE_LIBRARY}
        ${AUDIO_TOOLBOX_LIBRARY}
        ${AVFOUNDATION_LIBRARY}
    )

    # Add required entitlements for JIT (iOS 14.2+)
    message(STATUS "iOS target: JIT requires com.apple.security.cs.allow-jit entitlement")
endif()
