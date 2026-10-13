# Windows star.fill compiler-ready source packet

This packet preserves original `Image(systemName: "star.fill")` witness, `.resizable()`, `.scaledToFit()`, 32×32 frame, yellow foreground, light color scheme. `FactorySystemImageAssets.json` remains provider-raster-pending; no named RGBA fixture, SF Symbol replacement, or Mac golden asset is included.

Root materialization:

1. Run pinned provider-raster producer, archive raw RGBA, glyph/provider identity, resource hashes, process receipts, and fault receipts.
2. Verify measured `star.fill` → `Segoe Fluent Icons` `E735` mapping, dimensions, RGBA hash, and license field. Copy only verified mapping into fresh `.factory-work/hosts/system-star-fill-r4/package`; keep source packet immutable.
3. Materialize fresh canonical case/tuple/source-binding hashes after staged provider bytes are joined. Null fields here remain holds.
4. Execute `package/plan.json` compile request with one job, `-Xswiftc -j1`, `-Xswiftc -num-threads -Xswiftc 1`, 1 GiB cap, and canonical runtime/bridge/renderer paths.

Required channels before any promotion: provider bytes/hash, compile source join, compiler receipt, EXE hash, native lifecycle receipt, tagged screenshot/UIA, and Mac comparison. Current packet is source-ready only.
