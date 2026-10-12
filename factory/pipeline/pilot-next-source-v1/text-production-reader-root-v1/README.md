# Text production reader root r1

Source-only bounded adapter for measured Text Windows20 archive
`factory/native/windows/pilot-text-paint-root-v2/actual-count20-r10-r1`.
It streams exact export rows into fresh output, derives 20 typed captures,
binds `ArchiveByteReader` to one immutable archive root per capture, & invokes frozen
`factory.gate.windows_exit_admission` through controls. Raw files stay
unchanged. `qualified=false`, `nativeParityGranted=false`, semantic/timing
remain held. Fresh Mac exit-proof report remains diagnostic-only, with
qualification=false & parity held.

Root command:

```sh
python3 factory/pipeline/pilot-next-source-v1/text-production-reader-root-v1/materialize_text_reader_r1.py \
  --windows-archive factory/native/windows/pilot-text-paint-root-v2/actual-count20-r10-r1 \
  --host-source-root factory/native/windows/pilot-text-paint-root-v2/package \
  --runtime-source-root factory/native/windows/api-font-37429120-20261011/runtime \
  --compiler-binary factory/pipeline/paired-rectangle-fixed-r11-root-v3/artifact-bytes-r1/artifacts/swift.exe \
  --exe-binary factory/native/windows/pilot-text-paint-root-v2/actual-final-r7/FactoryProbe.exe \
  --renderer-binary factory/pipeline/paired-rectangle-fixed-r11-root-v3/artifact-bytes-r1/artifacts/renderer.dll \
  --mac-report factory/pipeline/pilot-next-source-v1/paired-text-exit-proof-root-v1/actual-paired-report-r2.json \
  --output .factory-work/text-production-reader-r1

python3 factory/pipeline/pilot-next-source-v1/text-production-reader-root-v1/run_text_reader_controls_r1.py \
  --reader-input .factory-work/text-production-reader-r1/reader-input.json \
  --captures .factory-work/text-production-reader-r1/typed-captures.json \
  --output .factory-work/text-production-reader-r1/reader-controls.json

python3 factory/pipeline/pilot-next-source-v1/text-production-reader-root-v1/run_paired_report_controls_r1.py \
  --report factory/pipeline/pilot-next-source-v1/paired-text-exit-proof-root-v1/actual-paired-report-r2.json \
  --windows-root factory/native/windows/pilot-text-paint-root-v2/actual-count20-r10-r1 \
  --output .factory-work/text-production-reader-paired-controls-r1
```

Closure arguments are explicit measured files: host package, exact runtime
tree `api-font-37429120-20261011`, compiler, Windows executable, & renderer.
Each is streamed, size bounded, & hash checked against measured plan rows before
copy. Each capture archive keeps observation row files at bare run-local names,
while global plan, compile, runtime, witness, host, tool, & raw files are copied
into same archive with exact role hashes. This preserves row-local references
without cross-run basename substitution. Every file & each capture read budget
is 32 MiB, with duplicate JSON keys, symlink components, & path escapes rejected.
Fresh Mac report validation checks 20+20 rows, all raw file hashes,
80 Mac exit-proof role records, exact source/case/tuple/host joins, & Windows
terminal certificates. Omitting any closure input records a hold instead of
substituting bytes.
Compiler is stored at mandatory `tool/compiler.bin`; host/runtime source trees
are streamed into archive copies, while only measured raw/archive/tool bytes may
use immutable hardlinks. Controls bind every mutation to capture-0's original
canonical archive root, then exercise wrong source, plan hash, retained identity,
terminal kernel wait, lock state, & stream hash faults through production reader
paths, checking each named rejection reason. Shared global observation-list rows
& capture clock/raw-receipt references are resealed together, so named
identity/kernel/lock faults reach production checks rather than generic byte
binding rejection.
Paired-report controls invoke same production verifier for positive admission,
case/tuple/source drift, raw hash, exit role/PID, terminal proof, row identity,
qualification/parity claims, & PNG repeatability. Mutations stay in bounded
fresh ignored output; raw captures remain unchanged.
