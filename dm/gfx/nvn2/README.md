# Switch 2 graphics-to-Metal backend (experimental)

This directory is the Switch 2 graphics compatibility boundary for the native ARM64 runtime. Guest CPU code should execute natively where permitted; NVIDIA GPU commands and shaders require a separate translation implementation. It is intentionally separate from `../nvn/`, which implements the original Switch NVN interface and its Tegra X1 / Maxwell assumptions.

**Current status: no Switch 2 graphics implementation yet.** The repository currently has an Apple Metal smoke-test app, a bounded HIPC/CMIF host boundary, and static NSO survey tooling. None of those supplies the NVN2 ABI, command stream, object layouts, shader container, or synchronization semantics. Do not label the existing clear-only Metal view as NVN2 support.

## Evidence gate before coding NVN2

Use a self-built Switch 2 homebrew test program and record:

1. SDK/API version and exported/imported NVN2 symbols.
2. Actual call order from device initialization through queue creation and first presentation.
3. Argument widths, enum values, opaque handle relationships, and return/error values. Do not dereference or publish pointer contents; record opaque pointer identity only where needed to correlate lifetimes.
4. Device/queue limits and feature queries, with the source of each value.
5. Resource creation/destruction order, memory sizes, formats, alignment, and synchronization points.
6. Shader container metadata and hashes first; do not assume the Switch 1 Maxwell shader format applies.

The optional `graphicsTrace` field in `dm/tests/switch2/survey/report.schema.json` stores an ordered, evidence-linked trace. Each call must cite its source and classify the phase. Keep observations marked as inferred or unknown until directly supported.

## Backend boundaries

Keep three layers separate:

- **Guest-facing NVN2 ABI:** exact exported symbols, calling conventions, argument layouts, enums, and opaque guest handles. This layer must be derived from observed Switch 2 evidence, not copied from Switch 1 NVN headers.
- **Backend-neutral command/resource model:** validated device, queue, command-buffer, resource, synchronization, and presentation operations. It must preserve guest-visible ordering and error behaviour.
- **Apple Metal implementation:** maps the validated model to public Metal APIs available on iOS/iPadOS. Query capabilities at runtime; never assume a Mac-only feature or a particular GPU family. Use conservative fallbacks where possible.

Do not expose raw guest pointers directly to Metal or trust guest-provided sizes. Validate all ranges and lifetimes at the guest boundary.

## Implementation sequence

1. **Device discovery:** reproduce the observed device/version queries and limits; return only measured or deliberately unsupported results.
2. **Queue lifecycle:** model create/destroy, command-buffer allocation, submission ordering, and error paths.
3. **Presentation:** connect a validated guest surface/swapchain contract to an iOS drawable and present a clear-only frame.
4. **Synchronization:** implement observed fence/event semantics and prove ordering across queue submissions.
5. **Memory/resources:** add buffers, textures, format mapping, alignment, upload/readback, and barriers one capability at a time.
6. **Shaders:** identify the actual Switch 2 shader representation and instruction set before writing a translator. Keep shader parsing and translation separate from the Switch 1 Maxwell path.
7. **Draw validation:** one indexed triangle, then a textured quad, with deterministic captures and correctness checks.

Each stage needs host unit tests plus an evidence-linked homebrew trace. Physical M3 iPad Air and A19 Pro iPhone 17 Pro Max testing remains necessary before claiming device compatibility or sustained performance.

## Performance and compatibility (phase 4)

Do not optimize an unverified renderer. Once correctness exists, measure CPU submission, GPU execution, memory residency, synchronization stalls, frame pacing, and thermal behaviour separately. Use per-device runtime budgets and dynamic resolution rather than hard-coded RAM/GPU assumptions. Establish a stable baseline first; do not promise 60 fps before repeatable measurements on both target devices.

## Explicit non-goals and unsupported claims

- The Switch 1 NVN backend is not an NVN2 implementation.
- A Metal device/command queue or clear-only frame is not evidence of NVN2 translation.
- The original Switch NRO/NSO container readers are diagnostic comparison tools; they do not establish a Switch 2 retail executable format.
- The HIPC parser is a bounded host-side parser; it is not full Horizon, kernel-handle, service-manager, TIPC, or domain-object support.
- No retail Switch 2 title is currently known to boot in this repository.

See [the native ARM64 runtime architecture](../../../docs/switch2-native-arm64-runtime.md) and [the M3 bring-up plan](../../../docs/switch2-m3-port-plan.md).
