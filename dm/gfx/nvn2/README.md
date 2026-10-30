# Switch 2 graphics-to-Metal backend (experimental)

This directory is reserved for the Switch 2 graphics compatibility boundary in the native ARM64 runtime. Guest CPU code should execute natively where permitted; NVIDIA GPU commands and shaders still require a separate translation/compatibility implementation. It is intentionally separate from `../nvn/`, which implements the original Switch NVN interface and its Tegra X1 / Maxwell assumptions.

**Current status: no Switch 2 graphics implementation yet.** See [native ARM64 runtime architecture](../../../docs/switch2-native-arm64-runtime.md). Do not add guessed prototypes, copied NVN object layouts, or assumed shader formats here.

## Implementation order

1. Survey NVN2 symbols and version queries from a self-built Switch 2 homebrew test.
2. Record observed ABI signatures, object sizes, initialization order, and queue lifecycle in checked-in test fixtures.
3. Implement device creation and capability queries.
4. Implement queue / command-buffer lifecycle and a clear-only Metal present.
5. Add synchronization, buffers, textures, resource barriers, shader loading, and draw commands incrementally.
6. Add unit tests and M3 iPad Air and A19 Pro iPhone 17 Pro Max device smoke tests on both target devices for each milestone.

The Metal backend must use runtime feature checks and provide a conservative path for iPadOS. Do not assume Mac-only Metal features or memory budgets.

See [the M3 bring-up plan](../../../docs/switch2-m3-port-plan.md) for the complete milestone and evidence checklist.
