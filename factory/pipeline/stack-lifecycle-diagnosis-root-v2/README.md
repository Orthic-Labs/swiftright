# Stack lifecycle diagnosis v2

This packet adds one host-side evidence join for stack/custom-layout startup. It does not modify renderer, Bridge, runtime, ABI, UIA worker, or lock code.

## Concrete gap

`factory/pipeline/sr0-display-selfjob-v4/diagnosis/README.md` proves only that failed host reached renderer DPI setup (`render/swiftright-render/src/view.rs:1612`) after `Bridge.load`; it has no bounded marker for `loop-ready`, first window metrics, or callback publication. `bridge-load-trace-v1.swift` proposes those markers, while `factory/pipeline/pilot-next-source-v1/rectangle-count20-uia-diagnostic-v1/worker.ps1` already records UIA `before/after-from-handle` and `before/after-read-uia`. No source currently joins those two clocks by exact run ID, host PID/start time, or pinned source hashes.

The paired review remains observational: `factory/pipeline/paired-stack-custom-actual-v4/independent-review/findings-v1.json` records stack `+` on both providers, custom UIA child count `0`, and no cross-provider or lifecycle claim. This packet preserves that boundary.

## Smallest additive repair

Fresh host wrapper writes one scalar `FACTORY_STACK_PHASE_V2` line per phase to stderr, using one run ID, host PID, UTC start, monotonic milliseconds, QPC, session, and pinned source hashes. Existing UIA worker writes equivalent phase fields into its already-bounded stage receipt. No phase is inferred from missing output.

`phase-contract-v2.json` defines required fields and order. `validate-phase-receipt-v2.ps1` performs bounded source-bound validation and joins host/worker receipts. It emits `loader-or-abi`, `gpui-before-window`, `window-callback-publication`, `uia-window-exposure`, `uia-content`, or `evidence-incomplete`; it never emits qualification, parity, or golden status.

## Root-run control

After root transport admission, stage one fresh host wrapper with unchanged hashes from archived diagnosis, run one stack case & one custom case, then pass exact host/worker receipt paths:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File `
  .\factory\pipeline\stack-lifecycle-diagnosis-root-v2\validate-phase-receipt-v2.ps1 `
  -HostReceipt .\<bounded-output>\host-phase.json `
  -WorkerReceipt .\<bounded-output>\worker-observation.json `
  -OutputPath .\<bounded-output>\lifecycle-join.json
```

The first control mutations must be run against copied receipts: stale `runId`, foreign `host.pid`, reordered phase, duplicate phase, decreasing monotonic/QPC value, source-hash drift, child phase after parent terminal, and missing UIA phase. Every mutation must remain `evidence-incomplete` or rejected; none may become qualified.

## Existing source pins

Archived failed-host pins remain evidence only: host source `5a41b5d411509e5e9d293cc56943c7270394c176ba863b0533921ac22a87792d`, executable `62aa7d5b9a5b9001d697822d26b2d102d8934de1de4a02103f810e756f71af66`, renderer `e280f4a9fd9eca0a7b2657f72f8c322a537cee7b4c85999f6cbf7eb1f39ccc93`, Bridge Loader `10144b99141508043ca2ab86d72ac444e89d770193753115cc68e683aaa6f768`, Bridge `d0768273e76a0ec3a6b71e8e8ac6a0a359be7ab6051e1e77ac40d4670c7118b8`, runtime `c9ce2fb6d4e45c4bb452f91895909bc0179d6f9c97a946628a684ff8d163337e`.
