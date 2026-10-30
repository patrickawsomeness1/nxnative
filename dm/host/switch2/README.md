# Switch 2 host compatibility (experimental)

This directory is reserved for Switch 2-specific loader and Horizon compatibility work. Existing generic host code may be reused only after its ABI and behavioural assumptions are checked against Switch 2 homebrew observations.

**Current status: no Switch 2 runtime implementation yet.**

Before adding code, collect a reproducible survey of:

- module format, loader metadata, relocations, and imported symbols;
- SDK / OS version information and required SVCs;
- service-manager and IPC requests during startup;
- memory mapping, thread, synchronization, and filesystem behaviour.

Keep Switch 1 behaviour unchanged. Switch 2 differences must be explicit, testable, and selected by a distinct runtime profile; do not silently change the Switch 1 host.

Use self-built homebrew as the first test target. Do not commit firmware, keys, commercial game files, or copyrighted system components.

See [the M3 bring-up plan](../../../docs/switch2-m3-port-plan.md).
