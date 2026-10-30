# Switch 2 iOS Metal bring-up app

This is a standalone iOS/iPadOS diagnostic app. It does **not** emulate Switch 2 and does not load Nintendo software. Its purpose is to establish a reproducible Apple-device baseline before any Switch 2 guest runtime or NVN2 translation code is attempted.

## What it verifies

- The app can create the system Metal device.
- It can create a Metal command queue.
- It executes signed-in-app AArch64 PACIA/AUTIA and BTI instructions and reports whether a pointer-authentication round trip changes and restores a sample value. This is a host CPU capability smoke test only; it does not prove Switch 2 PAC key/ABI compatibility.
- It remaps a dedicated signed `__TEXT` code page, requests `VM_PROT_EXECUTE` without `VM_PROT_READ`, executes a tiny function from that alias, and reports whether the complete XOM path succeeds. This directly tests the iOS signed-page strategy; it does not yet prove the full guest loader can enforce XOM for every module layout.
- It can acquire an MTKView drawable, encode a clear-only render pass, and present it.
- It records the Metal device name, unified-memory status, maximum buffer length, recommended working-set size, and completed frame count.

## Build

On a Mac with Xcode and XcodeGen installed:

```sh
cd dm/tests/switch2/ios
xcodegen generate
open Switch2Bringup.xcodeproj
```

Select an iPad Air (M3) or iPhone 17 Pro Max destination and build/run. A successful run should show a dark blue render surface and an increasing frame count.

For a command-line build:

```sh
xcodebuild -project Switch2Bringup.xcodeproj -scheme Switch2Bringup -destination 'generic/platform=iOS' -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

## Evidence to attach to the next milestone

For each device, record:

- device model and iOS/iPadOS version;
- Xcode version and build configuration;
- Metal device name and values shown in the dashboard;
- whether the frame count increases continuously;
- app log / crash report if device creation or presentation fails.

Do not infer Switch 2 API support from this test. It only validates the Apple Metal execution and presentation foundation.

## Homebrew payload inspection

The app can import a self-built `.nro`, `.nso`, or little-endian ELF64 file through the iOS Files picker. It reports the recognized container, architecture, version/build ID where present, and bounded loadable segment metadata. It never executes imported bytes.

The NRO/NSO readers describe original Switch container formats. Their presence is for diagnostic comparison only; they are not claimed to be Switch 2 executable formats. A recognized ELF64 file is not automatically a Switch 2 title or compatible homebrew payload.

The parser has synthetic tests for NRO0, NSO0, ELF64, malformed ranges, and unknown input. CI runs these tests before the iOS app build.
