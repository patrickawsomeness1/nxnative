# Xcode iOS launch settings

The iOS app lives in `dm/ios/` and is generated for Xcode by `dm/ios/project.yml` using XcodeGen. This is the real app shell used by the native-execution host, not a standalone mockup.

## What this change adds

- `Sources/DmLaunchScreen.m`: UIKit menu shown before the game starts.
- `Sources/front_ios.m`: switches from the launcher to the Metal game view, with an optional host output resolution.
- `Sources/main.m`: defers native host preload until after the settings are chosen.
- Saved Performance / Balanced / Quality choices:
  - **Performance:** handheld operation, 1280×720 docked baseline, 1024×576 handheld output.
  - **Balanced:** handheld operation, 1600×900 docked baseline, 1280×720 handheld output.
  - **Quality:** docked operation, 1600×900 output.

The menu sets `DM_OPMODE` and `DM_GAME_RES` before host loading. Whether an individual game honors those output-resolution hints must be confirmed with on-device testing. These are render-target/output resolution presets, **not** a real-time adaptive-resolution system.

**Unimplemented and visibly marked as such:** MetalFX spatial/temporal scaling, frame interpolation (frame generation), graphics-pack loading, game-specific frame-rate unlocking, and outdoor 60 FPS optimizations. Those require separate renderer and game changes. Do not label them as enabled.

## Open in Xcode

1. On a Mac install **Xcode**, **XcodeGen**, and the additional dependencies listed in the root README.
2. Clone this repository and check out `feature/ios-prelaunch-graphics-menu` (or merge its pull request).
3. Use your own extracted game assets and an **existing supported game profile** to run the complete `scripts/build_ipa_from_nsp.py` pipeline. The build generates `dm/ios/Gen/` and `dm/ios/DmIOS.xcodeproj`.
4. Open `dm/ios/DmIOS.xcodeproj` in Xcode. The menu's Objective-C source files appear in the `Sources` group.
5. Select your signing team and target iPhone if building/installing from Xcode; the standard packaging script builds an **unsigned** IPA to sign later.

The full pipeline needs the rewritten code modules, generated shader libraries, game profile, and RomFS. Simply opening the template project does not create a playable game.

## Tears of the Kingdom status

At the time of this change, `nxnative` does **not** contain a validated *Tears of the Kingdom* game profile. The separate `totk-ios` repository only contains a short README; no playable IPA or its original build sources were available in the connected repositories.

To target Tears of the Kingdom, integrate the user's actual IPA build sources and establish a verified TOTK profile first. Measure real frame time in representative outdoor scenes (for example, traversal, towns, rain, and dense vegetation) before attempting a 60 FPS timing patch. A 60 FPS menu preference or frame interpolation alone does not unlock 60 simulation updates per second.

## Safeguards

- No game binary, ROM, keys, or proprietary graphics packs are committed to this repository.
- The launcher deliberately does not apply patches for unsupported games.
- Test first using a backed-up save and record `Documents/log.txt` if boot fails.
