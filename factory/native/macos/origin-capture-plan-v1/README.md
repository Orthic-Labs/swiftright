# F5 fresh Mac `macOrigin` capture plan

Status: proposal-only. No native/compiler execution occurred. This packet covers fresh `swiftui.padding-frame` runs (20 rows per case) only. Existing raw seed captures without `meta.conditions.macOrigin` remain observational & cannot be retro-qualified.

## Finding

Current `factory/native/macos/capture.py` hashes manifest source & case, copies `Witness.swift` plus generated `CaptureHost.swift` into internal scratch, invokes owned process groups, records binary/AX/recorder observations, then `normalize.py` writes `capture.json`. It does not persist resolver/compiler process receipt, source-before/after, tool-before/after, output/stream refs, or `meta.conditions.macOrigin`; `check_evidence.py` does not check those joins. Existing `factory/gate/mac_origin_admission.py` already defines reader-backed v1 receipt checks, so producer work should emit its required refs without changing schema/gate.

## Minimal fresh-capture flow

1. Resolve one canonical F5 manifest & case. Preserve existing `capture.id` (`<case-id>.macos.run-<NNN>`), manifest case `{id,hash}`, recipe/source hashes, tuple & run number. Reject source/case/recipe drift before build.
2. Keep existing internal-cache scratch confinement, signed F1 recorder preflight, fresh AX preflight, owned process groups & permission preflights. Use `AXIsProcessTrusted()`/`CGPreflightScreenCaptureAccess()` only; never request TCC access. Recorder/AX availability remains factual (`AVAILABLE` or `HELD`).
3. Wrap existing `xcrun swiftc` build with receipt writer matching gate v1: resolver argv, compiler argv/cwd/PID/PGID/times/exit/cleanup, stdout/stderr refs, exact tool before/after refs, exact `Witness.swift`/`CaptureHost.swift` before/after refs, output binary ref, `sourceDrift:false`, `status:SUCCESS`. Main argv must be exactly `/usr/bin/xcrun swiftc -parse-as-library -O -o <capture-host> <Witness.swift> <CaptureHost.swift>`; no unbound source or flags.
4. After build & channel collection, archive exact fresh bytes in an admitted internal archive: canonical case, actual Witness source, generated adapter (SDK source), compiler receipt, resolver/compiler streams, capture binary, `/usr/bin/xcrun`, resolved `swift-frontend`, recorder/AX source/binary/receipt when those channels were used. Reuse `compiler-tool-archive-v1` only when receipt hashes match its manifest; otherwise create successor archive metadata. Never use historical archive bytes to certify a new capture with different hashes.
5. Normalize each run with `meta.conditions.macOrigin` before `validate_artifact`. Keep all existing fields & candidate flags. Bind `captureId` to `capture.id`; bind `case` to exact canonical case bytes; bind source, adapter, binary & compiler receipt refs to exact archived bytes. Descriptor below uses only canonical JSON values, so existing `capture.schema.json` remains unchanged.
6. Run existing `mac_origin_admission_issues(capture, origin_reader)` using `ArchiveByteReader` plus explicit `macPathMap` for absolute receipt paths. Reject missing/read/hash/size/case/source/tool/argv/process/stream/binary joins. Preserve rejected evidence & reasons; no parity/promotion claim. Run `check_evidence.py` only after origin refs are present.

If fresh AX client is `AVAILABLE`, include `auxiliaryAX.receipt`, `.source`, `.binary` refs & bind summary `freshAXClient` hashes to them. If it is `HELD`, omit `auxiliaryAX`; do not synthesize availability. Existing trusted recorder can provide observational AX raw output when available, but recorder observation never substitutes compiler origin receipt.

## Descriptor emitted under `capture.meta.conditions.macOrigin`

```json
{
  "version": "1",
  "captureId": "<capture.id>",
  "summary": {"path": "<absolute summary.json>", "sha256": "sha256:<64hex>", "bytes": 0},
  "case": {"path": "<absolute canonical case>", "sha256": "sha256:<64hex>", "bytes": 0},
  "source": {"path": "<absolute Witness.swift>", "sha256": "sha256:<64hex>", "bytes": 0},
  "adapter": {"path": "<absolute generated CaptureHost.swift>", "sha256": "sha256:<64hex>", "bytes": 0},
  "binary": {"path": "<absolute capture-host>", "sha256": "sha256:<64hex>", "bytes": 0},
  "compilerReceipt": {"path": "<absolute compiler-receipt.json>", "sha256": "sha256:<64hex>", "bytes": 0}
}
```

`summary.json` must carry same candidate policy, case/source/adapter/binary hashes & embedded compiler receipt. `capture.id` stays existing typed string ID; `captureId` is a redundant equality check for producer diagnostics, not promotion evidence. `case` ref is source-of-truth for source-case binding.

## 20-row padding acceptance

For each fresh case, require 20 independently produced run directories, unique process IDs per channel, immutable raw/image/capture hashes, exact case/source/adapter/binary joins, origin admission PASS per row, & no missing rows. Keep F5 held channels (scroll/offscreen, font resolution, internal Layout callbacks, dynamic behavior) as held. Padding coordinator may consume candidate IDs & origin issues separately; this packet does not convert observations into parity or baseline.

## Source pins reviewed

Pins are source-review anchors, not execution receipts:

- `factory/native/macos/capture.py` `sha256:f8ab9640bfb04a2c488a6f606828c16fa3712099957dced1d4bb46edc2401e0a`
- `factory/native/macos/normalize.py` `sha256:0eca28223f4a15754c9870c2ac8beb152467e8b701e7754747b879519f6b5e21`
- `factory/native/macos/check_evidence.py` `sha256:1c172b8de9f5f99a2e4813658b8cdbc17e0466b958a8484062a0ad6fce1bb93f`
- `factory/native/macos/AXClient.swift` `sha256:9514c4ed6964a9a078058fc909ea72a89ad6363fd0662ed2e9369788af59c404`
- `factory/native/macos/CaptureHost.swift` `sha256:749fb3b497784aa8edc344868c15fcf0d69c2bd9a63cdb37a8592949ef77688b`
- `factory/gate/mac_origin_admission.py` `sha256:abac68ee7d425aa6303b58a2a3e38eaf522385d3decc0e129760292cbcfec11e`
- `factory/pipeline/archive_reader.py` `sha256:8e1307c6a86323d7d4d464bf1d57e734f83c5f4dfb4ee41ad3a8d2d3016b668e`
- `factory/spec/schema/capture.schema.json` `sha256:ed5bd1604a4e5cf6c913035c94ad2daaac9ccd152421f01a449959a80d59eee2`
- `factory/pipeline/manifests/swiftui.padding-frame.json` `sha256:2412124999a972fdf7fbad7a1f42182bb8a28631cc8a5751de3c666329dd6dac`
- `factory/oracle/mac/compiler-tool-archive-v1/archive-manifest.json` `sha256:66cb21fad8d62d556e1954aeb9da232f5c05709f172242f050a227068629a8b7`
