# Switch 2 homebrew survey format

This directory defines the evidence format used before implementing Switch 2 loader, Horizon, or NVN2 compatibility.

- `report.schema.json` is the JSON Schema for a survey report.
- Record only behaviour observed from a self-built homebrew test program or documented SDK material the developer is authorized to inspect.
- Every module and observation must carry evidence. Mark unconfirmed details as `inferred` or `unknown`; do not turn guesses into ABI definitions.
- Keep firmware, keys, commercial game data, and copyrighted system components out of this repository.

A report should cover module format and architecture, loader metadata, imports, SVC observations, IPC requests, memory behaviour, NVN2 version/device queries, queue lifecycle, shader metadata, and first presentation. The schema intentionally does not prescribe NVN2 signatures or object layouts: those must come from measured evidence.

Validate a report with any JSON Schema Draft 2020-12 validator against `report.schema.json`.
