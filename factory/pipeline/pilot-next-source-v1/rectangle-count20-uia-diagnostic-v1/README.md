# Rectangle Count20 UIA diagnostic successor

Source-only successor for C20 worker diagnosis. It preserves existing UIA scalar traversal, retained-handle release, worker exit deadline `15` seconds, raw stream seals, & failure semantics. It adds durable stage files under worker output: config accepted, source pins, UIAutomation assembly, FromHandle, Read-UIA, scalar validation, & UIA publication.

Stage only `worker.ps1` & `worker-contract.json` into fresh producer `dependencies/uia-worker`; preserve existing schema, invoker, cleanup, stream-seal, & final-exit-certificate rows after exact hash admission. Stage `read-uia.ps1` only when its measured hash matches packet hash. Do not change deadline or switch apartment.

Root sequence: hash/admit packet rows, update fresh worker-contract sourceBinding for diagnostic worker hash, run existing C20 preflight, then inspect stage files from `native-01/uia-worker` before any semantic conclusion.
