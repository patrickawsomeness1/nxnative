# Switch 2 native module survey

`switch2_survey.py` is a read-only offline analysis tool for authorized Switch 2 NSO modules. It uses the shared, bounds-checked `nso.py` reader, which validates segment bounds and enabled SHA-256 hashes and supports Nintendo's ZBIC-compressed NSO segments when the optional `zbic` Python package is installed.

Switch 2's NSO0 header documents flag bit 6 as execute-only memory (XOM) and bit 7 as ZBIC compression (Nintendo's zstd-based format). Switch 2 security research also reports PAC on game return addresses and, in newer SDKs, PAC-related pointer discrimination; XOM may be enabled on newer game main modules. These differences are why the Switch 1 rewriter cannot simply be declared Switch 2-compatible.

It reports:
- NSO flags, including per-segment compression/hash flags, execute-only text (XOM), and ZBIC compression;
- segment offsets/sizes and module ID;
- NSO dynamic symbols and undefined imports;
- MOD0 dynamic tags plus RELA, PLT/JMPREL, RELR, and authenticated RELR relocation tables, including PAuth relocation IDs and a list of types the current loader cannot safely apply;
- static AArch64 instruction counts and samples for PAC/authentication, authenticated branches, BTI, SVCs, LSE atomics, and selected system-register accesses (`CTR_EL0`, timer registers, and thread-pointer registers).

## Run

From the repository root on a Mac:

```sh
python3 -m pip install 'capstone>=5,<6' lz4
# Only required when the module has ZBIC-compressed segments:
python3 -m pip install zbic
python3 dm/tools/switch2_survey.py /path/to/authorized/main -o main.switch2-survey.json
```

This is a survey, not a loader or execution test. Static disassembly can encounter embedded data and cannot establish runtime service calls, SVC semantics, PAC key behaviour, or graphics API usage. Keep Switch 2 observations separate from original Switch profiles until verified.

The current Switch 1 rewriter is intentionally guarded: `DM_TARGET=switch2` makes it stop with an explicit unsupported-target error, and it refuses NSOs that request XOM. The native loader has dormant per-module XOM sealing support, but the signed-page XOM probe has not yet been run on a physical iPad/iPhone. The loader implements standard PAuth `AUTH_ABS64`, `AUTH_RELATIVE`, `AUTH_GLOB_DAT`, authenticated RELR, and PAC-PLT `JUMP_SLOT` signing. It rejects unimplemented `AUTH_TLSDESC`, `AUTH_IRELATIVE`, `DT_AARCH64_AUTH_SYM`, `DT_AARCH64_VARIANT_PCS`, and unknown relocation types rather than treating them as ordinary pointers. Do not remove these checks to force a build. Switch 2 support requires a separate, tested rewrite/loader profile with correct signing-schema handling.
