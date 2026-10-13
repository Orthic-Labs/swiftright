# V7 full admission review

Static source admission passes for five seed rows, but bounded capture is held: v7 archives recipe JSONs, not canonical case JSON artifacts required by `capture_origin.py`.

Evidence:

* stage `sha256:2ab90d9a5f42cf88dabdba97067447d314351925a88d3a3c4fec0d90ae0a2a66`, 69 files, 280027 bytes
* `verify_v7.py`: PASS; `test_v7.py`: PASS, 5 rows, 8 controls, `captureStatus=NOT_RUN`
* collector v7 equals v6 byte for byte: `sha256:737399fcb39f13d79a8e908507210d0de733a3180b8eded63dfa7ec70ed2f8bf`
* runtime closure: 23 files, PASS, live imported bytes match archived copies; AXClient `sha256:9514c4ed6964a9a078058fc909ea72a89ad6363fd0662ed2e9369788af59c404`; CaptureHost `sha256:749fb3b497784aa8edc344868c15fcf0d69c2bd9a63cdb37a8592949ef77688b`
* compiler resolver + compiler subprocesses route through `_compiler_build_common`; owned process groups use bounded drain, TERM, KILL; no direct unbounded `swiftc` route
* AXClient/CaptureHost use preflight-only APIs; request APIs are absent; denial remains `HELD`

Required fresh v8 fix: add five full canonical case JSON files under `inputs/` (or pass an equivalent immutable case root), each named by exact case ID expected by `capture()`, with canonical hash equal to manifest `case.hash`. Current `--case-root .../seed-origin-v7/inputs` resolves no such files, so first case raises `CaptureError('execution eligible probe requires persisted canonical case')` after build/preflight and before runs.

Text bundled-font row explicitly holds bundled resource qualification: recipe says repository contains no bundled font resource, manifest has no `providerResources.font`; keep `witnessFontResolution`, `registeredFontProvider`, and font claims held. Other rows have no provider resource and retain host/provider, internal-layout, animation, compositor/AX availability holds per runtime gates.

After v8 case artifacts are pinned, bounded 100-run command is recorded in `report.json`; output remains candidate-only under `factory/native/macos/evidence/`, binaries/work stay under `/Users/adrdsouza/Library/Caches/SwiftRightFactory/`.
