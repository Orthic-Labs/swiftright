# Pilot native build preparation

`prepare-pilot-five-compile-v1.py` accepts `image-v2` & `custom-layout-v2` while retaining existing `image` output paths & source packet. New hosts use native SwiftPM builder argv:

```text
build --build-system native -v --package-path <stage>\package --scratch-path <stage>\package\build-bounded-r2\scratch --jobs 1 -Xswiftc -j1 -Xswiftc -num-threads -Xswiftc 1 -c release -Xlinker /MANIFEST:EMBED -Xlinker <Common-Controls manifest> -Xlinker /SUBSYSTEM:WINDOWS -Xlinker /ENTRY:mainCRTStartup
```

Native product path is fixed to `x86_64-unknown-windows-msvc\release\FactoryProbe.exe`. Root must run generated staging/build request only after copying packet into fresh Windows stage under `.factory-work\hosts\image-v2\package`; no overwrite is admitted.

Generated source stages copy retained-handle helper from
`root-execution/Sr0OwnedJobProcess.cs`; they do not fetch live Rectangle trees.
ZIP/cache scratch is kept under ignored repo path
`.factory-work/pilot-delivery-five-v1/`; root copies printed ZIP into matching
Windows `.factory-work` path before staging. New-host generation inserts native
flags before package path. Historical Rounded prebuild may retain package-first
argv; finalizer records this exact ordering defect in request metadata & refuses
any other token order.

After root archives actual prebuild receipt under `root-execution/image-v2-compile-r1/actual-prebuild-r1/observation.json`, with `plan-prebuild-v4.json` & `build-owned-pilot-v1.ps1` present, run through pinned factory environment:

```text
factory/.venv/bin/python factory/pipeline/pilot-delivery-five-v1/root-execution/prepare-pilot-final-build-v1.py --host image-v2 --attempt 1
factory/.venv/bin/python factory/pipeline/pilot-delivery-five-v1/root-execution/prepare-pilot-final-build-v1.py --host custom-layout-v2 --attempt 1
```

Finalizer verifies exact packet case identity, source bindings, native argv, package/scratch paths, retained original process handle, exit code, sealed streams, active job count 0, kernel wait 0, cleanup active count 0, exact product path, & hashes. It writes `plan-final-v4.json`, `build-owned-final-v1.ps1`, `final-builder-request.json`, & `finalization.json`; root must execute/archive final actual before Count1/Count20 capture.

Remote final entry supports a disposable `-PreflightOnly` pass: it copies final
inputs temporarily, removes them in `finally`, & never creates archive or final
receipt. A later real invocation alone creates prebuild archive, installs final
inputs, & writes final receipt.
