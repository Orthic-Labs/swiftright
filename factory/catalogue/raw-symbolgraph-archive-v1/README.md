# Raw symbolgraph archive v1

This archive preserves the 11 exact `rawGraphInputs` named by immutable
compiler-cursor evidence 836. It does not normalize or re-serialize graph JSON.
Each source is split into ordered 64 MiB raw chunks, then gzip-compressed at
level 9 with mtime zero. Manifest records original path, size, SHA-256, raw
fragment hashes, compressed hashes, offsets, and descriptor order.

`archive.py capture` reads only source paths named by 836, verifies each full
original hash, writes chunks, then writes manifest atomically. Every archive
file is a chunk smaller than the source and the large SwiftUI graph is divided
so no individual checked-in file approaches 100 MB.

`load_archive()` requires caller-supplied trusted manifest SHA-256, live link
evidence path, workspace root, and internal scratch root. It verifies the
exact pinned 836 bytes and ordered descriptors, manifest bytes, chunk order,
offsets, gzip metadata, compressed/raw hashes, and every reconstructed
whole-file size/hash. It exposes content-addressed reconstructed paths only
after all 11 inputs validate. Scratch must resolve under fixed
`~/Library/Caches/swiftright/raw-symbolgraph-archive-v1` on the home volume &
remain disjoint from resolved workspace/archive paths, including symlinks.
Reader rechecks exact `captureSources` pins against adjacent
producer/test/README bytes & the executing reader source. Numeric manifest
fields require true integers; booleans are rejected. It does not infer or
rewrite USRs.

Run focused fault tests with:

```sh
PYTHONDONTWRITEBYTECODE=1 factory/.venv/bin/python factory/catalogue/raw-symbolgraph-archive-v1/test_archive.py
```
