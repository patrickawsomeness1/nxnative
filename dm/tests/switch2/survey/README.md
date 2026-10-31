# Switch 2 homebrew survey format

This directory defines the evidence format used before implementing Switch 2 loader, Horizon, or NVN2 compatibility.

- `report.schema.json` is the JSON Schema Draft 2020-12 definition for a survey report.
- Record only behaviour observed from a self-built Switch 2 homebrew test program or documented SDK material the developer is authorized to inspect.
- Every module and observation must carry evidence. Mark unconfirmed details as `inferred` or `unknown`; do not turn guesses into ABI definitions.
- Keep firmware, keys, commercial game data, and copyrighted system components out of this repository.

A report should cover module format and architecture, loader metadata, imports, SVC observations, IPC requests, memory behaviour, NVN2 version/device queries, queue lifecycle, shader metadata, and first presentation.

## Ordered graphics trace

The optional `graphicsTrace` array records NVN2 calls in observed order. Each entry identifies the symbol, lifecycle phase, argument index and coarse type, optional result, and evidence source. Use opaque pointer/handle labels only to correlate object lifetimes; do not serialize process addresses or pointer contents.

The schema intentionally does not prescribe NVN2 signatures, enum meanings, object sizes, or shader formats. Those must come from measured evidence. A trace containing inferred details must remain marked as a draft and must not be used as an ABI implementation contract.

Validate a report with any JSON Schema Draft 2020-12 validator against `report.schema.json`.
