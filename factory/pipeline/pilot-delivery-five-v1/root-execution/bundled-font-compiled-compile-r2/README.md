# Bundled Tinos compile-r2 preparation

This packet refreshes Windows compile inputs from `bundled-font-readiness-v6-line-limit-host` while retaining runtime 37429120e7dd4e060ecf1a58a92ae3a7f4d2b12b, renderer ABI 0.6 hash `e280f4a9fd9eca0a7b2657f72f8c322a537cee7b4c85999f6cbf7eb1f39ccc93`, witness hash `sha256:e3917a212ec66304bac8631b835b05f95956bff695b13688743b967b522cfadb`, Tinos resource bytes/hash, compiler pin, bridge pins & case identity.

`stage-build-r2.ps1` requires restored active stage `D:\Claude\swiftright\.factory-work\hosts\bundled-font-compiled`, free desktop lock, quiescent owned processes, exact prior plan hash, fresh archive path `source-before-retry-r3`, & absent `prebuild-r3`. It archives prior source rows & plan, writes 15 v6 source rows, stages exact `package/paint-canary.patch` (5638 bytes, SHA-256 `sha256:59f05a177b557559024604d668f633206efa147f99e4223acc76ea4e4a126765`) & `tools/stage-tinos-font.ps1`, then validates bytes/hashes & runs existing `build-owned-pilot-v1.ps1` preflight & bounded compile with `-Attempt 3`. No native run occurs. Historical compile-r1 evidence remains untouched.

Resource staging uses v6 `package/Resources/Tinos-Regular.ttf` (521588 bytes, `sha256:60a0e8ef0c04dd5dd69ffe91025fa2ae5836cbd35600a82ba031977557e2cb61`) & copies it beside fresh `FactoryProbe.exe`; patch is source-only, no canary executable is assumed.
