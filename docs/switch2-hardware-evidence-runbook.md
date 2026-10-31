# Switch 2 hardware evidence runbook

This runbook closes the gap between a green cross-build and evidence from real hardware. It does not claim to make retail Switch 2 titles boot. It defines the minimum reproducible evidence needed before implementing more Horizon or NVN2 compatibility.

## 1. Establish a clean baseline

Record the exact Git commit and CI artifact names used. Do not mix artifacts from different workflow runs.

- Switch 2 console probe: `nxnative-switch2-hblauncher-probe` (contains `code.bin`, `data.bin`, and `report.json`).
- Apple-device diagnostic: `Switch2Bringup-unsigned-IPA`.

The console probe is a self-authored HBLauncher Native SDK app, not a retail NSO. The iOS IPA is unsigned and must be signed with the device owner's Apple development identity before installation. Do not commit provisioning profiles, certificates, private keys, device identifiers, or personal logs to the repository.

## 2. Switch 2 console run

Use a Switch 2 that is already able to run the selected HBLauncher homebrew path. Do not use a commercial game as the test case.

1. Launch the exact probe artifact built from the recorded commit.
2. First run with maximum stage **8**. The probe README documents stages 0–8 as the CPU/ABI baseline. This deliberately excludes stage 9, which contains unconfirmed service-manager SVC/TLS/CMIF assumptions.
3. Capture the complete HBLauncher log and the final context values:
   - `ctx->args[2]`: last completed stage;
   - `ctx->args[3]`: SDK-reported tick frequency;
   - `ctx->args[4]`: starting tick;
   - `ctx->args[5]`: elapsed ticks across the 1 ms sleep;
   - `ctx->frame`: expected `NXP2` marker.
4. Record whether each stage passed, failed, timed out, or crashed. Preserve the first failing stage and the raw error/result value; do not convert an unexplained failure into a guessed ABI rule.
5. Only after stages 0–8 have been captured, run a separate opt-in test with maximum stage **9**. Treat stage 9 as experimental. A failure or hang in stage 9 must not erase the baseline result.
6. Record console model/revision, system version, HBLauncher version, probe commit, artifact/run ID, date, and whether the test was cold-started.

A CI cross-build is not a console run. If the app cannot be launched, report that as an environment/launcher blocker and retain the build evidence separately.

## 3. Apple-device diagnostic run

Install the signed diagnostic IPA on each target independently.

For each device, record:

- exact device model and iOS/iPadOS version;
- Xcode version and signing/build configuration;
- Metal device name, unified-memory flag, maximum buffer length, and recommended working-set size;
- PAC IA/IB/DA/DB round-trip results;
- authenticated BRAA/BTI result;
- LSE LDADDAL result;
- signed `__TEXT` remap/XOM result;
- whether the clear-only Metal frame count continues increasing;
- crash log or console output if any test fails.

Run once after a fresh install and once after a device restart. Do not infer Switch 2 compatibility from an Apple CPU/Metal smoke test: these measurements validate the Apple host only.

## 4. Evidence record template

Copy and fill this record for each device/run. Keep unknown fields as `null`; never fill them with estimates.

```json
{
  "schemaVersion": 1,
  "runType": "switch2-console-or-apple-device",
  "gitCommit": null,
  "workflowRunId": null,
  "artifactName": null,
  "artifactSha256": null,
  "dateUtc": null,
  "hardware": {
    "model": null,
    "systemVersion": null
  },
  "software": {
    "launcherOrXcodeVersion": null,
    "probeVersion": null
  },
  "results": [
    {
      "stageOrCheck": null,
      "status": "not-run",
      "rawValue": null,
      "notes": null
    }
  ],
  "rawLogFile": null
}
```

For a console run, include one result per probe stage and preserve the raw context values above. For an Apple run, include one result per diagnostic check. Keep raw logs local until sensitive identifiers and personal data have been removed.

## 5. What this evidence unlocks

- Passing console stages 0–8 establishes only the tested HBLauncher userland ABI and CPU instructions on that console.
- A passing stage 9 would establish only the exact named-port/CMIF experiment exercised; it would not establish general Horizon service-manager compatibility.
- Passing Apple PAC/LSE/XOM/Metal checks establishes only the host-device capabilities exercised by the diagnostic app.
- Retail NSO loading, retail Horizon SVC/handle semantics, NVN2, shader translation, and game compatibility remain separate milestones requiring their own evidence.

## 6. Stop conditions

Stop and preserve logs if the probe crashes, hangs, returns an unexpected stage marker, or reports inconsistent tick data. Do not add guessed SVC numbers, TLS offsets, service command IDs, NVN2 signatures, or object layouts to the runtime to make a test appear to pass. Update the implementation only when a reproducible observation or authoritative SDK contract supports it.
