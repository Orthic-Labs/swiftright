# Inactive branch spike

This review holds `SwiftUI.WidgetBundleBuilder.buildLimitedAvailability` at line 28491. Pinned `arm64e-apple-macos.swiftinterface` source places line 28491 in `#else` of `compiler(>=5.3) && $InlineAlways`; line 28484 is selected branch. Fresh pinned `swiftc` compilation & run selected `InlineAlways` with exit code 0.

Raw SourceKit evidence remains absence-only without branch proof: exact line/name index count is 0 & cursor response is `Unable to resolve cursor info.` Symbol graph retains two overload candidates with distinct USRs. Guard requires exact source branch tree, compiler probe receipt, immutable 836 link evidence, request/response/tool/source hashes, owner/kind/access, & both graph entities. It rejects active, unknown, malformed, wrong source, raw, request, tool, graph, & probe mutations.

Run `python3 investigate_inactive_branch.py` to regenerate evidence & `python3 test_inactive_branch.py` to replay it.
