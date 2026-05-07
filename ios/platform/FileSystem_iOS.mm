// SPDX-FileCopyrightText: 2002-2025 PCSX2 Dev Team
// SPDX-License-Identifier: GPL-3.0+
// iOS filesystem implementation — sandbox-aware paths

#include "common/FileSystem.h"
#include "common/Path.h"
#include "common/Console.h"

#include <cstdlib>
#include <cstring>
#include <sys/stat.h>
#include <unistd.h>
#include <Foundation/Foundation.h>

// iOS sandbox paths:
//   ~/Documents       — User-visible files (games, saves)
//   ~/Library/Application Support — App data, configs
//   ~/tmp            — Temporary files
//
// On iOS, getenv("HOME") returns the app's sandbox container path.

static std::string GetHomeDirectory()
{
    const char* home = std::getenv("HOME");
    if (home && home[0] != '\0')
        return std::string(home);
    return "/var/mobile/Containers/Data/Application"; // Fallback
}

static std::string GetDocumentsDirectory()
{
    return Path::Combine(GetHomeDirectory(), "Documents");
}

static std::string GetLibraryDirectory()
{
    return Path::Combine(GetHomeDirectory(), "Library/Application Support");
}

static std::string GetTempDirectory()
{
    return Path::Combine(GetHomeDirectory(), "tmp");
}

// Override working directory to Documents
std::string FileSystem::GetWorkingDirectory()
{
    std::string docs = GetDocumentsDirectory();
    if (chdir(docs.c_str()) == 0)
        return docs;
    return GetHomeDirectory();
}

bool FileSystem::SetWorkingDirectory(const char* path)
{
    // On iOS, redirect to Documents if path is relative or empty
    if (!path || path[0] == '\0')
        return chdir(GetDocumentsDirectory().c_str()) == 0;
    return chdir(path) == 0;
}

std::string FileSystem::GetProgramPath()
{
    // On iOS, use NSBundle to get the executable path
    @autoreleasepool {
        NSString* path = [[NSBundle mainBundle] executablePath];
        if (path)
            return std::string([path UTF8String]);
    }
    // Fallback
    return Path::Combine(GetHomeDirectory(), "BionicSX2.app/BionicSX2");
}

// Override: Ensure directories exist in iOS sandbox
bool FileSystem::EnsureDirectoryExists(const char* path, bool recursive, Error* error)
{
    if (FileSystem::DirectoryExists(path))
        return true;

    // If path is relative, prepend Documents
    std::string full_path;
    if (!Path::IsAbsolute(path))
        full_path = Path::Combine(GetDocumentsDirectory(), path);
    else
        full_path = path;

    return FileSystem::CreateDirectoryPath(full_path.c_str(), recursive, error);
}

// iOS: File exists check (POSIX APIs work fine)
bool FileSystem::FileExists(const char* path)
{
    if (!path || path[0] == '\0')
        return false;

    struct stat st;
    if (stat(path, &st) != 0)
        return false;

    return S_ISREG(st.st_mode);
}

bool FileSystem::DirectoryExists(const char* path)
{
    if (!path || path[0] == '\0')
        return false;

    struct stat st;
    if (stat(path, &st) != 0)
        return false;

    return S_ISDIR(st.st_mode);
}
