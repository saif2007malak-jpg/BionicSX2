// SPDX-FileCopyrightText: 2002-2025 PCSX2 Dev Team
// SPDX-License-Identifier: GPL-3.0+
// iOS implementation of CocoaTools using UIKit
// MUST be .mm (Objective-C++) — non-negotiable

#if ! __has_feature(objc_arc)
    #error "Compile this with -fobjc-arc"
#endif

#include "common/CocoaTools.h"
#include "common/Console.h"
#include "common/WindowInfo.h"

#include <UIKit/UIKit.h>
#include <QuartzCore/QuartzCore.h>
#include <dlfcn.h>

// MARK: - Metal Layers

static NSString* _Nonnull NSStringFromStringView(std::string_view sv)
{
    return [[NSString alloc] initWithBytes:sv.data() length:sv.size() encoding:NSUTF8StringEncoding];
}

bool CocoaTools::CreateMetalLayer(WindowInfo* wi)
{
    // Create CAMetalLayer for iOS
    CAMetalLayer* layer = [CAMetalLayer layer];
    if (!layer)
    {
        Console.Error("Failed to create Metal layer.");
        return false;
    }

    // Get the UIView from window_handle
    UIView* view = (__bridge UIView*)wi->window_handle;
    if (!view)
    {
        Console.Error("Invalid window handle for Metal layer.");
        return false;
    }

    [view setOpaque:NO];
    [view.layer addSublayer:layer];
    [layer setFrame:view.bounds];
    [layer setContentsScale:[[UIScreen mainScreen] scale]];

    // Store the layer pointer
    wi->surface_handle = (__bridge_retained void*)layer;
    wi->type = WindowInfo::Type::Surfaceless; // iOS uses surface-less rendering
    return true;
}

void CocoaTools::DestroyMetalLayer(WindowInfo* wi)
{
    if (!wi || !wi->surface_handle)
        return;

    CAMetalLayer* layer = (__bridge_transfer CAMetalLayer*)wi->surface_handle;
    [layer removeFromSuperlayer];
    wi->surface_handle = nullptr;
}

std::optional<float> CocoaTools::GetViewRefreshRate(const WindowInfo& wi)
{
    // iOS: Use UIScreen maximumFramesPerSecond
    // Note: This is only available on iOS 10.0+
    if (@available(iOS 10.0, *))
    {
        UIScreen* screen = [UIScreen mainScreen];
        if (screen)
            return [screen maximumFramesPerSecond];
    }
    // Fallback: assume 60 FPS
    return 60.0f;
}

// MARK: - Bundle/Path Helpers

std::optional<std::string> CocoaTools::GetBundlePath()
{
    std::optional<std::string> ret;
    @autoreleasepool {
        NSURL* url = [NSURL fileURLWithPath:[[NSBundle mainBundle] bundlePath]];
        if (url)
            ret = std::string([url fileSystemRepresentation]);
    }
    return ret;
}

std::optional<std::string> CocoaTools::GetNonTranslocatedBundlePath()
{
    // iOS doesn't have translocation like macOS
    return GetBundlePath();
}

std::optional<std::string> CocoaTools::GetResourcePath()
{
    @autoreleasepool {
        if (NSBundle* bundle = [NSBundle mainBundle])
        {
            NSString* rsrc = [bundle resourcePath];
            return std::string([rsrc UTF8String]);
        }
    }
    return std::nullopt;
}

std::optional<std::string> CocoaTools::MoveToTrash(std::string_view file)
{
    // iOS apps can't move files to trash (no trash on iOS)
    // Delete the file instead
    NSString* path = NSStringFromStringView(file);
    NSError* error = nil;
    if ([[NSFileManager defaultManager] removeItemAtPath:path error:&error])
        return std::string([path fileSystemRepresentation]);
    return std::nullopt;
}

bool CocoaTools::DelayedLaunch(std::string_view file)
{
    // iOS doesn't support launching other apps this way
    Console.Warning("DelayedLaunch not supported on iOS");
    return false;
}

bool CocoaTools::ShowInFinder(std::string_view file)
{
    // iOS doesn't have Finder
    Console.Warning("ShowInFinder not supported on iOS");
    return false;
}

// MARK: - Window Management (iOS uses UIWindow/UIView)

void* CocoaTools::CreateWindow(std::string_view title, uint32_t width, uint32_t height)
{
    // On iOS, we use UIWindow
    UIWindow* window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    [window setBackgroundColor:[UIColor clearColor]];

    // Create a UIView for rendering
    UIView* view = [[UIView alloc] initWithFrame:window.bounds];
    [window addSubview:view];
    [window makeKeyAndVisible];

    return (__bridge_retained void*)view;
}

void CocoaTools::DestroyWindow(void* window)
{
    // Transfer ownership back to ARC for cleanup
    (__bridge_transfer UIView*)window;
}

void CocoaTools::GetWindowInfoFromWindow(WindowInfo* wi, void* cf_window)
{
    if (cf_window)
    {
        UIView* view = (__bridge UIView*)cf_window;
        float scale = 1.0f;
        if (@available(iOS 4.0, *))
            scale = [[UIScreen mainScreen] scale];
        CGRect bounds = view.bounds;

        wi->type = WindowInfo::Type::Surfaceless;
        wi->window_handle = cf_window;
        wi->surface_width = bounds.size.width * scale;
        wi->surface_height = bounds.size.height * scale;
        wi->surface_scale = scale;
    }
    else
    {
        wi->type = WindowInfo::Type::Surfaceless;
    }
}

// MARK: - Theme/Event Handling (stubs for iOS)

void CocoaTools::AddThemeChangeHandler(void* ctx, void(*handler)(void* ctx))
{
    // iOS doesn't have system-wide dark/light theme change notifications like macOS
    // Would need to observe UITraitCollection changes
    Console.Warning("Theme change handler not implemented for iOS");
}

void CocoaTools::RemoveThemeChangeHandler(void* ctx)
{
    // Not implemented for iOS
}

void CocoaTools::MarkHelpMenu(void* menu)
{
    // iOS doesn't have menu bar
    Console.Warning("MarkHelpMenu not supported on iOS");
}

// MARK: - Event Loop (iOS doesn't have Cocoa event loop)

void CocoaTools::RunCocoaEventLoop(bool wait_forever)
{
    // iOS uses UIApplicationMain event loop, not Cocoa run loop
    Console.Warning("RunCocoaEventLoop not applicable on iOS");
}

void CocoaTools::StopMainThreadEventLoop()
{
    // Not applicable on iOS
    Console.Warning("StopMainThreadEventLoop not applicable on iOS");
}
