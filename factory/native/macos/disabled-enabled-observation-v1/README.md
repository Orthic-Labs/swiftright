# Disabled button AX enabled observation, version 1

This new packet adds raw Mac AXEnabled observations for Continue in F9 case swiftui.disabled.recipe/case/f113195a59446fc4. It does not alter prior Mac run receipts or paired reports.

Before launch, a newly compiled AX client ran AXIsProcessTrusted() with no prompt option and returned true; permissionRequests is false. Twenty new windows then used the unchanged internal capture-host binary already bound by 20 previous run owner receipts to the exact generated source SHA-256 68eed62f6ef06ecec579a0e36cdc44a612a559a8329fe6dbd91a700c5d90c005 and case SHA-256 d6a88082e0818e46e4e1ea5e6d45af6edbce63c86fc6b847704c38ad3db9aa99. Each new run records target PID, process start, executable path and binary hash, window title, source/case hashes, client identity and raw AX response.

All 20 runs returned one Continue AX button with AXEnabled successfully read as Boolean true. The collector never invokes AXPress, sends input, or produces a callback receipt. This proves only the observed Mac accessibility enabled state; F9 hit-testing remains untested. It does not establish cross-platform parity or qualification.

Client and probe ran on Xcode 27.0 / Apple Swift 6.4, target arm64-apple-macosx27.0.0, macOS 27.0.1. Client source and binary were built/read from internal SwiftRightFactory cache. Client is ad-hoc signed; trust was checked at runtime without a permission request. Exact toolchain, source, executable, prior owner receipts and all new raw run files are pinned by evidence/input-manifest.json and evidence/stage-manifest.json.

Run offline verification against captured evidence:

```sh
PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=factory/native/macos/disabled-enabled-observation-v1 python3 -m unittest discover -s factory/native/macos/disabled-enabled-observation-v1 -p 'test_*.py' -v
PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=factory/native/macos/disabled-enabled-observation-v1 python3 factory/native/macos/disabled-enabled-observation-v1/seal.py
```

capture.py is the pinned capture procedure; do not rerun it into this frozen evidence directory. It requires a fresh empty run directory and aborts before launching any app if source, case, host, client, prior-run, or no-prompt trust pins fail. The report keeps the original 20-run set referenced by hash and lists a separate new set of 20 observations.
