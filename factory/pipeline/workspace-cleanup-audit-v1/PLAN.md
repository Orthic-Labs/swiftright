# Source-only cleanup inventory

No files deleted. Process/open-file snapshot found no users of listed candidates; root rechecks immediately before cleanup.

| Exact native scratch directory | Allocated KiB | Archived files |
|---|---:|---:|
| `/Users/adrdsouza/Library/Caches/SwiftRightFactory/seed-origin-actual-v1-20261011` | 1340 | 22 |
| `/Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/seed-origin-v8-capture-20261011` | 1324 | 22 |
| `/Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/external-ax-client` | 96 | 2 |
| `/Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/additive-copy-cost-root-r3-20261011` | 584 | 41 |
| `/Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/existing-recorder` | 152 | 3 |

`report.json` lists 240 exact generated compiler-cache paths, 4.2519 GiB total. These regenerate from retained source/toolchain; source, Products, test executables & logs remain outside listed paths. Byte-identical cache reconstruction is not claimed.

Whole `/Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/runtime-additions` remains HOLD (~9.60 GiB). Preserve copied source, Products & intermediate failures until byte-archived. Specific unarchived historical log: `scroll/fresh-runtime-db29/probes/sr0-s/fresh-runtime/out/swift-test-scroll-db29.txt`. Final 175-test root integration receipt, stdout, patch/source anchors stay canonical in factory; they do not substitute for intermediate logs.

Other old native/control directories retain individual HOLD status with missing archive paths/hashes in report. Active `sr1/git-root` contains root remote audit helper; preserve it. Fresh Mac20 execution/cache directories belong separate cleanup-rehydration owner.

Root cleanup order: retire five byte-archived native directories; retire exact cache-only candidates; retain every HOLD directory. Regeneration & archived re-extraction are separate operations.
