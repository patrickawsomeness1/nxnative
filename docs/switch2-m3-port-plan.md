# Switch 2 on iPad Air M3 — bring-up plan

Status: **research / architecture plan only**. This document does not claim that Switch 2 software currently boots in this repository. The public nxnative codebase is a Nintendo Switch (Tegra X1 / NVN) native-execution project. Switch 2 support is a separate, experimental port.

Target devices: **iPad Air (M3)** and **iPhone 17 Pro Max (A19 Pro)**. Both iPadOS and iOS are first-class targets, sharing one Switch 2 runtime with device-specific profiles. A Mac build may be used as a development/test host, but it is not the product target.

## Why a separate backend is required

The existing renderer in `dm/gfx/nvn/` takes over the original Switch NVN interface and replays its command stream through Metal (`hle_nvn.c`, `nvn_mtl.m`). Its shader and texture assumptions are specific to the original Switch GPU generation. Switch 2 introduces NVN2 and a different NVIDIA GPU generation. Treating NVN2 as a few extra NVN entry points would be unsafe: object layouts, command submission, shader formats, synchronization, memory mapping, and device queries must be measured and implemented against Switch 2 behaviour.

The existing Horizon host is also not automatically a Switch 2 host. Loader metadata, SVC behaviour, kernel objects, IPC services, filesystem interfaces, and process capabilities must be surveyed from a lawful homebrew test environment before adding compatibility code.

## Proposed architecture

Keep the existing Switch 1 path intact. Add a separately selectable Switch 2 path:

- `dm/host/switch2/`: Switch 2 title/NSO loader profile, ABI checks, Horizon compatibility deltas, and platform capability declarations. Reuse generic host code only after its assumptions are verified.
- `dm/gfx/nvn2/`: NVN2-facing interface, object model, command recorder, and validation logs. Do not share Switch 1 object structs or function tables by assumption.
- `dm/gfx/nvn2/metal/`: NVN2-to-Metal replay backend. Start with device creation, a clear-only frame, then buffers, textures, barriers, and basic rasterization.
- `dm/shaders/switch2/`: shader inspection and translation experiments, kept separate from the Maxwell/Ryujinx shader path until the Switch 2 shader ISA and container format are verified.
- `dm/tests/switch2/`: host-side tests and device smoke tests that need no commercial game content.
- iPad app shell: expose a **Switch 2 experimental** runtime choice only when the Switch 2 backend is built; preserve the current Switch 1 flow.

## Bring-up milestones

### 0. Establish a reproducible baseline

- Pin the upstream nxnative commit this fork is based on.
- Build and run an existing Switch 1 homebrew/test title on the M3 iPad Air.
- Capture device logs, memory high-water mark, GPU family/features, OS version, and build settings.
- Keep the existing Switch 1 build green throughout the port.

Exit criterion: a repeatable baseline build and log bundle from the target iPad.

### 1. Switch 2 homebrew survey

Use a small, self-built Switch 2 homebrew test program—not a commercial game—to record:

- executable/module format and loader metadata;
- SDK and NVN2 version queries;
- imported symbols and unresolved imports;
- SVC numbers and observed calling conventions;
- service-manager / IPC requests made during startup;
- GPU device queries, object creation order, queue setup, and first present;
- shader container headers and binary hashes (metadata only at first).

Exit criterion: a written ABI/API survey with evidence for every compatibility requirement. Do not guess function signatures or object sizes.

### 2. CPU and Horizon compatibility

- Compare Switch 2 module loading and relocations with the existing NSO rewriter.
- Add only observed Switch 2 ABI / SVC differences behind the Switch 2 runtime selector.
- Implement the minimum services required by the test program.
- Add tests for guest memory mapping, thread creation, synchronization, and IPC lifetimes.

Exit criterion: the homebrew test reaches its entry point and completes basic OS calls without entering the graphics path.

### 3. NVN2 Metal smoke test

Implement in this order:

1. NVN2 device initialization and queried limits;
2. queue and command-buffer lifecycle;
3. swapchain/presentation surface;
4. clear-only frame;
5. GPU-visible fences and waits;
6. buffer allocation and upload;
7. texture allocation and format mapping;
8. shader loading/translation;
9. one indexed triangle and a textured quad.

Exit criterion: stable, repeatable homebrew rendering on both the M3 iPad Air and A19 Pro iPhone 17 Pro Max with validation logs and no Switch 1 regressions.

### 4. Performance and compatibility

- Measure CPU, GPU, memory, thermal throttling, and frame pacing separately.
- Use dynamic resolution and conservative texture residency on the 8 GB iPad Air.
- Do not promise 60 fps; first target correctness and stability at a modest resolution.
- Add game compatibility only after a title-specific survey and test report.

## Target device constraints

### iPad Air (M3)

The M3 iPad Air has an 8-core CPU, 9-core GPU, and 8 GB unified memory. Treat this as a fixed practical budget shared by iPadOS, the app, guest memory, shader caches, and render targets.

### iPhone 17 Pro Max (A19 Pro)

The iPhone 17 Pro Max uses A19 Pro with a 6-core CPU and 6-core GPU, hardware-accelerated ray tracing, and a vapor-chamber thermal design. Independent reporting based on Xcode 26 identifies 12 GB RAM for this model; treat that as a planning estimate, not an Apple-published specification. Its smaller enclosure requires separate sustained-load testing.

### Shared device strategy

Both devices are credible Apple Silicon targets for the first graphics smoke test. They must not share hard-coded memory or GPU assumptions: query available memory, Metal feature sets, texture limits, and display capabilities at runtime. Large commercial titles may exceed either device's practical budget even if the backend is correct.

Build one portable runtime with per-device profiles. The iPad profile can prioritize resolution and larger touch/controller layouts; the iPhone profile should use a more conservative render scale, memory budget, and thermal governor. Optional advanced GPU paths must have conservative fallbacks on both.

## Verified vs. experimental

**Verified in the existing repository**
- The Switch 1 path intercepts NVN through `nvnBootstrapLoader`.
- Its current replay backend uses Metal and zero-copy unified-memory buffers.
- The existing shader path is based on Tegra X1 / Maxwell shader translation.
- The M3 iPad Air has an 8-core CPU, 9-core GPU, and 8 GB memory.
- The iPhone 17 Pro Max uses A19 Pro with a 6-core CPU and 6-core GPU; Apple documents its vapor-chamber thermal design. Its 12 GB RAM figure is independently reported from Xcode 26, not published in Apple's spec sheet.

**Experimental / not yet verified here**
- Switch 2 module execution on this fork.
- Switch 2 Horizon service compatibility.
- NVN2 function coverage and object layouts.
- Switch 2 shader translation to Metal.
- Commercial Switch 2 game boot, graphics correctness, performance, or compatibility on iPadOS.

## Safety and legal boundaries

The test path should use homebrew that we build ourselves and software / firmware data the developer is authorized to inspect. Do not bundle Nintendo firmware, keys, game dumps, or copyrighted game content in this repository. Users must supply any legally obtained files themselves.

## Immediate next engineering task

Create a Switch 2 homebrew survey harness and a structured report format before implementing NVN2. This avoids building a large, speculative compatibility layer against unmeasured APIs.
