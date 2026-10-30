# Switch 2 console-side homebrew probe

This package is built against the public [HBLauncher](https://github.com/ravensclawx/HBLauncher) Native SDK (MIT), pinned in CI to commit `18b4748ba98eeac7df17beb5d3418985eb74897c`.

It is deliberately a small console-side diagnostic app, not a Switch 2 emulator component. It checks:

- HBLauncher SDK ABI v3 context validation;
- allocation, write, readback verification, and free of a 64 KiB heap block;
- whether the launcher supplied Vulkan instance, physical device, device, queue and swapchain handles;
- the provided swapchain dimensions, image count and queue family;
- whether the shared 2D Vulkan renderer can present frames;
- elapsed time, frame count and input polling.

## Important scope boundary

HBLauncher is a separate userland homebrew environment which requires its own supported console setup and a live external session. Its Vulkan display is not the Switch 2 retail NVN2 interface. A passing run measures this test environment only; it does not prove that a commercial Switch 2 title can be loaded or that NVN2 has been implemented.

The package does not contain firmware, keys, game data, or exploit code. The probe does not access or modify system files or game saves.

## Build

The repository's GitHub Actions workflow checks out the pinned HBLauncher SDK, installs the AArch64 cross compiler, builds this package, and uploads `code.bin`, `data.bin`, and `report.json` as an artifact. The resulting package is intended for the HBLauncher host's app catalog, not for the Switch HOME menu and not as an NRO.
