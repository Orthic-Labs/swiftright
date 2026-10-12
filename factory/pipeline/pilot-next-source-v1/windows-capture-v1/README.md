# Rectangle Count1 Windows capture source

This packet is prospective source for one fresh Rectangle host capture. It keeps UIA, pixel, retained renderer handle, owned close, stream sealing, terminal worker release, CAS lock, background placement, and 1 GiB self-job checks from reviewed v16/v15 sources. It does not use padding first-proof or any historical candidate.

Root must stage exact measured inputs before invocation. `source-inputs.json` supplied by root must be a regular fresh file with SHA-256 pin and this shape:

```json
{
  "kind": "factory-rectangle-source-inputs-v1",
  "count": 1,
  "caseID": "<fresh measured case id>",
  "caseHash": "<64 lowercase hex>",
  "sourceHash": "sha256:<64 lowercase hex>",
  "tupleID": "<fresh measured tuple id>",
  "tupleHash": "<64 lowercase hex>",
  "capturePlanPath": "<absolute path>",
  "capturePlanHash": "<64 lowercase hex>",
  "compiledHostPackagePath": "<absolute path>",
  "compileReceiptPath": "<absolute path>",
  "compileReceiptHash": "<64 lowercase hex>",
  "exeHash": "<64 lowercase hex>",
  "exeRef": {"path": "<absolute executable path>", "sha256": "sha256:<64 lowercase hex>", "bytes": 0},
  "planHash": "<64 lowercase hex>",
  "rendererPath": "<absolute path>",
  "rendererSha256": "<64 lowercase hex>",
  "rendererRef": {"path": "<absolute renderer path>", "sha256": "sha256:<64 lowercase hex>", "bytes": 0},
  "buildPreflightPath": "<absolute path>",
  "buildPreflightHash": "<64 lowercase hex>",
  "runtimeSourceCommit": "<measured commit>",
  "serializerControlSha256": "<64 lowercase hex>",
  "contextRef": {"path": "<absolute context path>", "sha256": "sha256:<64 lowercase hex>", "bytes": 0}
  ,"planRef": {"path": "<absolute plan path>", "sha256": "sha256:<64 lowercase hex>", "bytes": 0}
  ,"compileRef": {"path": "<absolute receipt path>", "sha256": "sha256:<64 lowercase hex>", "bytes": 0}
  ,"tupleRef": {"path": "<absolute tuple path>", "sha256": "sha256:<64 lowercase hex>", "bytes": 0}
  ,"bindingRef": {"path": "<absolute binding path>", "sha256": "sha256:<64 lowercase hex>", "bytes": 0}
  ,"bindingHash": "<64 lowercase hex>"
  ,"recipeRef": {"path": "<absolute recipe path>", "sha256": "sha256:<64 lowercase hex>", "bytes": 0}
  ,"recipeHash": "<64 lowercase hex>"
  ,"serializerRef": {"path": "<absolute serializer path>", "sha256": "sha256:<64 lowercase hex>", "bytes": 0}
  ,"integrationBindingsHash": "<64 lowercase hex>"
  ,"integrationBindingsRef": {"path": "<absolute producer integration-bindings.json>", "sha256": "sha256:<64 lowercase hex>", "bytes": 0}
}
```

`issued-metadata.json` must be freshly issued for this Rectangle case, contain exactly one capture, use `capture/<32 hex>` & `image/<32 hex>` IDs, and match source, tuple, compile, and run joins. Root supplies integration guard, serializer control, package, paths, and measured hashes. Preflight writes only control receipt; native launch occurs only after root stages & reviews every value.

Suggested coordinator config fields are `package`, `producerRoot`, `admissionRoot`, `controlRoot`, `outputRoot`, `runRoot`, `sourceInputsPath`, `sourceInputsHash`, `integrationGuardPath`, `integrationGuardHash`, `compileReceiptHash`, `exeHash`, `serializerControlSha256`, `issuedMetadataPath`, `issuedMetadataHash`, `owner`, and `count: 1`.

Required root sequence:

1. Stage fresh source inputs, plan, package, compile receipt, executable, renderer, preflight, integration guard, and issued metadata; verify every supplied hash & byte count.
2. Run `interactive-task-rectangle-single.ps1 -Config <fresh control config>` through root's bounded Windows supervisor in preflight mode. Confirm `capture-preflight.json` reports zero native, GUI, compiler, remote, and lock actions.
3. Run same config only after fresh lock ownership & desktop-session checks. Archive raw output before any normalization. Keep candidate, parity, and qualification held until independent reader joins all receipts.

No source in this packet may relabel historical padding evidence or synthesize Rectangle observations.
