# Switch 2 native ARM64 host compatibility (experimental)

This directory is the isolated Switch 2 runtime profile for iPadOS (M3 iPad Air) and iOS (A19 Pro iPhone 17 Pro Max). The target is direct execution of compatible guest AArch64 code, not a CPU interpreter as the default.

## First implementation: Horizon service boundary

- `horizon.h/.c` provides a small, bounded service registry and command-dispatch boundary.
- Services are registered explicitly by name; duplicate names, unknown services, invalid buffers, and capacity exhaustion fail closed.
- The router deliberately does **not** fabricate Nintendo `nn::Result` values.
- The current tests use a synthetic echo service. They prove host-side routing and framing mechanics only, not Horizon compatibility or game boot.

## CMIF framing foundation

- `nx_horizon_cmif_dispatch()` validates the 16-byte CMIF request header (`SFCI`, version, command ID, token), dispatches the command payload, and emits an `SFCO` response header on success.
- The response preserves the request token and writes a success result only when the handler succeeds. Host-side failures are returned separately; no unverified Nintendo result mapping is guessed.
- CMIF framing is now carried inside a bounded HIPC request parser. HIPC descriptor ranges are validated and exposed as bytes only; guest addresses are never dereferenced.
- The session adapter currently round-trips only descriptor-free CMIF requests. It rejects PID transfer, copied/moved handles, buffer descriptors, receive statics, TIPC/domain requests, and unsupported command types. It does not implement kernel handle translation or `sm:` semantics. Tests use synthetic messages, not captured Switch 2 traffic.

## Session lifecycle foundation

- Host-internal session handles can be opened against registered services, used for CMIF dispatch, and closed.
- These handles are not Horizon kernel handles. Real HIPC copy/move handle descriptors and actual `sm:` command semantics still require validation against a Switch 2 target.
- Tests cover opening, dispatching through, closing, and rejecting a closed session.

## Next implementation sequence

1. Capture service-manager and IPC traffic from a self-built Switch 2 homebrew test program.
2. Implement the observed CMIF request/response framing and service-manager session lifecycle.
3. Add narrowly scoped service implementations (starting with `sm:`, `set:`, `time:`, and `fs:` only as observations justify them).
4. Connect the Horizon SVC boundary to the native ARM64 guest gate after Switch 2 SVC numbers and ABI are verified.
5. Build NVN2 command/resource translation to Metal once a real homebrew graphics trace exists.

Existing Switch 1 `hle_*.c` handlers are not automatically Switch 2 compatible. Reuse requires an ABI and behavior check. Keep the Switch 1 host unchanged.

Use self-built homebrew as the first target. Do not commit firmware, keys, commercial game files, or copyrighted system components.

**Status:** bounded HIPC parsing and descriptor-free HIPC→CMIF session round-trip are implemented and CI-tested. No Switch 2 service implementation, kernel-handle transport, Horizon SVC implementation, retail guest launch, or NVN2 renderer is complete yet.
See [the M3 bring-up plan](../../../docs/switch2-m3-port-plan.md).

## HIPC transport boundary

`hipc.c/.h` now parses the HIPC request header, optional special header/PID, copy/move handles, send/receive/exchange buffer descriptors, data words, and receive-static list with strict bounds checks. It locates 16-byte-aligned CMIF v0/v1 payloads. `nx_horizon_session_hipc_dispatch` can round-trip simple descriptor-free CMIF requests through an internal session and build a HIPC response. It deliberately rejects descriptor-bearing requests for now; it does not yet implement `svcConnectToNamedPort`, kernel handle translation, domain objects, pointer-buffer mapping, or a complete `sm:` service manager. The boundary test job compiles with AddressSanitizer and UndefinedBehaviorSanitizer and runs 20,000 deterministic malformed HIPC messages without a sanitizer finding.

## Verified SDK syscall overlap

The pinned HBLauncher Native SDK calls `SVC 0x1e` for `GetSystemTick` and `SVC 0x0b` for `SleepThread`. nxnative's current HLE already dispatches these through `hle_svc.c` and `hle_thread.c`. The console-side probe exercises both and reports the SDK-provided tick frequency and measured elapsed ticks. This confirms an ABI overlap in the SDK source, not yet a successful Switch 2 runtime test; the native console frequency must be measured on hardware.
