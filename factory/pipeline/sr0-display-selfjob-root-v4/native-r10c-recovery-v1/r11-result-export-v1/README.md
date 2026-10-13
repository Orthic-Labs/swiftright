# SR0 r11 result export

Bounded raw-result export for one completed r11 run. It does not qualify workload, derive metrics, alter receipts, or release lock. Exporter verifies explicit plan SHA, requires one run with 900-second deadline, one-second poll, `NoActivate`, `NoResources`, & `qualificationClaim=false`, then streams explicitly supplied receipts/runtime inputs into uncompressed ZIP.

Caps: 256 files, 8 MiB/file, 2 MiB/JSON, 32 MiB aggregate. Every entry gets byte count & SHA-256. Reparse inputs, duplicate paths, path escape, oversize files, existing outputs, & missing inputs fail. Include explicit `owner-status.json`, `collector-receipt.json`, `collector.stdout.bin`, `collector.stderr.bin`, `launcher-receipt.json`, launcher original stdout/stderr, coordinator verdict, start/finish receipts, & renderer/workload samples in `ReceiptPaths` as emitted by run; exporter does not invent absent files.

Root runs on Windows after r11 observer completes, with fresh output paths:

```powershell
& .\export-r11-results.ps1 `
  -RunRoot D:\Claude\swiftright\.factory-work\sr0-display-selfjob-v4\one-run-v7-r11 `
  -PlanPath D:\Claude\swiftright\.factory-work\sr0-display-selfjob-v4\one-run-v7-r11\one-run-plan-r11.json `
  -ExpectedPlanSha256 <plan-sha256> `
  -ReceiptPaths @(
    'owner-status.json',
    'collector-receipt.json',
    'collector.stdout.bin',
    'collector.stderr.bin',
    'launcher-receipt.json',
    'launcher.stdout.bin',
    'launcher.stderr.bin',
    'coordinator-verdict.json',
    'start-receipt.json',
    'renderer-samples.json',
    'workload-samples.json'
  ) `
  -RuntimeInputPaths @(
    'D:\Claude\swiftright\.factory-work\sr0-display-selfjob-v4\one-run-v7-r11\runtime-source-receipt.json'
  ) `
  -ArchivePath D:\Claude\swiftright\.factory-work\sr0-display-selfjob-v4\one-run-v7-r11\result-export-r11.zip `
  -ManifestPath D:\Claude\swiftright\.factory-work\sr0-display-selfjob-v4\one-run-v7-r11\result-export-r11.manifest.json
```

Adjust only explicit paths to actual emitted names; do not replace missing evidence with placeholders. Verify archive locally or on Windows with bounded standard-library reader:

```text
python verify-r11-archive.py --archive result-export-r11.zip --manifest result-export-r11.manifest.json --output result-export-r11.verified.json
```

Verification emits `raw-export-verified` with `qualificationClaim=false`; raw status, owner, timing, collector/launcher streams, & samples remain in archived bytes.
