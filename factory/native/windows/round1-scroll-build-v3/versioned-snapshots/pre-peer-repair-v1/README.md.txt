# Scroll compiler-only builder v3

V2 source & failed precompiler admission remain unchanged. V3 renames reserved automatic `$host` variable to `$hostControls`; exact scroll witness/package/plan remain pinned. Fresh compiler output: build-v3-r1.

Run run-controls.ps1 first. It generates actual cleanup/host-input/AST outputs, invokes actual production Assert-CompletedBuildControls on those outputs, then invokes same function against retained positive/missing/stale/failed/bool-count fixtures. No compiler/native calls occur. All fixtures persist; missing-file fault renames evidence without deletion. Basic reserved-assignment lint checks Host/PID/input assignments across every owned PowerShell script.

Builder requires actual admission invocation proof & fresh full-script lint receipt in addition to cleanup/host-input/AST source hashes. Missing/stale/failed proofs stop before compiler. Controls remain unexecuted in this source packet; root runs real controls & archives results before build.

Retained kernel handle cleanup, bounded raw stream capture & unresolved-descendant timeout receipt unchanged from v2. No PID taskkill. This source preparation performed no SSH, compiler or GUI actions.
