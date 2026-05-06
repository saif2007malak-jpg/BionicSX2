// SPDX-FileCopyrightText: 2002-2025 PCSX2 Dev Team
// SPDX-License-Identifier: GPL-3.0+
// iOS implementation of HostSys using Darwin XNU calls
// Uses vm_allocate, vm_protect, pthread_jit_write_protect_np

#include "common/HostSys.h"
#include "common/Assertions.h"
#include "common/Console.h"
#include "common/Threading.h"

#include <mach/mach_init.h>
#include <mach/mach_vm.h>
#include <mach/vm_map.h>
#include <mach/vm_prot.h>
#include <pthread.h>
#include <sys/mman.h>
#include <unistd.h>
#include <cstring>

// Page size for iOS (vm_page_size)
static size_t GetPageSize()
{
    return static_cast<size_t>(sysconf(_SC_PAGESIZE));
}

void* HostSys::Mmap(void* base, size_t size, const PageProtectionMode& mode)
{
    pxAssertMsg((size & (GetPageSize() - 1)) == 0, "Size is page aligned");
    if (mode.IsNone())
        return nullptr;

#ifdef __aarch64__
    // On Apple Silicon, we can't allocate executable memory with mach_vm_allocate() directly.
    // Use mmap() with MAP_JIT for JIT pages.
    if (mode.CanExecute())
    {
        if (base)
            return nullptr;

        const int mmap_prot = mode.CanWrite() ? (PROT_READ | PROT_WRITE | PROT_EXEC) : (PROT_READ | PROT_EXEC);
        const int flags = MAP_PRIVATE | MAP_ANON | MAP_JIT;
        void* const res = mmap(nullptr, size, mmap_prot, flags, -1, 0);
        return (res == MAP_FAILED) ? nullptr : res;
    }
#endif

    kern_return_t ret = mach_vm_allocate(mach_task_self(), reinterpret_cast<mach_vm_address_t*>(&base),
        static_cast<mach_vm_size_t>(size),
        base ? VM_FLAGS_FIXED : VM_FLAGS_ANYWHERE);
    if (ret != KERN_SUCCESS)
    {
        DEV_LOG("mach_vm_allocate() returned {}", ret);
        return nullptr;
    }

    vm_prot_t machmode = 0;
    if (mode.CanRead()) machmode |= VM_PROT_READ;
    if (mode.CanWrite()) machmode |= VM_PROT_WRITE;
    if (mode.CanExecute()) machmode |= VM_PROT_EXECUTE;

    ret = mach_vm_protect(mach_task_self(), reinterpret_cast<mach_vm_address_t>(base),
        static_cast<mach_vm_size_t>(size), false, machmode);
    if (ret != KERN_SUCCESS)
    {
        DEV_LOG("mach_vm_protect() returned {}", ret);
        mach_vm_deallocate(mach_task_self(), reinterpret_cast<mach_vm_address_t>(base),
            static_cast<mach_vm_size_t>(size));
        return nullptr;
    }

    return base;
}

void HostSys::Munmap(void* base, size_t size)
{
    if (!base)
        return;

    mach_vm_deallocate(mach_task_self(), reinterpret_cast<mach_vm_address_t>(base),
        static_cast<mach_vm_size_t>(size));
}

void HostSys::MemProtect(void* baseaddr, size_t size, const PageProtectionMode& mode)
{
    pxAssertMsg((size & (GetPageSize() - 1)) == 0, "Size is page aligned");

    vm_prot_t machmode = 0;
    if (mode.CanRead()) machmode |= VM_PROT_READ;
    if (mode.CanWrite()) machmode |= VM_PROT_WRITE;
    if (mode.CanExecute()) machmode |= VM_PROT_EXECUTE;

    kern_return_t res = mach_vm_protect(mach_task_self(),
        reinterpret_cast<mach_vm_address_t>(baseaddr),
        static_cast<mach_vm_size_t>(size), false, machmode);
    if (res != KERN_SUCCESS) [[unlikely]]
    {
        ERROR_LOG("mach_vm_protect() failed: {}", res);
        pxFailRel("mach_vm_protect() failed");
    }
}

size_t HostSys::GetRuntimePageSize()
{
    return static_cast<size_t>(sysconf(_SC_PAGESIZE));
}

#ifdef _M_ARM64

void HostSys::FlushInstructionCache(void* address, u32 size)
{
    __builtin___clear_cache(reinterpret_cast<char*>(address), reinterpret_cast<char*>(address) + size);
}

static thread_local int s_code_write_depth = 0;

void HostSys::BeginCodeWrite()
{
    if ((s_code_write_depth++) == 0)
        pthread_jit_write_protect_np(0);
}

void HostSys::EndCodeWrite()
{
    pxAssert(s_code_write_depth > 0);
    if ((--s_code_write_depth) == 0)
        pthread_jit_write_protect_np(1);
}

#endif // _M_ARM64
