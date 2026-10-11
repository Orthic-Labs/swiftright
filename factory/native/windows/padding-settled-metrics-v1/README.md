# Padding settled metrics v1

Source-only successor of `round1-seeded-hosts-v1/padding-frame`; copied witness/runtime inputs remain byte-bound. This packet adds structured logging without changing graph, measurement, commit, tick, activation-veto, foreground, HWND ownership, DPI, or timing behavior.

`MetricsLogging.swift` emits JSON lines prefixed `FACTORY_METRICS` with monotonic nanoseconds, ISO-8601 UTC, PID, thread, HWND, DPI, scale, phase & source. `Bridge.onReady` records `BridgeWindow.metrics()` plus `factoryOwnedClient`/`GetClientRect` in one callback. First actual `BridgeEvent.kind.windowMetrics` records every raw `BridgeEvent` field, then repeats both metric sources in same callback. First graph commit records ordering marker. Tick/poll data never becomes an event; window close records `held-missing-actual-windowMetrics-event` when no real event arrived.

Loader path is rolling `D:\Claude\swiftright\.factory-work\inputs\renderer\swiftright_render.dll`. External build/launch preflight must verify SHA256 `e280f4a9fd9eca0a7b2657f72f8c322a537cee7b4c85999f6cbf7eb1f39ccc93` before execution; source loader only opens configured path. Native execution, binary capture, qualification, parity & timing claims are outside this source packet. `source-manifest.json` binds copied package files to frozen padding witness hash `0210e1c0ac73ac48528c3303d42f85f9506e99e3eef816e031f20138f705c629`.

Pure source fault controls for review: remove `.windowMetrics` branch → missing-event hold remains; route tick into event logger → violates explicit source/phase gate; replace rolling loader path or renderer hash → source-manifest mismatch; remove `expectedHWND` on first event → ownership guard regression.
