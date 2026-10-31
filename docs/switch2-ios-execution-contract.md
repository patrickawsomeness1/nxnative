# Switch 2 iOS execution contract (design gate)

Status: architecture contract only. This document defines what a future native execution path must prove; it does not implement a loader or claim that Switch 2 code runs on iOS.

## Goals

- Keep the Switch 1 loader and rewriter unchanged.
- Give Switch 2 a separate, explicitly selected guest-image path.
- Make the first executable target a self-built, graphics-free homebrew probe.
- Keep imported game files as data until a validated, supported build pipeline explicitly transforms an authorized input into a signed app.
- Fail closed on unknown formats, unsupported relocations, address conflicts, missing imports, or unsupported guest services.

## Image classes are not interchangeable

| Input | What can be established now | What must not be assumed |
| --- | --- | --- |
| NSO | The survey tool can inspect bounded headers, segment metadata, hashes, compression flags, and selected AArch64 instructions. | A parsed NSO is not a loaded process. Switch 2 relocations, entry ABI, imports, and memory layout are not yet supported. |
| NRO / ELF | Magic or ELF structure can identify a candidate container. | Identification does not establish a valid Switch 2 executable or a compatible entry ABI. |
| HBLauncher ABI 3 | The pinned SDK defines fixed-address `code.bin` / `data.bin`, a 0x2b8-byte context, and an `_start` trampoline. | It is not an NSO and must not be passed to `load_modules()`. Its service calls are HBLauncher-specific. |
| NSP / XCI / NCA | The desktop inspector can identify container signatures and safely list PFS0/HFS0 metadata where supported. | No decryption, title installation, content extraction, or execution is implemented. |

## Required stages

### A. Static validation (host-side; no execution)

Before any guest bytes are considered for a build:

1. Identify the exact container and inner executable format.
2. Validate every offset, size, alignment, count, and arithmetic operation with overflow-safe bounds checks.
3. Validate segment ranges and reject overlaps unless the format explicitly defines the relationship.
4. Parse the actual relocation and import tables; reject unknown relocation types and unresolved symbols.
5. Verify hashes when the format supplies them and record which checks were possible.
6. Produce a machine-readable report that distinguishes `identified`, `structurally_valid`, `supported_for_build`, and `unsupported`.
7. Never infer that an extension or magic value alone proves the file is safe or executable.

### B. Signed build (Mac-side; no JIT)

The intended iOS route is a build-time transformation, not a runtime downloader or JIT:

- Imported executable content remains inert data until a supported converter has validated it.
- Any native executable instructions that the iOS app will execute must be incorporated through a documented, reproducible build/link/sign process and covered by the app's code signature.
- Do not mark arbitrary imported data pages executable, generate executable memory, or assume that `mmap`/`mprotect` can turn downloaded bytes into runnable code on stock iOS.
- Do not bypass platform code-signing, executable-memory, entitlement, or App Store policy controls.
- The Mac tool must show the exact transformation, toolchain version, target architecture, signing identity, and resulting artifact hash.
- If an input cannot be transformed into a signed image under the supported policy, stop with a clear unsupported result. Do not silently fall back to JIT or an unsigned executable mapping.

A signed Mach-O bundle is not sufficient by itself: the guest ABI, relocations, imports, memory layout, and operating-system calls must also be implemented and tested.

### C. Runtime admission

A future Switch 2 runtime may admit an image only when all of the following are true:

- The image format and ABI are explicitly supported by the Switch 2 backend.
- Entry point, stack, TLS, memory regions, permissions, and relocation results are validated.
- All executable pages are backed by code included in the signed app build; writable guest data remains non-executable.
- Every imported service/function resolves to an implemented, versioned host interface.
- Unsupported SVCs, IPC descriptors, handles, services, and GPU calls return explicit errors rather than fabricated success.
- A test report records the exact image hash, backend version, device/OS, and completed test stages.

### D. First runtime milestone

The first milestone is not a retail game. It is a self-authored, graphics-free Switch 2 homebrew probe that:

1. Reaches its verified entry point.
2. Reads a known context value and writes a result marker.
3. Calls one independently verified OS service.
4. Performs a bounded heap allocation and read/write test.
5. Exits cleanly and produces a reproducible log.

Only after that should the backend add threads, synchronization, IPC, and graphics. Each capability needs a console trace or authoritative ABI source plus a host-side regression test.

## iOS memory and address-space constraints

- Do not assume a fixed guest virtual address is available in the iOS process. Reserve and validate the entire range before loading anything; reject collisions.
- Do not assume Switch 2 guest page sizes, mapping flags, cache-maintenance rules, or exception behavior match Switch 1.
- Separate guest virtual addresses from host pointers. Never dereference a guest-provided address without an explicit, validated translation.
- Enforce W^X: writable data and executable code must not share a writable-executable mapping.
- PAC and BTI instruction presence in a static survey is not proof that the loader, signing model, or guest ABI is compatible with the Apple host.
- Measure address-space use, resident memory, allocation failures, and thermal behaviour on physical devices. CI compilation is not a device runtime test.

## NX2Apple product contract

The Mac GUI should expose honest, staged states:

- **Inspect** — identify files and show validated metadata.
- **Prepare** — run only supported, reproducible conversion steps.
- **Build** — create a signed iOS app using the documented toolchain.
- **Install** — install the signed app to a connected, authorized device.
- **Run report** — show which guest stages actually completed.

The GUI must not label a diagnostic app as a game port, label a file as playable based on its extension, or report installation as proof of successful launch. Signing and device installation require the user's own valid development signing setup and device trust.

## Current blockers (explicit)

1. No captured Switch 2 retail/homebrew loader trace establishes the native NSO entry ABI and memory map.
2. The current Switch 2 HIPC/CMIF code is a host-side framing prototype; service-manager and kernel-handle semantics are unverified.
3. No Switch 2-specific NSO relocation/import loader exists.
4. No complete no-JIT signed-image conversion pipeline exists.
5. No Switch 2 NVN2-to-Metal implementation exists.
6. The HBLauncher probe has been cross-built in CI but has not been reported running on physical Switch 2 hardware.
7. The iOS Metal app is a platform diagnostic, not a guest runtime.

## Exit criteria for changing this status

Do not mark this contract implemented until there is a separate Switch 2 loader with tests for malformed images, relocations, imports, address collisions, memory permissions, entry/exit, and a physical-device run of the self-built probe. Do not mark retail compatibility until a title-specific test report demonstrates it.
