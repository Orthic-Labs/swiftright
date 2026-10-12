# Rectangle Count20 successor admission

This packet is additive source for fresh Rectangle Count20. It does not edit or relabel Count1, legacy padding, or historical archives. Controller performs source-only admission & writes one bounded receipt; root owns any later native dispatch.

`controller-rectangle-count20.ps1` requires:

- fresh `factory-rectangle-count1-proof-v1` with `status=completed-source-bound-observation`, `count=1`, exact case/source/tuple/plan/compile/exe/runtime/renderer/serializer joins;
- native first proof fields: `firstCaptureProof`, `backgroundWindow`, `retainedRendererHandle`, `workerTerminalProof`, `rendererTerminalProof`, `streamsSealed`, `jobMemoryBound`, `lockReleased`; active process count exactly one & peak job memory <= 1 GiB;
- fresh `factory-rectangle-source-inputs-v2`, `count=20`, exact case/source/tuple/plan/compile/exe/runtime/renderer/serializer/helper-manifest fields;
- source-input refs `planRef`, `compileRef`, `tupleRef`, `bindingRef`, `recipeRef`, and `serializerRef` with measured bytes & hashes;
- helper manifest with regular-file byte counts & SHA-256 pins for every UIA, pixel, renderer-close, stream-seal, final-release, memory-job, integration, and serializer source;
- producer `integrationBindingsRef` with at least 23 distinct bounded rows, each relative, regular, byte- & SHA-256-bound under producer root;
- issued metadata with exactly 20 ordered captures, canonical `capture/<32 hex>` & `image/<32 hex>` IDs, exact source/tuple joins;
- fresh plan, compile receipt, renderer, serializer control, output root, and run root. Existing run root rejects admission.

Compile receipt must be measured `factory-rectangle-owned-compile-v1` with `exitCode=0`, `streamsSealed=true`, `streamDrainComplete=true`, `originalHandleRetained=true`, `jobActiveCount=0`, `kernelWait=0`, `ownedExited=true`, and exact source/plan/exe/renderer joins. Source inputs also carry `contextRef`; issued metadata must preserve exact context bytes, plan/compile/exe/renderer/tuple/binding/recipe refs, and ordered IDs.

Config kind is `factory-rectangle-count20-config-v1`, count is `20`, and config file is `count20-config.json` inside fresh `controlRoot`. Hash fields for controller pins are lowercase 64-hex values without `sha256:` prefix. `sourceHash` is preserved in its measured `sha256:<64 hex>` form.

Root source admission after source staging:

```powershell
& .\controller-rectangle-count20.ps1 -Config <fresh-control>\count20-config.json -PreflightOnly
```

After admission receipt passes, root uses `interactive-task-rectangle-repeat.ps1 -Config <fresh-control>\config.json` with fresh Count20 metadata. This successor invokes `dispatch-rectangle-repeat.ps1` & `capture-rectangle-repeat.ps1`; it does not invoke frozen padding drivers. Count1 proof remains mandatory in every stage.

`integration-fresh-rectangle-v1.ps1` is supplied as guard source. It joins measured source inputs, compiler plan/receipt, executable, renderer, serializer, recipe, canonical tuple, binding, case, source hash, and ordered capture IDs. `issue-rectangle-metadata-v1.ps1` emits fresh cryptographic IDs before launch & refuses existing output.

Both Count1 & Count20 interactive tasks write `task-start.json` immediately after self-job admission, before dispatch, with PID, session, job flags/limit, source-input hash, issued hash, and run ID.

Receipt status is source admission only. Root must retain Count1 proof, issue fresh Count20 metadata, run reviewed UIA/pixel/renderer/stream/job/lock controller, archive raw outputs, then pass independent trusted-reader joins before any qualification or parity claim.
