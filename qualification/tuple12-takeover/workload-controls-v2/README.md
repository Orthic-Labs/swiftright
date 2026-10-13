# Tuple12 workload lifecycle controls v2

Materialized source-only successor for fresh workload stage. Current `.work\\sr0-r12-workload-v1` build used original run/background overlays; v2 requires root Windows parse/build before use.

Pinned source:

```text
commit       0e201571e4320a3b6ccce14313fd2ad67e523904
manifest     f45b9e0dab99428194946341b0170f0e3beed874f9f552d01fd9046f3200b7ca
materialized 26705e8f1fdd0164a9963c9cb0f730fda2e313e5c07348097c8fe8ab3ef7e468
renderer     7578cd5da8a6831900c66680c4b94f89e64b6b294623709817848b02219aeac2
WorkloadWin  7e749248800da8e6058b0b69ccbab2a5ce2e43a1a719475616da5e92936d930c
```

Controls:

```sh
python3 qualification/test_tuple12_workload_lifecycle_v2_controls.py
```

Result: positive path + seven mutation faults PASS. Windows owner runs parser/typecheck, then stages these scripts into fresh namespace, runs `-NoActivate -LifecycleProof`, & binds lifecycle receipt before R10 admission.
