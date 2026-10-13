# Windows star.fill live-provider source packet v10

Fresh source packet after additive `SwiftRightRuntime` API commit. Original `Image(systemName: "star.fill")` witness remains byte-preserved (`0862162052b143a52e3f556e41f70fa02612b0b3f6ee83d7f7aecd835f6a018b`). Segoe Fluent Icons E735 remains explicit substitute provider; SF Symbol parity is unclaimed.

V10 consumes `SystemImageRasterProvider` & `WindowsSystemImageProvider`: exact selected-face comparison after NUL termination, measured top-down native coverage, bounded aspect-fit composition, fail-visible empty/unknown coverage, & no v9 vertical flip/raw-bounds clipping. V9 native bytes remain immutable provenance.

`package/Package.swift` already points at canonical `D:\\Claude\\swiftright\\.factory-work\\runtime-stage\\runtime` & `D:\\Claude\\swiftright\\.factory-work\\inputs\\SwiftRightBridge`. Keep those paths unchanged. Runtime API commit identity is supplied by root after commit; this packet must not invent it. Root refreshes these fields from freshly staged receipt/tree:

```text
source-bindings.json.runtime.commit       = <root-supplied API commit>
source-bindings.json.runtime.treeHash     = <runtime-source-tree.json sourceTreeHash>
source-bindings.json.runtime.sourceReceiptHash = <sha256 of runtime-source-receipt.json>
```

`source-bindings.json` currently pins four image API rows. Root request `image-runtime-api-windows-r1/source-manifest.json` pins those rows plus two font-policy rows; bind all six after API commit. Retain renderer tuple11, bridge ABI 0.6, runtime path, witness hash, & substitute-provider-unverified status.

## Root-owned helper integration

Existing root helpers still pin runtime commit `37429120e7dd4e060ecf1a58a92ae3a7f4d2b12b` & tree `sha256:c9ce2fb6d4e45c4bb452f91895909bc0179d6f9c97a946628a684ff8d163337e`:

- `prepare-pilot-five-compile-v1.py`: fixed assertions at lines 21, 28, 32, 73.
- `prepare-pilot-final-build-v1.py`: `RUNTIME_TREE` & `RUNTIME_COMMIT` at lines 36–37, checks at lines 356–357 & 433–434.

Root integration should make one fresh v10 plan derive runtime commit/tree/receipt from packet runtime receipt, then make finalizer validate that plan identity. Add v10 packet mapping beside existing `image-star-observation` mapping; preserve v9 mapping & all historical packets. No helper edit belongs in this source packet.

## Root Windows headless runtime test

Use existing root entry `factory/pipeline/pilot-delivery-five-v1/root-execution/image-runtime-api-windows-r1/`. It stages only six additive runtime files into canonical rolling stage, uses no fourth `hosts` lane, & runs under existing pinned Windows supervisor:

```text
swift.exe test --package-path D:\Claude\swiftright\.factory-work\runtime-stage\runtime --scratch-path D:\Claude\swiftright\.factory-work\runtime-stage\runtime-api-image-r1-scratch --jobs 1 -Xswiftc -j1 -Xswiftc -num-threads -Xswiftc 1
```

Use 1 GiB RSS, one SwiftPM lane, one frontend thread, sealed streams, quiescence, & no GUI. Root records fresh API commit/tree/receipt hashes after commit; no parity claim follows from headless API tests.
