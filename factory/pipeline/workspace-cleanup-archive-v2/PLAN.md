# Exact scratch preservation & cleanup plan

Archive PASS: 231,732 files, 30,776 unique objects, 146 gzip chunks. Original bytes: 6,845,389,931; unique raw bytes: 3,138,856,489; compressed chunk bytes: 967,130,557. Largest compressed chunk: 12,164,972 bytes (<50 MB). Every raw object, part, tar member, chunk & compressed/raw manifest hash verified.

All 64 exact roots are listed in `archive-descriptor.json`. Keep exclusions: active `sr1/git-root`, owner `sr1/f1-residuals`, catalogue/compiler-tool caches, freshMac20 directories. No scratch files deleted.

Archive contains every regular file, including 1,550 product/module/executable-classified files (conservative filename/path/mode tags), 19,158 generated intermediates, 10,619 source files, 199,563 logs/receipts/data files & 842 copied repository state files. Generated objects are preserved; no missing historical process closure is inferred from successful final tests. Current before/after process & open-file snapshots are empty for selected roots.

3,747 canonical byte-reference joins pass with zero conflicts; current reader physical dependencies on selected roots: zero. Existing 91 terminal observations remain unchanged; they do not qualify unrelated jobs. Symlink text for 66 links is archived as metadata; rehydrator neither follows nor recreates links. No receipt path requires symlink alias reconstruction. Historical missing scroll test log now has exact archive bytes.

Root cleanup: recheck each selected root for processes/open files & new consumer paths; compare regular-file hash manifest if roots changed. Retire exact roots after checks. No generated Product or raw evidence is discarded without preserved bytes. Keep archive descriptor, chunks, consumer snapshot & verification receipt.

Verify full archive offline:

```sh
python3 factory/pipeline/workspace-cleanup-archive-v2/restore.py --descriptor factory/pipeline/workspace-cleanup-archive-v2/archive-descriptor.json --sha256 sha256:d752681c7526631e55c7f73415f026a4f1a0704359d2cd5900d35c6de290ef1f --receipt factory/pipeline/workspace-cleanup-archive-v2/verification-replay.json
```

Rehydrate selected original file into fresh internal scratch (no native execution):

```sh
python3 factory/pipeline/workspace-cleanup-archive-v2/restore.py --descriptor factory/pipeline/workspace-cleanup-archive-v2/archive-descriptor.json --sha256 sha256:d752681c7526631e55c7f73415f026a4f1a0704359d2cd5900d35c6de290ef1f --only /Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/runtime-additions/scroll/fresh-runtime-db29/probes/sr0-s/fresh-runtime/out/swift-test-scroll-db29.txt --output /Users/adrdsouza/Library/Caches/SwiftRightFactory/workspace-cleanup-archive-v2/replay-scroll-log-r1 --receipt factory/pipeline/workspace-cleanup-archive-v2/rehydration-scroll-log-r1.json
```

Successful rehydration receipt supplies `rehydratedReaderConfig.macRoots` & explicit original-path → restored-file `macPathMap`, suitable for existing `ArchiveByteReader`. Caller admits this fresh config; frozen configs/receipts stay untouched. Rehydrated compiler/source/output bytes remain historical observations. Byte restoration adds no schema qualification, parity or promotion.
