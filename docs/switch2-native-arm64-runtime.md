# Switch 2 native ARM64 execution on iOS/iPadOS

## Product definition

The target is a native ARM64 compatibility runtime for iPad Air M3 and iPhone 17 Pro Max. Do not describe the target as a full-system emulator or build another homebrew launcher.

The Switch 2 uses a custom NVIDIA processor. Independent hardware documentation identifies its CPU as eight 64-bit Arm Cortex-A78C cores; Nintendo's own public specification confirms only that the processor is custom NVIDIA silicon. The Apple targets also execute AArch64 machine code. That shared instruction-set family creates an opportunity for direct host-CPU execution of compatible guest user-mode code, without interpreting every guest instruction.

Sources:
- [Nintendo Switch 2 official technical specifications](https://www.nintendo.com/gaming-systems/switch-2/tech-specs/)
- [Switch 2 T239 hardware notes](https://switchbrew.org/wiki/Switch_2%3A_Tegra_T239)

## Execution model

1. **Native ARM64 guest execution:** Map guest virtual memory and, where the executable format, instruction features, ABI, and iOS code-signing policy permit, dispatch compatible AArch64 guest code on the Apple CPU. Do not add an instruction interpreter as the default architecture.
2. **Compatibility runtime:** Implement the guest process loader, relocations, TLS, thread/context setup, synchronization, memory mapping semantics, and the specific Horizon SVC / IPC / service interfaces actually required by the selected test program.
3. **Graphics boundary:** Implement the Switch 2 graphics-facing API separately and translate its commands, resources, synchronization, and shaders to Metal. Native CPU execution does not make NVIDIA GPU commands executable by Apple GPU hardware.
4. **Host services:** Map controller input, audio, filesystem access, timing, and app lifecycle to public iOS/iPadOS APIs.
5. **One runtime, two device profiles:** Share the guest compatibility code, but query Metal limits, memory budget, display, thermal state, and available CPU features at runtime on M3 iPad Air and A19 Pro iPhone 17 Pro Max.

## Critical iOS execution constraint

A normal iOS/iPadOS app cannot assume it may load arbitrary user-imported ARM64 binaries as executable code. Apple enforces code signing and non-executable writable memory. Apple documents that executable/writable pages and JIT are restricted to tightly controlled, specially entitled cases; third-party apps cannot grant themselves Apple's private dynamic-code-signing entitlement.

References:
- [Apple Platform Security: runtime process security](https://support.apple.com/guide/security/security-of-runtime-process-sec15bfe098e/web)
- [Apple Developer: JIT and MAP_JIT requirements](https://developer.apple.com/documentation/BundleResources/Entitlements/com.apple.security.cs.allow-jit)

Therefore the native-execution design has a platform gate which must be resolved before promising arbitrary game-file execution:

- **No-JIT / ordinary signed IPA:** use a per-title offline native packaging or ahead-of-time translation process on a Mac, then include the resulting code in an app that is signed as a whole before installation. This is not a universal drop-in loader; dynamic modules, relocations, code generation, and runtime patching must be handled by the build pipeline.
- **JIT-capable development environment:** only pursue this as a separate experimental configuration if the actual device, signing method, OS version, and legally available entitlement demonstrably permit executable guest pages. Never assume a public App Store entitlement.
- **Fallback:** if neither path is available, the product cannot truthfully claim direct native execution of arbitrary imported game binaries on stock iOS. A CPU interpreter would be a different architecture and must not silently replace the requested design.

## First implementation milestones

### A. Host ISA and ABI probe
Build a small, signed ARM64 test executable into the app. Record host CPU architecture, supported instruction features, pointer-authentication behaviour, page size, memory mapping behaviour, thread primitives, and Metal device capabilities. This validates the Apple host; it does not execute a Switch 2 game.

### B. Guest image survey
Create a read-only parser and report generator for a legally supplied Switch 2 homebrew executable. Identify its actual container, ELF/Mach-O-like headers if applicable, segments, relocations, imports, TLS, entry point, required CPU features, and dynamic modules. Do not infer Switch 2 retail formats from original Switch NRO/NSO files.

### C. Native execution feasibility test
Choose a tiny self-built guest ARM64 test with known entry point and no GPU dependency. Prove the selected signed execution strategy on a physical iPad and iPhone. Measure exact failure modes if code signing or executable-page policy blocks it. No retail title is the first test.

### D. Minimal OS compatibility
Only after C succeeds, implement the observed loader and minimal Horizon ABI needed for the test: process entry, memory, threads, synchronization, clock, logging, and IPC. Add each service only with evidence and tests.

### E. Graphics
Survey Switch 2's actual graphics API/ABI and shader representation. Implement the Metal translation boundary incrementally. The existing Switch 1 NVN backend is not a substitute for Switch 2 graphics.

### F. Real homebrew execution
Run the self-built test to completion and present a rendered frame on both Apple devices. Record device logs, correctness checks, memory use, thermal behaviour, and reproducible build artifacts.

## Scope of existing bring-up artifacts

- The SwiftUI/Metal dashboard is only an Apple GPU smoke test.
- The NRO/NSO/ELF reader is metadata inspection only. NRO/NSO are original Switch formats; they are not a Switch 2 loader.
- The HBLauncher probe is an optional, separate console-side diagnostic built for that launcher's own ABI. It is not the Switch 2 runtime and must not define the product architecture.
- None of these artifacts currently executes Switch 2 guest code.

## Definition of "working"

The first meaningful success is a self-built Switch 2 ARM64 homebrew test reaching its entry point and completing a documented OS call through the compatibility runtime on an actual target iPhone/iPad. The next success is a GPU-independent program plus a Metal-presented frame. Only then should title-specific game compatibility be attempted.
