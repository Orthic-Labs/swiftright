# External owner raw capture

This folder records raw facts for 541 SwiftUI interface extension headers targeting 39 explicitly qualified SwiftUICore nominal paths; 508 headers have v12 member rows. Each record binds exact SwiftUI header source line/text, SourceKit extension entity/USR when present, member rows, SwiftUICore owner source line/text/access/kind/owner chain, raw SourceKit owner entity/USR when present, & exact SwiftUICore symbol graph matches when present. Pinned index omits 19 extension header entities & 111 conditional owner declaration entities; records retain `missing-in-pinned-index` status.

Inputs are pinned to immutable 836 evidence, final census `sha256:ba84859f8387d3c1361b3287a5adf458fd256ffb8c8d900c72997cf43cdaf174`, arm64e SDK interface hashes, SourceKit request/output hashes, SwiftUICore graph hash, target `arm64-apple-macosx27.0`, & Xcode-27-RC toolchain identities. Twelve target paths have no SwiftUICore graph match; this capture preserves that fact without treating graph absence as exclusion or eligibility evidence.

Run `python3 capture_external_owners.py` to regenerate capture & `python3 test_external_owners.py` to replay source/stream bindings.
