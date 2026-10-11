# Windows copy-cost candidate pair preparation

Preparation only: zero SSH/SCP/Windows/compiler/GUI/Pulse invocations. Fresh packet contains two full52-file runtime packages: current374 &scratch candidate775526e1. Graph.swift is sole byte difference. Every test byte is unchanged;175 source test methods each, original TaskID40ms body/120ms settle &performance2/4/15ms assertions intact.

Proposed execution: one serialized `swift test --package-path <variant/runtime> --scratch-path <variant/scratch> -c release` per current/candidate, in that order. No filter, retry, threshold change or TaskID rewrite. Raw outcomes including nondeterministic TaskID failure remain observations. Root CPU release &source review required before transport/execution.

Runner derives from reviewed direct-SCP TaskID runner, preserved as runner-preimage-taskid.ps1. It uses New-Item -Path, ownedInputRoot, raw native stream copying,900s owned process deadline, exact PID/executable/start-time checks, CIM descendants, source before/after &compiler before/after hash gates. It inventories emitted EXEs/DLLs. Exact compiler bytes reference existing TaskID archive; no redundant tool archive is copied.
