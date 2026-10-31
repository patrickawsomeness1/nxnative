# nxnative Switch 2 HBLauncher CPU probe

This package is built against the public [HBLauncher Native SDK](https://github.com/ravensclawx/HBLauncher), pinned in CI to commit `18b4748ba98eeac7df17beb5d3418985eb74897c` (MIT). It is a small, self-authored diagnostic app, not a copy of a commercial title.

## What it checks

The host may select a maximum stage through `ctx->args[1]` (1–9); zero runs the complete probe. Stage 9 is experimental and may fail on a stock or unsupported Horizon environment. The app writes the last completed stage to `ctx->args[2]` and the marker `NXP2` to `ctx->frame`.

| Stage | Operation |
| ---: | --- |
| 0 | Native entry, HBLauncher ABI validation, context writeback |
| 1 | Loader-provided stack pointer is nonzero and 16-byte aligned |
| 2 | SDK `hbx_tick()` (GetSystemTick, SVC `0x1e`), `hbx_sleep_ns(1 ms)` (SleepThread, SVC `0x0b`), then another tick read; writes `ctx->tick_hz`, starting tick, and elapsed ticks to `ctx->args[3..5] |
| 3 | SDK log-ring write |
| 4 | 64 KiB heap allocation, deterministic write/readback, free |
| 5 | Formatted logging |
| 6 | PACIA/PACIB/PACDA/PACDB sign/auth round trips |
| 7 | PAC-authenticated `BRAA` into a `BTI j` landing pad |
| 8 | LSE `LDADDAL` atomic read/modify/write |
| 9 | Experimental `sm:RegisterClient` request: connect to `sm:`, construct a CMIF v0 request in the thread-local HIPC buffer, send it synchronously, validate the response framing, and close the session handle |

The app is built as a freestanding AArch64 image with BTI enabled by the upstream SDK toolchain. Read `ctx->args[3..5]` after stage 2 to compare the SDK-provided tick frequency with the elapsed ticks across the 1 ms sleep. The HBLauncher SDK documents `CNTFRQ_EL0` as not readable at this privilege level, so the probe deliberately does not execute that potentially trapped register read. See [the pinned SDK timer implementation](https://github.com/ravensclawx/HBLauncher/blob/18b4748ba98eeac7df17beb5d3418985eb74897c/sdk/src/hbx_app.c). It intentionally does not initialise Vulkan or issue NVN2 calls. Stage 9 is a deliberately isolated service-manager experiment: the `ConnectToNamedPort`, `SendSyncRequest`, and `CloseHandle` SVC numbers are reference ABI candidates (respectively `0x1f`, `0x21`, and `0x16`) and have **not** been confirmed for native Switch 2 by a console trace. The `sm:RegisterClient` command ID and CMIF v0 framing are likewise hypotheses being tested, not a supported service implementation. A failed stage 9 is diagnostic, not evidence that earlier CPU stages failed. Stages 6–8 execute PAC, authenticated-branch/BTI, and LSE instructions on the Switch 2 CPU only when the package is run on-console; a successful CI cross-build alone does not verify those runtime results.

## Build

CI clones HBLauncher at the pinned revision, copies this package into its SDK app tree, and runs:

```sh
python3 sdk/tools/hbx-build.py apps/nxnative-probe --out build/nxnative-probe
```

The resulting `code.bin`, `data.bin`, and `report.json` are uploaded as the `nxnative-switch2-hblauncher-probe` artifact.

## Evidence limits

A successful cross-build proves only that the package compiles and links against the pinned HBLauncher ABI. Stage 9 being present in the binary does not establish that its candidate SVC numbers, TLS layout, HIPC header, CMIF framing, or `sm:RegisterClient` request are correct on Switch 2. Only a recorded console run with the returned stage/result values can provide evidence, and even that would validate this narrow homebrew path—not retail NSO loading, general kernel-handle transport, complete Horizon service-manager behaviour, NVN2, or retail game execution. Keep those as separate milestones.
