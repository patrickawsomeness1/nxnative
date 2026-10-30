# Switch 2 native ARM64 host compatibility (experimental)

This directory is reserved for a native ARM64 guest execution runtime plus Switch 2-specific loader and Horizon compatibility work for both iPadOS (M3 iPad Air) and iOS (A19 Pro iPhone 17 Pro Max). Existing generic host code may be reused only after its ABI and behavioural assumptions are checked against Switch 2 homebrew observations.

**Current status: no Switch 2 guest execution implementation yet.** The product target is direct execution of compatible guest AArch64 code on Apple ARM64, not a CPU interpreter as the default. iOS executable-page/code-signing restrictions are a blocking feasibility gate for imported binaries; see [native ARM64 runtime architecture](../../../docs/switch2-native-arm64-runtime.md).

Before adding code, collect a reproducible survey of:

- module format, loader metadata, relocations, and imported symbols;
- SDK / OS version information and required SVCs;
- service-manager and IPC requests during startup;
- memory mapping, thread, synchronization, and filesystem behaviour.

Keep Switch 1 behaviour unchanged. Switch 2 differences must be explicit, testable, and selected by a distinct runtime profile; do not silently change the Switch 1 host.

Use self-built homebrew as the first test target. Do not commit firmware, keys, commercial game files, or copyrighted system components.

See [the M3 bring-up plan](../../../docs/switch2-m3-port-plan.md).
