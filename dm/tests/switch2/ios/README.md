# Switch 2 iOS Metal bring-up app

This is a standalone iOS/iPadOS diagnostic app. It does **not** emulate Switch 2 and does not load Nintendo software. Its purpose is to establish a reproducible Apple-device baseline before any Switch 2 guest runtime or NVN2 translation code is attempted.

## What it verifies

- The app can create the system Metal device.
- It can create a Metal command queue.
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
