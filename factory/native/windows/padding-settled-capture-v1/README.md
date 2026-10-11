# Padding settled capture v1

Prospective source/config rebind for one padding-frame capture, then fresh 20 only after first capture succeeds. It targets freshly compiled host package `D:\Claude\swiftright\.factory-work\hosts\padding-settled\package` & rolling renderer input `D:\Claude\swiftright\.factory-work\inputs\renderer\swiftright_render.dll`.

`prepare-capture.ps1` validates exact `build-settled-r1\observation.json` & `FactoryProbe.exe` paths, supplied hashes, receipt success, source-package plan hash, exact compiled-package plan `82628daf…`, reviewed build preflight hash, renderer hash when receipt carries one, owned output namespace & Count `1|20`. It performs no host launch, lock acquisition, retry, GUI action, or native capture.

`dispatch.ps1` performs fresh namespace & first-run gates, invokes reviewed build `preflight.ps1 -Phase Launch` immediately before each owned child launch through `capture-repeat.ps1`, then runs exactly one or twenty captures. It requires measured receipt/executable hashes & uses admitted v5 cleanup, stream-seal, owned-close & pixel helpers. Count20 first-proof rechecks raw host markers, receipt bytes, closed stream hashes, UIA bytes & all four pixel sample bytes before dispatch. Metrics absence remains diagnostic-only; no synthetic event is accepted.

Metrics absence is diagnostic-only. Logs may report missing real `BridgeEvent.kind.windowMetrics`; capture must preserve raw diagnostics & must never synthesize event from tick/poll. Qualification, parity, timing & provider claims remain held.
