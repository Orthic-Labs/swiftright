# Round 1 scroll-build v2 independent source review

Blocked before root control execution: `factory/native/windows/round1-scroll-host-v1/package/runtime-source-tree.json` is absent. `build-host-v2.ps1` invokes `Assert-FactoryRuntimeSource` before `Assert-CompletedBuildControls` or compiler start; verifier requires this file and compares its raw hash to `plan.runtimeSourceTreeHash`.

Builder source is otherwise pinned to manifest `11d1423be2be77b90d678166971e25b56e1191f97e7937f2caa3b0c11abf19e8`, plan `87e220ea813bfc3a11fca006b1388865c1137f3d3cebd2f760baac96908ba904`, shared host helper `93c5c8e29999796f2c8a1c0689f384e3ea8b99d9e655c3e2a98e52baa27e49db`, and inherited cleanup manifest `194dd278a3771d6e8daa416aeaac252bca93f982bc069511aca43bb1c1397b97`.

After metadata repair, rerun source review. Root then runs fresh pure cleanup, host-input, and AST controls before one compiler-only build. Native parity, GUI, executable launch, and test runner stay held.
