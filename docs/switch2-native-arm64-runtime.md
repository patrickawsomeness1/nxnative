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

## How nxnative already solves native execution on iOS

The upstream nxnative codebase already has a concrete no-JIT native-execution pipeline for original Switch modules. We should adapt that mechanism rather than invent a JIT or an emulator:

1. `dm/tools/patch_nso.py` expands and rewrites a Switch AArch64 NSO offline. It adjusts platform-specific register/thread-local conventions, SVC/timer entry points, and other measured incompatibilities, and emits a patched image plus fixup/gate metadata.
2. `dm/ios/tools/gen_embed.py` emits assembly that embeds the guest's executable text and patch blocks into the app's single signed `__TEXT` segment. Writable data is emitted in a separate RW segment.
3. The complete app is linked and signed as one iOS executable. The guest text is therefore part of the app's signed code image before installation; it is not arbitrary unsigned code downloaded into executable memory at runtime.
4. The iOS branch of `dm/host/loader.c` reserves the guest's address range and uses `vm_remap` to map the signed executable pages back at their expected guest-relative addresses, sharing the signed RX pages, while data is mapped copy-on-write. Relocations and guest thread-local slots are then initialized.
5. Guest ARM64 functions execute directly on the Apple CPU. Horizon kernel/services are supplied by the host compatibility layer, while the graphics interface is handled separately by the Metal backend.

This is the native execution model required for the Switch 2 port. It is not a CPU interpreter and it does not need a general JIT. The key constraint is that all executable guest code and any offline-generated patches must be embedded and signed before installation. A game update or newly imported executable requires rebuilding/re-signing the app or its signed guest-code container; simply selecting an arbitrary file in Files cannot make it executable.

Relevant implementation files in this repository:
- `dm/tools/patch_nso.py`
- `dm/ios/tools/gen_embed.py`
- `dm/ios/tools/build_ipa.sh`
- `dm/host/loader.c` (iOS `vm_remap` path)
- `dm/host/hle_svc.c` and the other `dm/host/hle_*.c` service implementations

Apple requires executable code to be signed and restricts writable/executable memory. We deliberately preserve nxnative's signed-code-section approach instead of depending on a private entitlement or unrestricted JIT.

References:
- [Apple Platform Security: runtime process security](https://support.apple.com/guide/security/security-of-runtime-process-sec15bfe098e/web)
- [Apple Developer: JIT and MAP_JIT requirements](https://developer.apple.com/documentation/BundleResources/Entitlements/com.apple.security.cs.allow-jit)
- [Apple mandatory code signing on iOS/iPadOS](https://support.apple.com/en-us/guide/security/sec7c917bf14/web)


## What current Switch 2 research does and does not establish

- Nintendo's public specification describes a custom NVIDIA processor. Switchbrew's reverse-engineered T239 notes identify eight 64-bit Arm Cortex-A78C cores, 12 GB LPDDR5X, an Ampere GPU, and PAC support. This is useful architectural evidence, not an official Nintendo SDK/ABI specification.
- Switchbrew's compatibility-mode notes describe `nnCompatTrampoline`, `nnCompatThin`, and `nnCompat` being injected when an **original Switch 1 game** runs on Switch 2. This explains the backwards-compatibility path; it does not establish that a native Switch 2 retail title uses the same loader, SDK libraries, executable layout, or NVN2 ABI as Switch 1. The same notes report a 31.25 MHz system-tick frequency in place of 19.2 MHz and corresponding `ConvertToTick` changes in that Switch 1 compatibility layer; treat this as a clock-compatibility lead to verify against native Switch 2 modules, not as a proven native-title constant.
- Public ns2jb/HBLauncher material is an early, tethered userland proof of concept. It is not a kernel-level custom firmware or a retail Switch 2 game loader. Its Vulkan app interface is not NVN2. It must not be used as the basis for the iOS runtime.
- Public Switch 2 extraction tooling is experimental and does not by itself provide the full runtime ABI, keys, or graphics implementation required by nxnative.

Research references:
- [Switch 2 T239 hardware notes](https://switchbrew.org/wiki/Switch_2%3A_Tegra_T239)
- [Switch 2 compatibility mode](https://switchbrew.org/wiki/Switch_2%3A_Compatibility_Mode)
- [Switch 2 research tools status](https://switch2unlock.com/en/tools/)
- [Nintendo official Switch 2 specifications](https://www.nintendo.com/gaming-systems/switch-2/tech-specs/)

Switch 2 uses the NSO0 module container with additional security/compression flags: flag bit 6 is XOM and bit 7 selects ZBIC compression. Switch 2 security research also documents PAC on game return addresses and PAC-related pointer discrimination in newer SDKs; newer game modules may have execute-only text. The shared NSO container therefore gives us a concrete starting point, but Switch 2's PAC/XOM and Horizon ABI cannot be treated as identical to Switch 1.\n\nThe new `dm/tools/nso.py` reader validates NSO segment bounds and optional SHA-256 hashes and supports ZBIC decompression when the `zbic` package is installed. `dm/tools/patch_nso.py` now consumes that validated loader rather than assuming LZ4-only segments. The new `dm/tools/switch2_survey.py` reports XOM/ZBIC flags, NSO dynamic undefined imports and defined symbols, and scans the AArch64 text for PAC, BTI, SVC, LSE atomics and selected system-register instructions. Synthetic NSO parser and survey tests now pass in GitHub Actions. This is analysis infrastructure; it does not yet implement PAC/XOM/SVC compatibility or run a Switch 2 module.\n\nReferences: [NSO0 format and XOM/ZBIC flags](https://switchbrew.org/wiki/NSO), [Switch 2 security mitigations](https://switchbrew.org/wiki/Security_Mitigations).\n\nThese sources support a native ARM64 research direction, but they do not yet provide a verified Switch 2 retail executable loader contract or NVN2 implementation specification. Those must be measured from an authorized self-built test program or authoritative SDK documentation.

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
- The NRO/NSO/ELF reader is metadata inspection only; it is not the Switch 2 loader. The actual nxnative native-execution pipeline is the offline NSO rewriter, signed code embedding, and iOS `vm_remap` loader described above.
- None of these artifacts currently executes Switch 2 guest code.

## Definition of "working"

The first meaningful success is a self-built Switch 2 ARM64 homebrew test reaching its entry point and completing a documented OS call through the compatibility runtime on an actual target iPhone/iPad. The next success is a GPU-independent program plus a Metal-presented frame. Only then should title-specific game compatibility be attempted.
