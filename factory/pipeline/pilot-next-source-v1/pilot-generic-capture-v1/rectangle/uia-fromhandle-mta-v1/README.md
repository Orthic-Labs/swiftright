# Rectangle UIA FromHandle MTA successor

Actual Rectangle Count20-r3 reached `stage-before-from-handle.json`, then timed out with empty worker streams. Renderer had already emitted `onReady`, first layout, & first-window-metrics. This packet preserves parent worker deadline 15s & launches one dedicated PowerShell worker with `-MTA`; `AutomationElement.FromHandle` runs synchronously on worker MTA thread. Parent retained-handle timeout remains sole acquisition bound.

Root stages `worker.ps1`, `invoke-worker-mta.ps1`, `worker-contract.json`, exact copied schema/reader/release helpers, then runs source controls with both paths. Parent & worker apartments are recorded separately. No Task.Run, timeout, UIA assertion, renderer, or lifecycle guard is loosened.

Controls require explicit producer schema & sibling `support/cleanup.ps1` + `support/stream-seal.ps1`; invoke `test-uia-fromhandle-mta-controls.ps1 -WorkerPath <staged-worker.ps1> -InvokerPath <staged-invoker.ps1> -SchemaPath <staged-producer-dependencies>\\uia-worker\\schema.ps1`. Controls call `Assert-UiaSnapshotWorkerProof` on one exact v2 fixture, then require rejection for missing parent apartment, worker STA, & legacy proof kind.
