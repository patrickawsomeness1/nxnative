# NX2Apple for macOS

A native SwiftUI front end for the nxnative Switch 2 bring-up workflow.

## Current capabilities

- Select an nxnative checkout.
- Select a candidate file and identify common Switch package, content, metadata, filesystem, and executable extensions: NSP, XCI, NSZ, XCZ, NCA, NCZ, NRO, NSO, ELF, KIP/KIP1, NPDM, NACP, CNMT, RomFS, NAX, PFS0, HFS0, tickets, and certificates.
- Inspect file signatures for PFS0, HFS0, NSO0, NRO0, KIP1, ELF, XCI header, and visible NCA2/NCA3 headers where the header is not encrypted.
- Recognize common numbered NSP/XCI split-file parts by filename.
- Parse PFS0/HFS0 directory tables directly from memory-mapped files (avoiding a second full-size RAM copy) and display contained filenames/sizes in the GUI. This is metadata inspection only.\n- Bounds-check PFS0/HFS0 directory-table parsing in a dedicated Swift package, with tests for payload offsets, malformed ranges, path traversal, truncated headers, and unreasonable entry counts. This reads container metadata only; it does not decrypt or extract content.
- Import an HBLauncher Native ABI 3 package folder (`manifest.json` plus `build/code.bin`, `build/data.bin`, and `build/report.json`); verify package identity, ABI, byte counts, and SHA-256 hashes before accepting it. The checks live in a dedicated Swift package validator with regression tests for identity/ABI mismatches, tampered images, invalid hashes, unaligned or overflowing addresses, and overlapping code/data regions.
- Generate the iOS Xcode project, archive the Metal/PAC/XOM diagnostic app, and export a development-signed IPA using the Mac's Xcode signing account.
- List paired iPhone/iPad devices with `xcrun devicectl`.
- Install the diagnostic app to a selected device by UDID.

## Run the Swift validation tests

```sh
cd dm/tools/nx2apple-mac
swift test
```

The macOS GitHub Actions workflow runs these tests before building the GUI.

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

This first GUI milestone builds and installs the **Switch2Bringup diagnostic app**, not a selected Switch 2 game. The existing Switch 1 NSO patcher explicitly refuses Switch 2 targets, and the Switch 2 native loader, retail/homebrew execution ABI, complete Horizon kernel/service transport, and NVN2-to-Metal renderer are not yet implemented. Format recognition uses file signatures where available and extensions as a fallback; compressed formats and encrypted headers may only be identified by extension, so recognition is not proof that file contents are valid. Selecting NSP/XCI/NSZ/XCZ/NCA/NCZ or related content only identifies the container family. PFS0/HFS0 directory metadata can be inspected read-only; split-file assembly, decryption, content installation, and execution are not implemented. Selecting NRO/NSO/ELF/KIP only identifies a candidate; an HBLauncher ABI 3 folder can be integrity-checked, but it is not executed. The code/data images use fixed addresses and depend on the console launcher ABI, services, and graphics handoff; the Apple execution bridge is not implemented. The HBLauncher ABI 3 importer validates reported addresses, alignment, entry point, non-overlapping memory regions, byte counts, and SHA-256 hashes. NSP/XCI retail package decryption/content installation is not implemented. Do not interpret an IPA export as proof that a game can run.

The UI deliberately labels this boundary instead of producing a broken or misleading game IPA. Future milestones can replace the diagnostic build action with the verified native homebrew/game pipeline once the runtime exists.
