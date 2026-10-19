# R5-10: SliceApp MSIX pair on SR0 tuple 10 (runtime change 8e47b89; renderer pin E280F4A9 unchanged), build and Sandbox (2026-10-11)

Dell stage root `D:\Claude\sr0-r5-10` (nothing deleted). @rightkit/release 0.2.146, non-elevated one-shot tasks (`elevated=False`). Build and Sandbox ran under `D:\Claude\desktop.lock` (label `r5-10`, queued behind `matrix10` and `lanes10`). Sandbox windows kept in the background (`sandbox-background.ps1 -Watch`: offline run pushes=157, push_failures=0). Harness = `git archive 0a745ab`. Artifacts: `/Volumes/D/scratch/swiftright/sr0-artifacts/win/r5-10/`. Signed before the Sandbox (cert 121FD7B5, expires 2026-10-12 05:16:54).

## Build

| | 0.1.0.0 | 0.1.1.0 |
|---|---|---|
| Source | `0a745abca1391d266331940b70fe6a305f1a7039` (clone `clean`) | clone-local `c60b1377bdd0d7a670009d9791d9b20834e7da78` on 0a745ab (`clean2`, not pushed) |
| QA source receipt | passed `1c87f7d8940b774b…` | passed `8875a8a11f5ca1e2…` |
| Seal | `sliceapp-0.1.0-0a745abc` | `sliceapp-0.1.1-c60b1377` |
| msix sha256 | `39007039eeec260959263cb130d317031f0e3b581f4037d661f37a0d3f2ccb01` (29,067,659 B) | `efc52869b889fefe883c4991a6f8c1878232275f5e452b29aea227645e085157` (29,067,759 B) |
| = seal sha256 | yes | yes |
| signtool /pa | verified, 0 errors | verified, 0 errors |
| Layout Stage check (unpacked signed + stage dir) | OK, digest = pin E713BF40… | OK |
| SliceApp.exe subsystem | 2 | 2 |

Renderer pinned ok (E280F4A9) in both. `swift-only-proof` ok. Feeds identical to earlier tuples. Seal sha256 `aa06b20a…` / `aea2348b…`.

## Sandbox (no hold-open)

| Run | Profile | Result | run.json sha256 |
|---|---|---|---|
| `r5-10-offline` | Offline | 13 of 14 PASS, **W08 FAIL** | `195b84405e4ae2350c3434412b07148b99ddc72dca273f5839f624e7c216d84a` |
| `r5-10-network` | Network | W00, W01, W12 PASS (first attempt, no retry needed) | `81ce0ca8b6ac102061afe436d7559b4e69b2c0ce1d083aef3e1cff90acad1bfe` |

Offline: W00–W07, W09–W11, W13, W14 PASS. W08: 5 genuine interruptions, 4 ok; c6 (+240 ms) left 0.1.0.0 `Modified, NeedsRemediation`, no window in 40 s, second update registered 0.1.1.0 Ok, data intact; same known platform behaviour as tuples 07 to 09.

## Records

`qualification/receipts/package/win-r5-10-{offline,network}`; `win-r5-09-*` moved with `git mv` to `package-history/`. `run.py run --stages package --no-tuple`: network 3/3 PASS; windows-x64 union fails on W08 only. Window titles in copied records: only `SliceApp`.
