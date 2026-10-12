# Rectangle fixed viewport host v2

Prospective successor preserves frozen v1 host & captured v1 evidence. `v2/CaptureHost.swift` sets `NSHostingView.sizingOptions = []` before attaching host to window, preventing SwiftUI intrinsic content sizing from replacing fixed 320x240 content bounds. Background `orderBack(nil)` & no-prompt permission preflight remain unchanged.

Frozen producer resolves sibling `CaptureHost.swift` & `AXClient.swift` from `module.__file__`; `capture_origin_rectangle_fixed_v2.py` sets that path to `v2/producer-context.py`, so v2 cannot accidentally bind v1 siblings. Root must compile v2 on internal disk, record measured compiler/source/runtime receipts, materialize fresh tuple/case, then capture fresh IDs. Existing v1 raw capture remains immutable & is never relabeled.

Wrapper binds frozen same-group producer SHA `sha256:2772b71ec0b8bd2a8abb56d45b9ac592b29f29557487f229e74ab6d5689e2f39` to child-v2 host/AX sources, requires full measured host hash, & preserves producer lifecycle. No native action is performed by this packet.
