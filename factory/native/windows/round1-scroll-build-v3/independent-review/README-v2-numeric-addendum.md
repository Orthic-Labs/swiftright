# V3 numeric admission addendum

Line 10 path bug is repaired in `run-controls.ps1` and pre-repair files remain under `versioned-snapshots/pre-peer-repair-v1`.

Admission still uses `-isnot [int]` for JSON count fields at `control-admission.ps1:8,14,31`. Windows PowerShell JSON integer deserialization commonly yields `Int64`; V2 never reached these checks because reserved `$host` failed first. Valid receipts may therefore be rejected before compiler entry. Accept only integral `Int32`/`Int64`, reject bool and floating/decimal values, enforce expected ranges, add positive Int64 plus bool/float/range fault fixtures, and run under intended Windows PowerShell 5.1 and 7 before clearance.
