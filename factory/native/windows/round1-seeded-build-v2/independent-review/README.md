# Seeded build v2 source review

V2 receives source clearance for fresh controls followed by compiler-only builds. Five exact package paths are allowlisted with exact plan hashes; source-admission metadata and local source-binding hashes match. Runtime commit/tree/receipt, verifier, host-input guard, compiler, renderer, bridge membership and bridge hashes are checked before and after each build.

Control flow uses Windows PowerShell 5.1-safe direct JSON decode followed by `@($decoded)` unroll in production parse admission and fixture paths. Integer admission accepts exact bounded Int32/Int64 values only. AST parse, reserved-variable lint, seven admission faults, nine integer faults and five host-input faults are required before compiler invocation.

Builder uses retained kernel handle operations, avoids PID lookup and `taskkill`, drains raw stdout/stderr into files, records receipt fields, refuses unresolved timeout state, checks PE subsystem 2, and never launches produced executable. Output is `build-v2-r1`.

Source-only state remains explicit: controls are prepared but unrun, no compiler/native/SSH/GUI action occurred, and no Mac parity or native qualification is claimed. Stage hash: `a9d53bdb2872ac8bccdd437104d107e4d1e37ba787735ecff41ab2d90db7f03f`.
