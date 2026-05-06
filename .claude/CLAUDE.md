================================================================================
  BionicSX2 — MASTER ENGINEERING BRIEF
  Prepared for: Claude Code
  Classification: Primary Reference Document — Consult Before Every Action
================================================================================


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  MISSION STATEMENT
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

The goal of this project is NOT to produce a compilable IPA.
The goal is to ship a PS2 emulator that runs games at maximum performance
on Apple Silicon — fully exploiting the ARM64 architecture, the Metal GPU
pipeline, and the iOS platform capabilities.

Every architectural decision must be made with that end goal in mind.
A working build that cannot run games is a failure.
An emulator that runs games at 30% efficiency is a failure.
Temporary shortcuts are allowed if they are isolated, documented, and scheduled for replacement.


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  MANDATORY CONSTRAINTS — READ AND ENFORCE AT ALL TIMES
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

These are non-negotiable engineering standards. Violating any of them
is not a shortcut — it is guaranteed technical debt that will block progress.

  [1] NO PATCHING. NO GUESSING.
      Never stub, comment out, or patch code without first understanding
      why it exists, what it does, and what the correct iOS replacement is.
      Patching symptoms instead of causes produces cascading failures.

  [2] READ BEFORE YOU WRITE.
      Before editing any file — especially ios_stubs.cpp, CMakeLists.txt,
      or any platform layer — read its full current state.
      Never modify a file you have not read in the current session.

  [3] BATCH ALL CHANGES — ONE COMMIT PER LOGICAL FIX.
      Each build takes 5-6 minutes. Fixing one symbol per commit wastes hours.
      Audit all related issues together, fix them all in a single commit.
      Never push a partial fix.

  [4] STUBS ARE A DIAGNOSTIC TOOL — NOT A SOLUTION.
      ios_stubs.cpp is a temporary scaffold, not an architecture.
      Every stub must carry a comment: // TODO: implement using [specific iOS API]
      The goal is to eliminate every stub over time, not accumulate them.
      A stub that causes a crash at runtime means that code path is active
      and must be implemented immediately — not re-stubbed.

  [5] NEVER GUESS FUNCTION SIGNATURES.
      Before writing any stub or platform implementation, run:
        nm build/pcsx2/libPCSX2.a | c++filt
      to know exactly what the linker expects. Even minor differences
      (const&, string_view vs string, namespace prefix) cause linker failures
      that are expensive to debug.

  [6] NEVER DESIGN FOR THE BUILD — DESIGN FOR THE RUNTIME.
      A project that links but crashes, hangs, or runs at 5 FPS is worthless.
      Every implementation decision must consider runtime behavior,
      not just compilation success.

  [7] NO BLIND ANDROID-TO-iOS TRANSPLANTS.
      Android and iOS share ARM64 but nothing else of consequence.
      Bionic libc ≠ Apple libc. JNI ≠ Objective-C runtime.
      Linux syscalls ≠ Darwin XNU. Every Android-origin code block must be
      audited before use — never assume it works on iOS.


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  FIRST ACTION — ENGINEERING BLUEPRINT (MANDATORY BEFORE ANY CODE)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Before writing a single line of code, produce a complete Engineering Blueprint.
This document is the foundation of the entire project.
Every future decision references it. It must be precise, complete, and honest.

The blueprint must cover all of the following:

  [A] FULL DEPENDENCY AUDIT
      Map every platform-specific dependency in the codebase:
      — What uses the x86 JIT recompiler?       → Must be disabled or replaced
      — What uses Bionic/Linux-specific syscalls? → Must be replaced with Darwin equivalents
      — What uses Android APIs (JNI, AAssetManager, Oboe, JVM)?
                                                  → Must be removed entirely
      — What uses POSIX APIs that differ on iOS?  → Must be audited per function
      — What uses mmap with PROT_EXEC/PROT_WRITE? → Requires iOS-specific memory strategy

  [B] PLATFORM ABSTRACTION LAYER DESIGN
      Define the complete iOS platform layer before implementation:
      — HostSys: vm_allocate / vm_protect (no stubs — real implementation plan)
      — Threading: pthreads or Grand Central Dispatch
      — AudioStream: AVAudioEngine or AudioUnit (Oboe is Android-only — excluded)
      — CocoaTools: Objective-C++ in .mm files — GetBundlePath, CreateMetalLayer,
                    GetViewRefreshRate — none of these can be implemented in .cpp
      — Filesystem: iOS sandbox paths (Documents, Library, tmp) — no assumptions
      — WindowInfo / Rendering surface: CAMetalLayer connected to UIView properly

  [C] CPU EXECUTION ENGINE — ARM64 JIT STRATEGY
      Primary Source Repository: https://github.com/ARMSX2/ARMSX2
      Upstream Reference:        https://github.com/pcsx2/pcsx2

      This is the single most important architectural decision in the project.
      The decision is final and must not be revisited.

      ── WHY NO EXTERNAL JIT SOURCE ───────────────────────────────────────────
      Any external PS2 emulator JIT is built around a different CPU architecture,
      memory management model, recompiler table design, and VU0/VU1 implementation.
      Extracting such a JIT and integrating it into PCSX2 is not "borrowing a library"
      — it requires building a complete translation layer between two incompatible designs.
      This would waste months with no guaranteed result, and is harder than writing
      a JIT from scratch. No external JIT source will be used. This decision is closed.

      ── THE CORRECT FOUNDATION: VIXL is already in the project ───────────────
      The ARMSX2 codebase (Android ARM64 fork of PCSX2) already includes VIXL:
      https://github.com/ARMSX2/ARMSX2
      VIXL is the foundation we build on for iOS ARM64 JIT.
      The Interpreter already understands EE Core, VU, and IOP — it is the
      frontend, and it is complete. We build on top of what exists.

      JIT construction path:
        1. Interpreter serves as the complete PS2 frontend (already done).
        2. Add a code cache on top of the Interpreter.
        3. For each MIPS instruction, emit ARM64 equivalent using VIXL.
        4. Handle iOS W^X memory using pthread_jit_write_protect_np()
           — available on iOS 14.2+, required for JIT pages.

      Zero integration friction: everything is inside the same codebase,
      uses the same memory model, and shares the same PS2 internals understanding.

      ── VU0 / VU1 STRATEGY ───────────────────────────────────────────────────
      Source: ARMSX2 codebase — already adapted for ARM64 Android.

      Relevant files already in the project:
        VU0.cpp, VU1.cpp, VUmicro.cpp, VUops.cpp
        VUmicroMem.cpp, VUmicroInterp.cpp

      ARMSX2 already replaced x86 SSE with ARM64 NEON intrinsics.
      Approximately 80% of the VU code works on iOS without modification.
      NEON intrinsics (vaddq_f32, vmulq_f32, vld1q_f32, etc.) are part of
      the ARM architecture — identical on Android and iOS.

      What must change for iOS:
        REMOVE:  #include <android/log.h>  →  os/log.h
                 __android_log_print()     →  os_log()
                 Any JNIEnv*, jobject, jstring references → delete entirely
        REPLACE: mmap() with MAP_ANON      →  vm_allocate() / vm_protect()
        KEEP:    All NEON intrinsics — identical on iOS
                 pthreads — identical on iOS
                 VU pipeline logic — fully portable

      VU execution stages:
        VU Stage 1 — Interpreter (VUmicroInterp.cpp, Android APIs replaced)
                     Goal: correctness. Games run slow — expected and acceptable.

        VU Stage 2 — VU0 JIT via COP2 path
                     Translate VU0 micro-instructions → ARM64 NEON using VIXL.
                     Unblocks geometry processing for most 3D titles.

        VU Stage 3 — VU1 JIT
                     VU1 runs independently and feeds the GS directly.
                     Requires careful thread synchronization with EE Core.

        VU Stage 4 — NEON optimization pass for Apple Silicon (A15–A18 FMAC units)
                     Apple Silicon (A15–A18) has 4 FMAC units — exactly what
                     VU emulation requires. Optimize hot paths for Apple Silicon.
                     Target: full-speed geometry on A15 and newer.

      ── FULL PROJECT EXECUTION PHASES ────────────────────────────────────────

        Phase 1 — Interpreter only. Goal: boot to BIOS.
        Phase 2 — EE Core JIT via VIXL. MIPS R5900 → ARM64. Basic code cache.
        Phase 3 — VU0/VU1 JIT. SIMD → ARM64 NEON. Source: ARMSX2 VU code.
        Phase 4 — IOP JIT + Apple Silicon microarchitecture optimizations.

      Constraint: Do not design any phase in a way that makes the next harder.
      Each phase must leave clean integration points for the one that follows.

      ── SUMMARY ──────────────────────────────────────────────────────────────
      VIXL is in the project. The Interpreter is in the project.
      The VU0/VU1 NEON-adapted code is in the project via ARMSX2.
      The PS2 memory and CPU models are already understood by the codebase.
      Building the JIT on top of this is an extension — not a rewrite.
      Any external JIT source introduces an impedance mismatch that costs
      more time than it saves. No external JIT source will be used.

  [D] PCSX2 macOS → iOS COMPONENT TRANSFER PLAN
      Repository: https://github.com/pcsx2/pcsx2

      We do not build from scratch. PCSX2 macOS is the donor codebase.
      Every component below has been audited for portability before any work begins.

      ── TIER 1: DIRECT PORT — Minimal changes required ────────────────────────

      Metal Rendering Backend
        Files:   GSDeviceMTL.mm, GSTextureMTL.mm, all .metal shader files
        Changes: NSView → UIView, CVDisplayLink → CADisplayLink
        Notes:   Metal Shading Language is identical on macOS and iOS.
                 Texture format mapping (PS2 GS → MTLPixelFormat) requires no changes.

      CocoaTools
        Functions: GetBundlePath(), GetResourcePath(), CreateMetalLayer(),
                   DestroyMetalLayer()
        Changes:   NSScreen → UIScreen for GetViewRefreshRate()
                   Bundle/sandbox path roots differ — update path constants only.

      Threading
        macOS uses pthreads and Grand Central Dispatch.
        Both are identical on iOS. Zero changes required.

      Filesystem Layer
        NSFileManager API is identical on iOS.
        Change: path roots only (~/Documents → iOS sandbox Documents directory).
        File read/write logic carries over without modification.

      Memory Management (partial)
        vm_allocate, vm_protect, vm_deallocate — same Darwin XNU calls on iOS.
        Change: PROT_EXEC pages require com.apple.security.cs.allow-jit entitlement.

      Common Utilities
        String utilities, math helpers, mach_absolute_time timers — identical on iOS.
        No changes required.

      ── TIER 2: NEEDS ADAPTATION — Same concept, different API ───────────────

      Audio Stream
        macOS: CoreAudio / AudioUnit
        iOS:   Same frameworks exist. AVAudioEngine API is identical.
        Change: Remove AppKit audio session handling.
                Add AVAudioSession configuration (mandatory on iOS, absent on macOS).

      Display Synchronization
        macOS: CVDisplayLink
        iOS:   CADisplayLink
        Direct API swap — same concept, different class name. Low risk.

      Window / Surface Management
        macOS: NSWindow + NSView + CAMetalLayer
        iOS:   UIWindow + UIView + CAMetalLayer
        CAMetalLayer itself is identical on both platforms.
        Change: UIKit view lifecycle replaces AppKit lifecycle.

      Input Handling
        macOS: NSEvent (keyboard, mouse, gamepad)
        iOS:   UITouch, UIGestureRecognizer, GCController
        GCController (MFi / Xbox / PlayStation controllers) — identical API on iOS.
        New work: touch input layer for on-screen controls.

      Settings / Preferences
        NSUserDefaults — identical API on iOS.
        INI file reading — fully platform-agnostic. No changes.

      ── TIER 3: CANNOT BE PORTED — Must be rewritten or excluded ─────────────

      x86 JIT Recompiler
        Files:   iCore.cpp, recVTLB.cpp, x86Emitter and all dependents
        Status:  x86-specific. Cannot execute on ARM64 iOS under any circumstance.
        Action:  Excluded entirely via CMake flag -DPCSX2_TARGET_IOS=ON
        Replace: ARM64 JIT built internally using VIXL (see Section [C]).
                 EE Core: VIXL-based MIPS R5900 → ARM64 recompiler.
                 VU0/VU1: ARMSX2 NEON-adapted interpreter code, then JIT via VIXL.
                 Source:  https://github.com/ARMSX2/ARMSX2
                 No external JIT source is used.

      AppKit UI Layer
        NSWindowController, NSViewController, NSMenu, NSToolbar — all excluded.
        Replace: UIKit or SwiftUI frontend, decoupled from emulator core via C++ API.

      macOS Entitlements
        Hardened Runtime entitlements are macOS-specific and incompatible with iOS.
        Action: Rebuild entitlements.plist for iOS from scratch.
        Required: com.apple.security.cs.allow-jit + standard iOS signing entitlements.

      Sparkle / Software Update
        macOS-only auto-update framework. Not available on iOS.
        Replace: TestFlight for beta distribution. App Store for release.

      ── PORTABILITY SUMMARY TABLE ─────────────────────────────────────────────

      | Component                      | Tier          | Effort      |
      |--------------------------------|---------------|-------------|
      | Metal backend (GSDeviceMTL)    | Direct port   | Low         |
      | Metal shaders (.metal)         | Direct port   | Low         |
      | CocoaTools                     | Direct port   | Low         |
      | Threading / GCD                | Direct port   | None        |
      | Filesystem                     | Direct port   | Low         |
      | vm_allocate / vm_protect       | Direct port   | Low         |
      | CoreAudio / AVAudioEngine      | Adaptation    | Medium      |
      | CVDisplayLink → CADisplayLink  | Adaptation    | Low         |
      | NSView → UIView                | Adaptation    | Medium      |
      | GCController (gamepad)         | Direct port   | None        |
      | NSUserDefaults / Settings      | Direct port   | None        |
      | x86 JIT                        | Cannot port   | Replace (VIXL + ARMSX2 NEON, see [C]) |
      | AppKit UI                      | Cannot port   | Full rewrite|
      | Entitlements                   | Cannot port   | Rebuild     |

  [E] BUILD SYSTEM DESIGN
      Do not patch CMakeLists.txt reactively. Design the build system upfront:
      — Create a proper iOS CMake toolchain file (ios.toolchain.cmake)
      — Use a single top-level flag: -DPCSX2_TARGET_IOS=ON
        This flag must:
          * Disable the x86 JIT and all recompiler files
          * Select iOS platform implementations over Android/Linux ones
          * Exclude all Android-specific code paths
          * Link correct Apple frameworks (Metal, MetalKit, AVFoundation,
            AudioUnit, UIKit, Foundation)
      — Never use conditional compilation scattered across the codebase.
        Platform selection must be centralized and traceable.

  [F] KNOWN FAILURE PATTERNS — MUST BE PRE-EMPTED IN THE BLUEPRINT
      These problems were encountered in prior work on this project.
      The blueprint must address each one with a concrete prevention strategy:

      1. ios_stubs.cpp symbol loops
         Symptom: add stubs → duplicate symbols → remove stubs → undefined symbols → repeat
         Prevention: run nm | c++filt before touching stubs. Understand what is
         defined in the static library vs what needs to be provided externally.

      2. Signature mismatches
         Symptom: stubs compile but linker rejects them due to const&, string_view,
         or namespace differences.
         Prevention: always derive signatures directly from header files — never write
         from memory.

      3. Edit-without-read regression
         Symptom: fixing one stub breaks three previously working ones because the
         file was modified without reading its current state.
         Prevention: enforce read-before-write as an absolute rule.

      4. CocoaTools in .cpp files
         Symptom: Objective-C runtime calls fail at link time or crash at runtime.
         Prevention: all CocoaTools implementations go in .mm files — this is
         non-negotiable. Objective-C cannot be used in .cpp files.

      5. Global variable type mismatches
         Symptom: g_common_hotkeys or g_host_hotkeys defined as wrong type,
         causing silent linker errors or runtime corruption.
         Prevention: derive all global variable types from their declaration in
         headers before defining them in platform files.

      6. One-symbol-per-commit waste
         Symptom: 5-6 minute builds used to fix one missing symbol at a time.
         Prevention: audit all undefined symbols in a single pass,
         fix all of them in a single commit.

  [G] PHASED ROADMAP WITH DELIVERABLES
      Break the project into explicit phases. Each phase has a single,
      verifiable success criterion. No phase begins until the previous one passes.

        Phase 0 — Blueprint & Audit
          Deliverable: This document, completed. Full dependency map produced.
          No code written until this phase is signed off.

        Phase 1 — Build System Foundation
          Deliverable: Project compiles for iOS target with zero Android dependencies.
          Interpreter mode only. No game execution required yet.

        Phase 2 — Platform Layer
          Deliverable: All platform stubs replaced with real iOS implementations.
          HostSys, CocoaTools, AudioStream, Filesystem all functional.

        Phase 3 — BIOS Boot
          Deliverable: Emulator reaches BIOS screen on a physical iOS device.
          Metal surface renders output. Audio initializes without crash.

        Phase 4 — Game Execution (Interpreter)
          Deliverable: At least one commercial PS2 title reaches in-game on interpreter.
          Frame rate will be low — that is expected and acceptable at this stage.

        Phase 5 — ARM64 JIT
          Deliverable: VIXL-based ARM64 recompiler integrated and functional.
          Measurable performance improvement over interpreter baseline.

        Phase 6 — Metal Optimization
          Deliverable: Metal backend optimized for Apple Silicon.
          Target: 60 FPS on representative PS2 titles on A15 or newer.

        Phase 7 — UI & Distribution
          Deliverable: SwiftUI or UIKit frontend. TestFlight distribution.
          Clean C++ API boundary between emulator core and UI layer.


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  PROJECT OVERVIEW
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Project:   BionicSX2
  Base:      PCSX2 → Android fork (ARMSX2 / BionicSX2 origin)
  Target:    iOS / iPadOS on ARM64 (Apple Silicon)
  License:   GPL 3.0 — fully open-source
  Hosting:   GitHub

  Source lineage:
    PCSX2 was designed for x86 Windows/Linux.
    The Android fork adapted it for ARM64 using Bionic libc.
    iOS is also ARM64 but runs on Darwin/XNU with Apple's libc,
    a different memory model, a different runtime, and strict security policies.
    These differences are significant and cannot be glossed over.


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  DEVELOPMENT ENVIRONMENT
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  | Tool                | Role                                            |
  |---------------------|-------------------------------------------------|
  | GitHub Codespaces   | Cloud-based development environment             |
  | GitHub Actions      | Automated IPA build via macOS runner            |
  | AI Assistant        | Engineering guidance and code review            |
  | TestFlight          | Beta distribution and device testing            |


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  PROJECT STRUCTURE (TARGET)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  BionicSX2/
  ├── .github/
  │   └── workflows/
  │       └── build-ipa.yml          ← GitHub Actions pipeline
  ├── src/                           ← PCSX2/BionicSX2 core (platform-agnostic)
  ├── ios/
  │   ├── platform/                  ← iOS platform layer (.cpp and .mm)
  │   │   ├── HostSys_iOS.cpp        ← vm_allocate / vm_protect
  │   │   ├── CocoaTools.mm          ← Objective-C++ implementations
  │   │   ├── AudioStream_iOS.cpp    ← AVAudioEngine / AudioUnit
  │   │   └── Filesystem_iOS.cpp     ← iOS sandbox-aware paths
  │   ├── ui/                        ← SwiftUI or UIKit frontend
  │   ├── entitlements/              ← com.apple.security.cs.allow-jit + others
  │   └── Info.plist
  ├── metal/                         ← Native Metal rendering backend
  │   ├── MetalRenderer.mm
  │   ├── Shaders.metal
  │   └── FrameSync.mm
  ├── cmake/
  │   └── ios.toolchain.cmake        ← iOS cross-compilation toolchain
  └── CMakeLists.txt


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  TECHNICAL CHALLENGE MATRIX
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  | Challenge              | Strategy                                       |
  |------------------------|------------------------------------------------|
  | x86 JIT on iOS         | Excluded via CMake. Interpreter first.         |
  |                        | ARM64 JIT via VIXL — already in the project.  |
  |                        | VU0/VU1 via ARMSX2 NEON-adapted code.         |
  | JIT memory permissions | pthread_jit_write_protect_np() — iOS 14.2+    |
  |                        | com.apple.security.cs.allow-jit entitlement.   |
  | Graphics API           | Port PCSX2 macOS Metal backend to iOS.         |
  |                        | github.com/pcsx2/pcsx2 — no rebuild from scratch|
  | Android dependencies   | Full audit in Phase 0. Removed entirely.       |
  | CocoaTools             | Implemented in .mm files — not stubbed.        |
  | Audio                  | AVAudioEngine or AudioUnit. Oboe excluded.     |
  | Build pipeline         | GitHub Actions macOS runner → unsigned IPA.   |
  | UI layer               | SwiftUI/UIKit frontend, decoupled from core.   |


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  DECISION TABLE — RIGHT VS WRONG APPROACH
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  | Wrong                              | Right                                |
  |------------------------------------|--------------------------------------|
  | Add stubs until it links           | Implement real platform APIs         |
  | Patch errors one by one            | Audit all dependencies upfront       |
  | One giant ios_stubs.cpp            | Proper platform layer per subsystem  |
  | Copy Android code without analysis | Understand what each module does     |
  | Disable JIT permanently            | Plan ARM64 JIT from day one          |
  | Fix linker errors reactively       | Design build system proactively      |
  | Commit one fix per build cycle     | Batch all related fixes, one commit  |
  | Write stubs from memory            | Derive signatures from header files  |
  | Edit files without reading them    | Read full file state before editing  |
  | Ship with known broken subsystems  | Every subsystem must have a real plan|


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  CLOSING DIRECTIVE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

This document is the single source of truth for the project.
Before every action — read it.
Before every commit — verify it is consistent with what is written here.
Before every architectural decision — confirm it serves the mission statement.

The measure of success is not a green CI pipeline.
The measure of success is a PS2 game running at full speed on an iPhone.

Build accordingly.

================================================================================
