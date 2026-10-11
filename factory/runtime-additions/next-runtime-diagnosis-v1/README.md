# Next runtime diagnosis v1

Read-only diagnosis of Windows TaskID & performance failures.

TaskID evidence reaches `start a` without terminal event before assertion. `settle()` is three yields plus 120 ms sleep, not completion barrier. Weak `NodeHandle` plus generation guard leave scheduling, early Graph lifetime, & generation rejection unresolved. Baseline also fails, postshape fails intermittently, & fontstorage later rounds pass; Font.Metadata box has no proven causal role.

Three copied-source focused release tests ran on macOS arm64: original, Graph retained through await, & Graph retained plus terminal event barrier. All passed; retained logged `commit=true a`, terminal logged `terminal=true` plus `commit=true a`. This validates diagnostic harness only; Windows behavior remains unresolved.

Performance evidence shows optimized typing 2.9427 ms > 2 ms & scroll 4.173 ms > 4 ms, while row edit 8.2319 ms < 15 ms; debug passes broad limits & exact work-counter tests pass. No phase delta or matched original/final causal result exists, so no runtime fix is justified.

Provenance is repaired in `mac-process-receipt.json`; `stage-manifest.json` pins all 150 owned source/log files. Next bounded action is one focused Windows run of retained & terminal variants with original assertions preserved. For performance, capture GraphProfile phase deltas only in one matched optimized original/final pair if run is authorized by existing owner.
