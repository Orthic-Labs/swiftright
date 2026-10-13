# SR0 r13 bounded offline analysis

`materialize-r13-analysis-v1.ps1` accepts explicit manifest entries only. It verifies source leaf files, reparse rejection, per-file SHA/bytes, 16 MiB file bound, 32 MiB aggregate bound, fresh output paths, & exact frozen parser destinations. It copies bytes through bounded streams, derives `presentmon.console.txt` from sealed stdout then stderr with zero inserted bytes, & emits `qualificationHeld=true`, `qualificationClaim=false`, `nativeActions=0`.

Build an explicit `input-manifest.json` from root-fetched r13 archive inventory using `input-manifest.schema.json`; include measured SHA/bytes for every required build/run file. Missing build/run tables fail admission. No parser or native process is launched by materializer.

```powershell
& .\materialize-r13-analysis-v1.ps1 `
  -InputManifestPath '<repo>\factory\pipeline\sr0-display-selfjob-root-v4\sr0-r13-offline-analysis-v1\input-manifest.json' `
  -OutputRoot '<fresh-analysis-root>' `
  -ReceiptPath '<fresh-analysis-root>.receipt.json'
```

Then run frozen parser only against materialized root:

```powershell
& py -3.11 -I '<repo>\qualification\tuple12-takeover\workload-analysis-v3\analyze_workload.py' `
  --os windows --root '<fresh-analysis-root>' --expect-runs 1 --expect-scale 2.5 `
  --out '<fresh-analysis-root>\report'
```

`real-input-diagnosis.md` records known r13 bytes & missing inputs. No qualification or parity claim follows materialization or parser output.
