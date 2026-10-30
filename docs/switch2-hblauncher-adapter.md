# HBLauncher-to-nxnative adapter findings

Status: ABI and image-format analysis complete; no direct loader integration yet. The pinned HBLauncher Native SDK is a useful Switch 2 userland CPU probe and a source of a self-authored test payload. Its package format is not an NSO and cannot be passed to nxnative's existing load_modules() path.

## Verified HBLauncher image contract

Source pinned in CI: ravensclawx/HBLauncher@18b4748ba98eeac7df17beb5d3418985eb74897c.

- ABI version: 3; generated sdk/abi.json reports ctxSize: 696.
- The authoritative C header sdk/include/hbx_sdk.h statically asserts sizeof(struct hbx_ctx) == 0x2b8 (696 bytes), gpu == 0xc8, input == 0x1c8, args == 0x208, and audio == 0x250. The prose in docs/ARCHITECTURE.md saying 592 bytes is stale; use the header and generated ABI JSON.
- The builder emits two fixed-address images: code.bin (RX) and data.bin (RW, with a zero-filled BSS tail). Its actual CLI defaults are code base 0x0c000000 and data base 0x0d000000; the introductory comment in hbx-build.py still mentions older addresses.
- The ELF entry is _start, at the selected code base. sdk/src/crt0.S accepts a context pointer in x0, has a bti jc landing pad, saves/restores caller frame/link registers, selects the supplied stack only if it is nonzero, 16-byte aligned and at least 4096 bytes, then calls hbx_app_main(ctx).
- The build uses -ffreestanding -nostdlib -fno-pic -fno-pie -mcmodel=large and extracts flat code/data sections. It is intentionally a fixed-address, non-PIE image, not a relocatable ELF/NSO.
- SDK services are not neutral platform calls. For example, hbx_tick() issues Horizon svc #0x1e; the SDK sleep helper issues svc #0x0b. Logging, heap, input, GPU and audio depend on the HBLauncher context/host contract.

## Why direct reuse in nxnative is not valid

nxnative's current module loader consumes its own rewritten NSO output plus fixup metadata. It expects MOD0/dynamic metadata, parses symbol/relocation tables, applies AArch64 relocations, registers SVC/timer gates, and on iOS remaps signed Mach-O __TEXT pages into a guest image range. The HBLauncher package instead has fixed virtual addresses, flat code/data binaries, no MOD0 or dynamic symbol table, a different entry ABI, and service calls defined by HBLauncher.

Therefore:
1. Do not rename code.bin to .patched.bin or feed it to load_modules().
2. Do not assume HBLauncher SVC numbers are interchangeable with the Switch 2 retail Horizon SVC ABI.
3. Do not interpret a successful HBLauncher package build as a successful nxnative guest execution.
4. Keep the HBLauncher console probe as a console-side CPU/ABI test, not as the iOS runtime's loader format.

## Adapter path

1. Keep the pinned HBLauncher package build as the independently reproducible console-side probe.
2. Build a separate nxnative-native CPU probe against a deliberately small nxnative test ABI: entry context, bounded stack, timer callback, log callback, and host-owned heap. It must not call HBLauncher SVC helpers.
3. Add a dedicated fixed-image package parser/validator for the HBLauncher artifact only if we need to inspect or run that exact package. Validate the report's ABI, bases, sizes, hashes, entry, and all image ranges before mapping.
4. For actual iOS execution, use the existing signed-page embedding principle, but add a separate loader path that either reserves the required fixed code/data addresses or rebuilds a relocatable payload. The current generic NSO loader is not that path.
5. Once the nxnative CPU probe runs on iOS, separately add verified Switch 2 Horizon SVC/IPC compatibility from console traces. Only then proceed to a Switch 2 NSO entry test.

## Evidence boundary

The pinned package currently compiles in GitHub Actions. The build does not run on a Switch 2 console, does not run through nxnative, and does not validate retail sm:, HIPC, NVN2, or game compatibility. A physical console-side run is still required to establish the HBLauncher probe's runtime observations.
