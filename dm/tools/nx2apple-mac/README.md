# NX2Apple for macOS

A native SwiftUI front end for the nxnative Switch 2 bring-up workflow.

## Current capabilities

- Select an nxnative checkout.
- Select a candidate homebrew/container file and show the current support boundary.
- Generate the iOS Xcode project, archive the Metal/PAC/XOM diagnostic app, and export a development-signed IPA using the Mac's Xcode signing account.
- List paired iPhone/iPad devices with `xcrun devicectl`.
- Install the diagnostic app to a selected device by UDID.

## Build the Mac app

Requires macOS 14+, Xcode command-line tools, XcodeGen, and a locally cloned nxnative repository.

```sh
brew install xcodegen
cd dm/tools/nx2apple-mac
xcodegen generate
open NX2Apple.xcodeproj
```

Select the NX2Apple scheme and build. For signing and installation, the Mac must have an Apple development team configured in Xcode, the iPhone/iPad must be paired and trusted, and the app's provisioning profile must permit the target device.

## Important current limitation

This first GUI milestone builds and installs the **Switch2Bringup diagnostic app**, not a selected Switch 2 game. The existing Switch 1 NSO patcher explicitly refuses Switch 2 targets, and the Switch 2 native loader, retail/homebrew execution ABI, complete Horizon kernel/service transport, and NVN2-to-Metal renderer are not yet implemented. Selecting an .nso/.nro/.elf file only records it as a candidate; .nsp/.xci retail package decryption/content installation is not implemented. Do not interpret an IPA export as proof that a game can run.

The UI deliberately labels this boundary instead of producing a broken or misleading game IPA. Future milestones can replace the diagnostic build action with the verified native homebrew/game pipeline once the runtime exists.
