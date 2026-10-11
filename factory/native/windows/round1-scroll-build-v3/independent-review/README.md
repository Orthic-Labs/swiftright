# Round 1 scroll-build v3 source review

Blocked before controls. `run-controls.ps1:10` passes four comma-separated child paths into one `Join-Path` expression, then uses its result as one command. This does not deterministically invoke `pure-controls/test-host-inputs.ps1` with `-OutputRoot`; host-input output generation and downstream admission proof are therefore not cleared.

V3 correctly renames `$host` to `$hostControls`, adds actual admission invocation proof, seven retained admission faults, full-script source-hash receipts, and reserved-assignment lint. Repair line 10, preserve V2 history, then rerun source review before root executes controls.
