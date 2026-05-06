# iOS Toolchain for BionicSX2
# This toolchain configures CMake for cross-compiling to iOS on ARM64 (Apple Silicon)
# Usage: cmake -DCMAKE_TOOLCHAIN_FILE=cmake/ios.toolchain.cmake -DPCSX2_TARGET_IOS=ON

set(CMAKE_SYSTEM_NAME iOS)
set(CMAKE_SYSTEM_VERSION 16.0)  # iOS 16.0+ required for pthread_jit_write_protect_np()

# Target ARM64 (Apple Silicon)
set(CMAKE_OSX_ARCHITECTURES arm64)

# Set iOS deployment target
set(CMAKE_OSX_DEPLOYMENT_TARGET 14.2 CACHE STRING "Minimum iOS version" FORCE)
# iOS 14.2+ required for pthread_jit_write_protect_np()

# iOS is always cross-compiling
set(CMAKE_CROSSCOMPILING TRUE)

# Set sysroot to iOS SDK
if(NOT CMAKE_OSX_SYSROOT)
    execute_process(
        COMMAND xcrun --sdk iphoneos --show-sdk-path
        OUTPUT_VARIABLE _ios_sdk_path
        OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_QUIET
    )
    if(_ios_sdk_path)
        set(CMAKE_OSX_SYSROOT ${_ios_sdk_path} CACHE PATH "iOS SDK path" FORCE)
    endif()
endif()

# Compiler flags for iOS
set(CMAKE_C_FLAGS_INIT "-target arm64-apple-ios${CMAKE_OSX_DEPLOYMENT_TARGET}")
set(CMAKE_CXX_FLAGS_INIT "-target arm64-apple-ios${CMAKE_OSX_DEPLOYMENT_TARGET}")

# Don't allow searching for programs in the sysroot
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)

# Set the root path to the iOS sysroot
set(CMAKE_FIND_ROOT_PATH ${CMAKE_OSX_SYSROOT})

# Define iOS as a valid Apple platform (not macOS)
set(IOS TRUE)
set(APPLE TRUE)  # iOS is still Apple platform
set(MACOS FALSE)  # But not macOS

# Define IOS as a C++ preprocessor macro so #ifdef IOS works in code
add_compile_definitions(IOS=1)

message(STATUS "iOS toolchain: Targeting iOS ${CMAKE_OSX_DEPLOYMENT_TARGET}+ on ARM64")
message(STATUS "iOS SDK: ${CMAKE_OSX_SYSROOT}")
