# Circle incremental close-marker compile v1

Source-only diagnostic packet. It preserves donor runtime, bridge, renderer, recipe, case and tuple inputs, replacing only `Sources/FactoryProbe/main.swift` with admitted close-marker source `b761a826b249e7b918c6a25af8b3d9bccaced7005d1a35253fb3fd618a576a19`.

`prepare-circle-incremental-v1.py` requires explicit donor package, donor final plan, runtime root, bridge root, donor compile receipt and measured baseline EXE. It verifies every source row by streamed hash/byte count before any copy, stores exact baseline `main.swift` and EXE backups, then emits fresh prebuild plan, manifest and ZIP. Package copy is capped at 32 MiB, each file at 64 MiB, with no overwrite/delete path.

Root-owned compile command after transport:

```powershell
& .\build-circle-incremental-v1.ps1 `
  -PlanPath 'D:\Claude\swiftright\.factory-work\hosts\circle\package\plan-prebuild-v1.json' `
  -PlanSha256 '<measured-plan-sha256>' -Phase prebuild -Attempt 1
```

This command only compiles. It does not open windows, acquire desktop lock, invoke capture, or qualify candidate. Receipt is `prebuild-r1\observation.json`; it records candidate source hash, donor receipt hash, baseline EXE hash, retained compiler handle, direct kernel wait, sealed streams, job memory cap, single job/frontend and native action count zero. Fresh final case/tuple and capture remain held until root binds measured compile output.

Installer is source-only and requires explicit `-StageRoot`; it refuses existing stage, reparse paths, unsafe ZIP entries, hash/byte drift and archive bounds.
