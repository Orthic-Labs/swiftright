# Pilot delivery five: stack layout lifecycle packet

Source-only Count1 packet for existing measured canonical stack-overlay host `stack-lifecycle-next-build-v1`. No compile, renderer, native, lock, SSH, or Git action occurs during prep. Stack UIA now routes through owned MTA worker `source/uia-worker-mta-v1`; parent retains no UIA assembly/type. Worker keeps 15-second acquisition, 5-second stream drain & destination closure, original handle, `FactoryProcessWaitV6`, plus rootRSS supervisor.

Measured joins:

- plan: `D:\Claude\swiftright\.factory-work\hosts\stack-lifecycle\package\plan.json`, SHA256 `9e385e4e50b46c109103cf28b9d8e93be01298fed6c35f2426a1d6a3cdaacef1`
- compile receipt: `...\package\root-build-r1\actual\observation.json`, SHA256 `99a0332b765518e97a8200ef25612fa5c31671037eccdf5504a1fcec091dcae8`
- EXE: `...\package\build-lifecycle-r1\scratch\out\Products\Release-windows-x86_64\FactoryProbe.exe`, SHA256 `abf82f6f133f1d4dd9a48b3075f9af5fe4632db2b9fdc9763114661196bf6c2c`
- renderer SHA256 `e280f4a9fd9eca0a7b2657f72f8c322a537cee7b4c85999f6cbf7eb1f39ccc93`
- runtime commit `37429120e7dd4e060ecf1a58a92ae3a7f4d2b12b`; runtime tree `c9ce2fb6d4e45c4bb452f91895909bc0179d6f9c97a946628a684ff8d163337e`
- source witness `fe91bed344011c7464a18c1ae5ee757a113f6eda6f7f4e0c4cb0258a258d8c35`; lifecycle main `1463629c6136d2dd1bf47b2ff21bfefcc3273f8d606608e3c10c5267062348a1`

Prepare exact typed source graph on Dell, choosing fresh RunRoot & PlanOutput under packet namespace:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File D:\Claude\swiftright\factory\pipeline\pilot-delivery-five-v1\stack-layout\prepare-stack-layout.ps1 `
  -RunRoot D:\Claude\swiftright\factory\pipeline\pilot-delivery-five-v1\stack-layout\native\count1-r1 `
  -LockOwner <coordinator-owner> `
  -PlanOutput D:\Claude\swiftright\factory\pipeline\pilot-delivery-five-v1\stack-layout\source-plan-count1-r1.json
```

Prep emits exact Count1 entry in `entry`, requiring measured receipt `99a0332b...91dcae8` & EXE `abf82f...96bf6c2c`. Root may run emitted entry only under desktop lock. Driver keeps original retained kernel handle, `FactoryProcessWaitV6`, 15-second child exit, 5-second stream drain, & 5-second destination closure. Output is diagnostic lifecycle evidence only: `nativeParity=hold`, `frozenTupleBound=false`.

Custom Layout Windows source remains separate under `custom-layout-host-v1`; same-source Mac packet is under `custom-layout-host-v1/mac-source`, fixed 320x240 no-prompt observables only, with internal scratch & rootRSS evidence. No measured lifecycle EXE/receipt pair is claimed for Mac source.
