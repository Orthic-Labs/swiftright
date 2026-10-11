# Round 1 next-build v2 independent source review

Clearance is limited to root running prepared pure controls, then one fresh compiler-only build per pinned package. Frozen builder manifest is `194dd278a3771d6e8daa416aeaac252bca93f982bc069511aca43bb1c1397b97`.

Review confirms exact package allowlist, plan hashes, runtime commit/tree, runtime receipt, factory and bridge member hashes, renderer hash, compiler hash, fresh `build-v2-r1` output, retained kernel process handle, no PID taskkill/Get-Process lookup, raw BaseStream files, durable receipt checkpoints, natural-exit no-termination, bounded wait/drain, and explicit unresolved descendant ownership on timeout.

Root runs `pure-controls/parse-controls.ps1` and `pure-controls/test-cleanup.ps1` first. Any control failure or compiler timeout/failed wait/failed drain/cleanup error blocks subsequent build. Native parity, GUI, test runner, and executable launch stay held.
