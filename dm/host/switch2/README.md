# Switch 2 native ARM64 host compatibility (experimental)

This directory is the isolated Switch 2 runtime profile for iPadOS (M3 iPad Air) and iOS (A19 Pro iPhone 17 Pro Max). The target is direct execution of compatible guest AArch64 code, not a CPU interpreter as the default.

## First implementation: Horizon service boundary

- `horizon.h/.c` provides a small, bounded service registry and command-dispatch boundary.
- Services are registered explicitly by name; duplicate names, unknown services, invalid buffers, and capacity exhaustion fail closed.
- The router deliberately does **not** fabricate Nintendo `nn::Result` values or pretend to implement CMIF/SFCO wire framing.
- The current test uses a synthetic echo service. It proves only registry/dispatch behavior, not Horizon compatibility or game boot.

## Next implementation sequence

1. Capture service-manager and IPC traffic from a self-built Switch 2 homebrew test program.
2. Implement the observed CMIF request/response framing and service-manager session lifecycle.
3. Add narrowly scoped service implementations (starting with `sm:`, `set:`, `time:`, and `fs:` only as observations justify them).
4. Connect the Horizon SVC boundary to the native ARM64 guest gate after Switch 2 SVC numbers and ABI are verified.
5. Build NVN2 command/resource translation to Metal once a real homebrew graphics trace exists.

Existing Switch 1 `hle_*.c` handlers are not automatically Switch 2 compatible. Reuse requires an ABI and behavior check. Keep the Switch 1 host unchanged.

Use self-built homebrew as the first target. Do not commit firmware, keys, commercial game files, or copyrighted system components.

**Status:** service-router foundation implemented; no Switch 2 CMIF service, Horizon SVC implementation, guest launch, or NVN2 renderer is complete yet.
See [the M3 bring-up plan](../../../docs/switch2-m3-port-plan.md).
