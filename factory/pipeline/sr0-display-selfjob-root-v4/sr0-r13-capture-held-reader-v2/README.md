# SR0 r13 capture-held reader v2

Sibling successor to v1. v1 remains immutable. v2 fixes PowerShell property-expression parsing by resolving properties before boolean evaluation & uses `Set-Field` for every mutation, including absent `nativeQualificationClaim` fields.

`capture-held-predicate-v14.ps1` is report-only: it accepts r13 capture completion held behind `strict-display-parser-pending`, requires terminal workload/PresentMon/stream/job evidence, & rejects qualification claims & lock mutation. `test-capture-held-controls-v2.ps1` AST-extracts exact predicate, pins actual receipt hashes from `source-pins.json`, accepts actual r13 receipts, & rejects nine in-memory faults.

```powershell
& .\test-capture-held-controls-v2.ps1 `
  -CaptureRoot '<fresh-r13-receipt-root>' `
  -PredicatePath '<repo>\factory\pipeline\sr0-display-selfjob-root-v4\sr0-r13-capture-held-reader-v2\capture-held-predicate-v14.ps1' `
  -SourcePinsPath '<repo>\factory\pipeline\sr0-display-selfjob-root-v4\sr0-r13-capture-held-reader-v2\source-pins.json' `
  -ControlRoot '<fresh-control-root>'
```

Offline strict parser remains separate & cannot promote capture-held evidence. Run frozen `qualification/tuple12-takeover/workload-analysis-v3/analyze_workload.py` only after bounded materialization of exact `result-workload.txt`, sealed `presentmon.csv`, required `presentmon.console.txt`, `build.json`, & `r1` tables. R13 collector published sealed PresentMon stdout/stderr, not frozen `presentmon.console.txt`; derive no values. Missing console/run tables remain parser hold.

`offline-provenance-plan.json` records parser-required files & explicit console provenance. R13 has sealed `presentmon.stdout.txt` + `presentmon.stderr.txt`, but no frozen `presentmon.console.txt`; any future materializer must record both source hashes/bytes, concatenation order, derived bytes/SHA, & must add no synthetic lines. Until such receipt exists, parser status stays held.
