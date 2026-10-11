# Copy-cost Windows serialized pair

Exactly one current → candidate full release suite ran, preserving all 175 original tests, TaskID 40 ms body / 120 ms sleep & performance bounds 2 / 4 / 15 ms. Current passed 175/175, exit 0; candidate passed 174/175, exit 1. `PerformanceTests.testSingleRowEditCommitTime` produced two assertion failures. TaskID same-ID test passed both runs. Source before/after hashes matched; only candidate Graph.swift differs.

| Variant | Typing ms | Scroll ms | Row-edit ms | Suite seconds |
|---|---:|---:|---:|---:|
| Current | 1.9871 | 3.3146 | 3.1923 | 4.658 |
| Candidate | 6.4876 | 11.5197 | 9.2915 | 6.803 |

Quiescence cleared after 11 samples, but unrelated Rust/link compilation resumed before current launch. Current phase CPU load ranged 7–63%; candidate 4–70%. Sampling brackets around current timing had no external compiler; candidate brackets contained 14 & 19 rustc processes. This captures observational outcomes without causal certification. No retries, filters, threshold changes, external-process termination or production edits occurred.

Actual process argv, cwd, UTC, CIM descendants, source/compiler/executable hashes & native stdout/stderr bytes remain in [receipt](results/receipt.json). Complete competing-process samples remain in [observer JSONL](results/factory-swiftright-copycost-observe-46e039abb746/samples.jsonl). [Verified accounting](verified-capture.json) binds raw outcomes, binaries & load observations. Existing TaskID packet preserves exact compiler bytes by references in frozen source plan.
