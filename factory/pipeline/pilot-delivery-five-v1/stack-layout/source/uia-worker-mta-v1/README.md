# Stack UIA MTA worker

`capture-stack-lifecycle-count1.ps1` keeps parent UIA-free. `Invoke-StackUiaSnapshotWorker` launches hidden PowerShell with `-MTA`; worker alone loads UIAutomation assemblies, resolves `FromHandle`, performs bounded `Read-UIA`, validates scalar JSON & returns worker proof.

Worker output stays under stack packet `native/`. Existing renderer ownership guard runs during 15-second worker acquisition. Existing stack `cleanup-v3.ps1` supplies `FactoryProcessWaitV6`; raw streams drain 5 seconds & destinations close 5 seconds. Original retained worker handle feeds final release certificate. `root-rss-supervisor.ps1` records coordinator RSS before/after worker.

Contract is source-pinned in `worker-contract.json`; no runtime, renderer, ABI, Rectangle source, or native behavior changes.

`test-stack-uia-mta-controls.ps1` reuses production schema/cleanup controls & rejects retained-handle identity loss, false kernel exit, wrong MTA config, & mutated source-contract bytes without launching worker.
