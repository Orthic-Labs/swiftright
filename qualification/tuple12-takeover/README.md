# Tuple12 takeover closure ledger

Source-bound inputs:

```text
source commit  0e201571e4320a3b6ccce14313fd2ad67e523904
source manifest f45b9e0dab99428194946341b0170f0e3beed874f9f552d01fd9046f3200b7ca
FreshOnBridge  87b8cb27ce6730e56681fac3ea22ed3dfb859b3dddb697c339318f4ce60eb374
renderer DLL   7578cd5da8a6831900c66680c4b94f89e64b6b294623709817848b02219aeac2
r5 driver      5c7295a4c71014ec053082f3d04095773b5c2af6183fcf3c2ad95cb4218b58c4
worker-v3      8d3918b5ecdf0ca31405015c17109166db732a8d6014aa4755410a1972aa3ec6
coordinator-v3 4bef611745175a0d5b8716a5159620a4ba38694ae4de04c38183f20e0bdc63f4
Cargo.lock     0e28d8bbbb13208c1951341741ec28a66b9c9e74a351708070207d973c478c9c
```

Root-managed Windows sequence after fresh Full output exists:

```sh
python3 qualification/assemble-tuple12-windows-full-v1.py --root <Full-16-output> --out <Full-16-report.json> \
  --expected-exe 87b8cb27ce6730e56681fac3ea22ed3dfb859b3dddb697c339318f4ce60eb374 \
  --expected-renderer 7578cd5da8a6831900c66680c4b94f89e64b6b294623709817848b02219aeac2 \
  --expected-driver 5c7295a4c71014ec053082f3d04095773b5c2af6183fcf3c2ad95cb4218b58c4 \
  --expected-worker 8d3918b5ecdf0ca31405015c17109166db732a8d6014aa4755410a1972aa3ec6 \
  --expected-coordinator 4bef611745175a0d5b8716a5159620a4ba38694ae4de04c38183f20e0bdc63f4 \
  --source-commit 0e201571e4320a3b6ccce14313fd2ad67e523904 \
  --source-manifest-sha256 f45b9e0dab99428194946341b0170f0e3beed874f9f552d01fd9046f3200b7ca \
  --base-path 'D:\\Claude\\swiftright\\.work\\sr0-r12-typecheck\\src' \
  --driver-path 'D:\\Claude\\swiftright\\.work\\sr0-matrix-controls-v1\\tuple12-startupguard-matrix-v1\\drive-fixture-noactivate-focus-r5.ps1' \
  --worker-path 'D:\\Claude\\swiftright\\.work\\sr0-matrix-controls-v1\\tuple12-startupguard-matrix-v1\\worker-v3.ps1' \
  --coordinator-path 'D:\\Claude\\swiftright\\.work\\sr0-matrix-controls-v1\\tuple12-startupguard-matrix-v1\\coordinator-v3.ps1'
```

After strict matrix admission, root owns 20 Windows cross runs/config:

```sh
BIN='D:\\Claude\\swiftright\\.work\\sr0-r12-typecheck\\src\\scratch\\out\\Products\\Release-windows-x86_64' \
EXPECT_EXE=87b8cb27ce6730e56681fac3ea22ed3dfb859b3dddb697c339318f4ce60eb374 \
EXPECT_RENDERER=7578cd5da8a6831900c66680c4b94f89e64b6b294623709817848b02219aeac2 \
qualification/tuple12-cross20.sh <fresh-cross-output>
```

Automatable package checks: W00–W07 & W09–W14, plus M00–M11, once fresh signed MSIX/DMG run receipts bind tuple12 hashes. W08 remains external RightKit helper proof: install registration, genuine cancellation to `Modified, NeedsRemediation`, helper transition, relaunch, data integrity, legacy path, & signed-source receipts. Mac full16 remains held until generalized recorder has same Team/signature & process-level no-prompt proof; existing trusted recorder is F1-only. Narrator audio remains human listen/date/verdict after automated checks. No freeze claim until all receipts join.
