# Origin integration review

Read-only audit of `core.py::_origin_issues` & `evaluate_gate`, origin integration tests, Windows archived numeric checks, & workflow call sites. Gate API is fail-closed: every captured run, including seeded-runner additions, reaches platform-specific byte verification; missing reader, unsupported platform, malformed reader output, reader exception, or guard issue adds blocking issue. `verified`, `status`, & native-parity labels do not substitute for guarded bytes.

Workflow `report()` & `gate_evidence()` currently call `evaluate_gate()` without `origin_reader`; those paths remain held with “native origin archive reader unavailable” and cannot emit origin-qualified pass. Keep this explicit until a trusted archive-owned reader is wired into those calls.

Root-reported gate suite (42 tests) & origin integration suite (7 tests after Windows v2) passed once. Final local targeted run used `factory/.venv/bin/python` and passed 23 tests: 7 origin integration, 11 Windows archive binding & 5 strict numeric-origin cases. Earlier system/bundled Python import failures are preserved in `retest.*`. Windows numeric tests separately mutate receipt `exitCode`, receipt `index`, capture `run`, & string index; workflow uses exact `type(x) is int` checks for each.

Mac guard & its test changed during concurrent v4 work. Initial inspection hashes were `ae156753…` & `e02c95b1…`; final 23-test run used `abac68ee…` & `98747096…`. Both versions are pinned, and this review covers integration boundary rather than Mac guard v4 internals.
