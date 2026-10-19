# R5-09: SliceApp MSIX pair on SR0 tuple 09 (renderer pin E280F4A9 unchanged), build and Sandbox (2026-10-10)

Dell stage root `D:\Claude\sr0-r5-09` (nothing deleted or recycled). @rightkit/release 0.2.146, non-elevated one-shot tasks (`elevated=False`). Build and Sandbox ran under `D:\Claude\desktop.lock` (label `r5-09`; the Sandbox step waited behind another lane's lock). Sandbox windows kept in the background with `sandbox-background.ps1 -Watch` (committed 3587dcc; pushes 568, push_failures 0 in the retried network run's log). Harness = `git archive f990166`. Artifacts: `/Volumes/D/scratch/swiftright/sr0-artifacts/win/r5-09/`. Cert 121FD7B5 (expires 2026-10-12 05:16:54) signed first-try.

## Build

| | 0.1.0.0 | 0.1.1.0 |
|---|---|---|
| Source | `f990166d8efbd0a7dd7ca3ff7d4f5e2f93291b83` (clone `clean`) | clone-local `edb78d43ebf9877c87795bcb37dceb5b52a6ab0e` on f990166 (`clean2`, not pushed) |
| QA source receipt | passed `f239798a2024f20e…` (3/3) | passed `a8a08050d1373988…` (3/3) |
| Seal | `sliceapp-0.1.0-f990166d` | `sliceapp-0.1.1-edb78d43` |
| msix sha256 | `e341d7f963155a984e683109b1e89c48212738c73cf7666a34e2c54a4c4a2e26` (29,066,984 B) | `5958689cb1fd44d91c4bb727b8678e9203fdfe115fdcc769a29840b7dfcb5ae7` (29,067,059 B) |
| = seal sha256 | yes | yes |
| signtool /pa | verified, 0 errors | verified, 0 errors |
| Layout Stage check (unpacked signed + stage dir) | OK, digest = pin E713BF40… | OK |
| SliceApp.exe subsystem | 2 | 2 |

Renderer pinned ok (E280F4A9) in both logs. `swift-only-proof`: `ok: true` (changed payload manifest + exe only). Feeds identical to tuple 07/08 (`87d7e8cd…`, `5eb70594…`). Seal sha256 `7eca4ee4…` / `c15e1e26…`.

## Sandbox (no hold-open)

| Run | Profile | Result | run.json sha256 |
|---|---|---|---|
| `r5-09-offline` | Offline | 13 of 14 PASS, **W08 FAIL** | `f5fbe0b26530c4680d05f6faf053f12d1b66d5f78453718df62762b01a4e1808` |
| `r5-09-network` (first attempt) | Network | FAIL, timeout: guest wrote no receipt in 40 min (not in the qualification records) | `a62cb1e1…` |
| `r5-09-network-2` (retry) | Network | W00, W01, W12 PASS | `51fb6d8aebe799961cbe8a3b2fd13ed47b23e2a988c9d2dedd598759206beb35` |

Offline: W00–W07, W09–W11, W13, W14 PASS. W08: 5 genuine interruptions, 4 ok (c3, c4, c5, c11); c6 (+240 ms) left 0.1.0.0 `Modified, NeedsRemediation` (RegistrationChanged), no window in 40 s, second update then registered 0.1.1.0 Ok with data intact. Same known platform behaviour as tuples 07/08. W12 PASS (network-2).

The first network attempt: guest never started its checks (receipts folder only had the host run.json); cause not established (the offline run with the same watcher worked, and the retry with an identical launcher passed). Kept as `receipts-network-1-timeout`.

## Records and package stage

`qualification/receipts/package/win-r5-09-{offline,network}` (network = r5-09-network-2); `win-r5-08-*` moved with `git mv` to `package-history/`. `run.py run --stages package --no-tuple`: network 3/3 PASS; offline fails only on W08; windows-x64 union fails on W08 alone. No tuple comparison. Window titles in copied records: only `SliceApp`.
