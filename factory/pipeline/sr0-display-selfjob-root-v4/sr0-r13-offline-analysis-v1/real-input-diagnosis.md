# R13 offline analysis input diagnosis

Live r13 export inventory proves these sealed bytes:

- `run/presentmon.csv`: 926,320 bytes, SHA-256 `b080fcab80dd5b802a82e844cdd2a8e7c95c84a1e4b9efc9e6b72c4820a2f76e`; 4,506 rows, 4,203 WorkloadWin rows, target PID 17076.
- `run/result-workload.txt`: present, 2,856 bytes in live export; hash must be measured from explicit exported bytes before materialization.
- `run/presentmon.stderr.txt`: 65 bytes, SHA-256 `f522a4b28ee9eedb6189a4389f8fa839f193614ad098940bb23ae59e6d185b28`; sealed benign warning.
- `run/presentmon.stdout.txt`: sealed in export; bytes/SHA must be measured from materialized source.

Frozen parser also requires `build.json`, `r1/meta.json`, `r1/integrity.json`, `r1/inputs.csv`, `r1/frames.csv`, `r1/bridge_input.csv`, `r1/ticks.csv`, `r1/mainactor.csv`, & `r1/inject.csv`. These are not claimed from live receipt inventory. Materializer rejects absent entries; it never fabricates build/run tables.

`presentmon.console.txt` is absent from collector output. Materializer may derive it only by exact byte concatenation in declared order `presentmon.stdout.txt`, then `presentmon.stderr.txt`; receipt records source paths, source bytes/SHA, order, output bytes/SHA, & `syntheticBytesAdded=0`. No newline, warning, or parser row is inserted.
