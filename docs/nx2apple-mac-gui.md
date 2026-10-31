# NX2Apple macOS GUI

The first native macOS GUI is at `dm/tools/nx2apple-mac/`. It is a SwiftUI app generated with XcodeGen.

## Download the built app

The latest successful GUI build is GitHub Actions run [#41148534090](https://github.com/patrickawsomeness1/nxnative/actions/runs/41148534090), artifact **NX2Apple-macOS-GUI**. Download the artifact ZIP, extract it, and move `NX2Apple.app` to Applications. The CI artifact is unsigned/not notarized; on first launch, use Finder's Open action if Gatekeeper blocks it. Do not bypass macOS security prompts for builds from unknown sources.

## Use

1. Open NX2Apple.
2. Choose the local `nxnative` repository root.
3. Select a candidate homebrew/container file to see the current format support status.
4. Enter the Apple Developer Team ID used by Xcode.
5. Choose **Build signed diagnostic IPA**. Xcode must have a valid development signing account and provisioning setup.
6. Choose **Find devices**, copy the UDID for the paired iPhone/iPad, and enter it.
7. Choose **Install diagnostic app**.

The app installs the Switch2Bringup hardware diagnostic target from `dm/tests/switch2/ios`.

## Hard current limit

This is not yet a one-click Switch 2 game-to-IPA converter. Selecting a game file currently only displays its support assessment; it is not passed to a game loader. The current target is the diagnostic app, which exercises host Apple Metal/PAC/XOM/LSE capabilities. Retail package decryption, Switch 2 native module loading, complete Horizon kernel and service compatibility, and NVN2-to-Metal rendering are not complete. A playable title IPA cannot honestly be generated until those components are implemented and validated on hardware.

The app's macOS target has been built and packaged successfully by CI in run #41148534090. Physical Mac launch, Xcode signing, and iPhone/iPad installation still require the user's Mac, signing account, and connected device; those actions cannot be performed by the remote CI runner.
