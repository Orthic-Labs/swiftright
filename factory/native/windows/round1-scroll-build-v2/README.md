# Scroll compiler-only builder v2

Exact scroll v1 package & plan `87e220ea…` retained; inherited runtime/bridge/member/compiler guards remain. Package must additionally contain exact runtime-source-tree.json metadata consumed by runtime verifier. Output is fresh build-v2-r1.

Before compiler starts, builder reads control-results/cleanup-controls.json, host-input-controls.json & parse-controls.json. It requires current production helper hashes, exact positive/fault coverage, strict typed successful outcomes & zero parser errors covering builder/helpers/control sources. Missing, failed or stale controls stop entry.

Root prepares control-results directory, runs pure-controls/test-cleanup.ps1 with Output cleanup-controls.json; runs pure-controls/test-host-inputs.ps1 with fresh OutputRoot control-results/host-fixtures then copies its controls.json to host-input-controls.json; runs pure-controls/parse-controls.ps1 with Output parse-controls.json. Root archives actual receipts before build. Source packet does not claim these controls executed.

Inherited retained-kernel-handle cleanup preserves raw streams/durable receipt. Natural exit never terminates. Deadline terminates owned driver only & records unresolved descendant ownership; unsuccessful control refuses further builds until ownership addressed. No PID taskkill, GUI or test execution. Source v1 remains frozen.
