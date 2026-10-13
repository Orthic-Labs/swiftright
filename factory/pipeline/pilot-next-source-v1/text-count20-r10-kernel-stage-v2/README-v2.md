# Text Count20 r10 kernel-authority source stage

Fresh source graph from frozen Count20 r9 pack. Donor remains immutable. `stage-r10-source-graph.py` copies only explicit `r9-source-files.json` rows, bounds each file at 64 MiB & graph at 256 MiB, rejects reparse/traversal/collisions, substitutes successor cleanup helper at both renderer & UIA support paths, rewrites frozen helper pins, & adds required `-ExpectedExeHash $ExeHash` / `$exeHash` at renderer & UIA cleanup callsites. It emits exact per-file donor/output hashes, `r10-source-graph.json`, `r10-reseal-plan.json`, & optional ZIP.

Successor requires retained-handle native identity (`GetProcessId`, `QueryFullProcessImageNameW`, `GetProcessTimes`) & pinned executable SHA-256 before any kill. `HasExited` never controls cleanup. Renderer 30 s, exit 15 s, stream drain 5 s, & existing lock/background/release gates stay unchanged.

Root-owned staging command after source transport:

```text
factory/.venv/bin/python factory/pipeline/text-count20-r10-kernel-stage-v1/stage-r10-source-graph.py --donor-root <r9-source-pack> --output-root D:\Claude\swiftright\factory\native\windows\.work\text-mta-r11-count20-r10\source-pack --source-list factory/pipeline/text-count20-r10-kernel-stage-v1/r9-source-files.json --helper-source factory/pipeline/owned-child-kernel-cleanup-v2/cleanup-kernel-authority-v2.ps1 --zip-path D:\Claude\swiftright\factory\native\windows\.work\text-mta-r11-count20-r10\source-pack.zip --installer-path D:\Claude\swiftright\factory\native\windows\.work\text-mta-r11-count20-r10\install-count20-r10.ps1 --old-namespace text-mta-r11-count20-r9 --namespace text-mta-r11-count20-r10
```

Stager reseals `admission/source-inputs.json`, candidate tuple/context/binding, `producer/integration-bindings.json`, overlay rows, stage graph, capture plan, preflight, & every transformed source row against fresh emitted bytes. Optional installer generation carries original Count1 certificate bytes/hash unchanged. Root must archive source graph/ZIP/installer hashes, run bounded v2 fake-kernel controls, review generated PowerShell, & only then use fresh Windows namespace. No r9 receipt is relabeled.
