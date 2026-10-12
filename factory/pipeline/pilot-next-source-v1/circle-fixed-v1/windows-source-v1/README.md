# Circle Windows source staging

`prepare-circle-windows-package.py` stages fresh package bytes from Rectangle `plan-final-v3.json` source bindings. Every listed source is regular, bounded, streamed-hashed, copied once into fresh output, & checked against plan hash. `witness.manifest.json` is replaced only by explicit Circle prebuild metadata (`candidate`, `qualification=prebuild`, `case=null`, & exact witness `sourceHash`); donor & replacement hashes remain in lineage. `main.swift` receives one exact witness-call transform plus flushed stderr markers around `Bridge.load`, `Bridge.onReady`, & `Bridge.run`; `Witness.swift` is replaced only by exact Circle witness hash `sha256:01f9fef3ab058a958bebf886191519e0102b05ff6b46acedd0d59a7aa8601f2e`.

`build-circle-owned-v1.ps1` is adapted from reviewed `build-owned-v4.ps1`. It owns `D:\Claude\swiftright\.factory-work\hosts\circle`, requires Circle candidate/plan identity, preserves runtime `37429120`, renderer hash, compiler hash, one compile job, one frontend thread (`--jobs 1 -Xswiftc -num-threads -Xswiftc 1`), 1 GiB compile job cap, & null `case` during prebuild. Receipt records `maxParallelJobs=1` & `maxFrontendThreads=1`. Final phase requires fresh Circle case ID/hash & measured executable hash. It performs compile-only work; root executes it.

`test-circle-windows-controls.py` checks positive transformed source & seven in-memory faults: wrong witness transform, missing startup marker, wrong Circle witness bytes, transformed hash drift, compile command parallelism, missing frontend thread cap, & frontend thread count two. Controls are source-only.

Root command shapes:

```text
factory/.venv/bin/python factory/pipeline/pilot-next-source-v1/circle-fixed-v1/windows-source-v1/prepare-circle-windows-package.py --source-package <rectangle-package> --source-plan <plan-final-v3.json> --circle-witness factory/pipeline/pilot-next-source-v1/circle-fixed-v1/witness.swift --prebuild-manifest <circle-prebuild-manifest.json> --output-package <fresh-circle-package> --output-manifest <fresh-manifest.json>

factory/tools/supervise-job.py --seconds 30 --rss-mib 256 --out .factory-work/circle-windows-source-controls -- factory/.venv/bin/python factory/pipeline/pilot-next-source-v1/circle-fixed-v1/windows-source-v1/test-circle-windows-controls.py <fresh-circle-package> <fresh-manifest.json>
```

No Rectangle evidence is relabeled. Prebuild has no case or host hash; root materializes fresh Circle case only after measured prebuild executable bytes.
