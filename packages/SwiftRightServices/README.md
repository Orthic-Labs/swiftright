# SwiftRightServices

Swift `EngineService` client for Rust engines that speak the RightKit framed-sidecar wire
envelope. Foundation only, Swift 6 language mode, builds and tests on macOS and Windows.
Implements `docs/architecture.md` section 7 (EngineService row, "Workspace capability
integration") and section 8 (inherited pipes, handshake, version range, correlation, timeouts,
queue bounds, typed errors, shutdown and reconnect). It does not modify RightKit.

## Protocol derivation (read-only, from RightKit source)

Source root: `/Volumes/D/claude/rightkit/crates/`. Line numbers are from that checkout.

**Envelope** (`rightkit-framed-sidecar/src/wire.rs`)

- One `Frame` enum, serde-tagged `"type"` in snake_case (wire.rs:55-57). Field order from serde is `type` first, then fields.
- `hello` (wire.rs:58-69): `engine`, `version`, `contract_version: u32`. Each defaults to empty or 0 when absent. Sent first by the child (wire.rs:59-60).
- `ready` (wire.rs:70-71): the peer "finished its own warm-up".
- `request` (wire.rs:72-81): `id: u64`, `method`, `params` (default null), optional `session_id`, `trace_id`.
- `event` (wire.rs:82-89): optional `id` (progress of a request) or absent (unsolicited); `session_id` optional; `event` payload required.
- `response` (wire.rs:90-99): `id`, `ok`, optional `result`, optional `error`, optional `session_id`.
- `error` (wire.rs:28-36): `code`, `message` (default ""), `retryable` (default false).
- `bye` (wire.rs:100-104): `reason`, the orderly goodbye.
- Parsing is lenient about unknown fields (wire.rs:23). Unknown `type` values are ignored by this client.

**Framing 1, JSON lines (default)** (`rightkit-framed-sidecar/src/lib.rs`)

- Write: `write_json_line` serialises compactly, checks the limit on the body without the newline, writes nothing on overflow, and appends `\n` (lib.rs:317-330).
- Read: `read_json_line_or_oversized` skips blank lines and `\r\n` lines, strips one trailing CR, and enforces `limit` on the content (lib.rs:213-311). The cap is `limit + 1` pending bytes (lib.rs:223). An over-limit line is drained up to its newline, so the stream resynchronises (lib.rs:12-16, 258-285). The drain is bounded by `DEFAULT_MAX_DISCARD` = 64 MiB (lib.rs:89, 277-284).
- Oversized frames carry a 4096-byte head, and `peek_id` reads `"id":<digits>` from it (lib.rs:163-208, 182-184). The client uses that to fail only the request the frame answers (`EngineError.frameTooLarge(requestID:)`). Rust's own `Oversized::id` (lib.rs:182-184) relies on the same rule, so engines must emit `type` and `id` before large fields.

**Framing 2, length-prefixed (binary-safe alternative)** (`rightkit-framed-sidecar/src/length_prefixed.rs`)

- 4-byte big-endian length, then UTF-8 JSON (module doc, length_prefixed.rs:1-4).
- Write rejects an empty body, a body over the limit, and lengths above `u32::MAX` (length_prefixed.rs:35-55; prefix written at :50).
- Read rejects a zero length as `InvalidData` (length_prefixed.rs:74-79), and a length above the limit as `TooLarge` before the body is read (:80-82). Both are fatal: there is no resynchronisation (module doc, :6-10). The client treats them as `malformedFrame` and `frameTooLarge` and tears the session down.

**Handshake** (derived; no normative spec in the crates)

1. Engine writes `hello` first (wire.rs:59-60).
2. Client checks `contract_version` against `supportedContractVersions`. Outside the range it fails with `incompatibleProtocol` and stops the engine.
3. Engine writes `ready` after warm-up (wire.rs:70). The client accepts requests only after `ready`.
4. Frames other than `hello`/`ready` before `ready` are `handshakeFailed`.

**Requests, responses, events**

- Correlation is by `request.id` (a monotonically increasing `u64` from 1 in this client) and `response.id`. Responses may arrive in any order.
- `event.id` equal to a pending request makes a `.progress` event. Absent id makes `.unsolicited`.
- A response with `ok: false` maps to `EngineError.remote(code:message:retryable:)` from `response.error` (wire.rs:28-36, 90-99).

**Cancellation**: the `Frame` enum has no cancel variant (wire.rs:58-105). A grep of `rightkit-framed-sidecar/src` and `rightkit-process/src` for "cancel" returns nothing. Caller cancellation therefore completes locally with `EngineError.cancelled`, and nothing is sent to the engine. A late response is counted in `lateResponseCount`.

## API

```swift
let client = EngineClient(configuration: EngineConfiguration(
    executable: engineURL, arguments: ["--serve"], supportedContractVersions: 1...1))
let hello = try await client.start()                  // optional; requests auto-start
let value = try await client.request("echo", params: .string("x"), timeout: .seconds(5))
let typed: Reply = try await client.call("transcribe", params: Request(...))   // Codable helpers
for await event in client.events { ... }              // connected, progress, unsolicited, disconnected
let outcome = await client.shutdown(grace: .seconds(3))  // bye, close stdin, then terminate
```

- `EngineConfiguration`: framing (`.jsonLines` default, or `.lengthPrefixed`), contract range, `maxFrameBytes` (16 MiB), `maxInFlightRequests` (64), `maxOutboundFrames` (256), `maxEventBuffer` (1024, newest kept), `handshakeTimeout` (10 s), `readyTimeout` (60 s), `defaultRequestTimeout` (30 s), `shutdownGrace` (5 s), `reconnect` (`.disabled` by default), `stderrTailBytes` (8 KiB), optional `sessionID` and `traceID` on every request.
- `ReconnectPolicy(maxRestarts:window:backoff:)`: after a crash, the next request restarts the engine after `backoff`, if fewer than `maxRestarts` restarts happened within `window`. Restart is lazy. Without it, requests keep failing with the crash error.
- `EngineError` (typed): `launchFailed`, `handshakeTimeout(stage:after:)`, `handshakeFailed`, `incompatibleProtocol(engine:received:supported:)`, `notRunning`, `queueOverflow(limit:scope:)` (`inFlightRequests` or `outboundFrames`), `requestTimeout(method:id:after:)`, `cancelled(method:id:)`, `remote(code:message:retryable:)`, `frameTooLarge(limit:requestID:)`, `malformedFrame`, `protocolViolation`, `engineExited(status:stderrTail:)`, `payloadMapping(method:underlying:)`.
- `EngineJSON`: `Sendable`, `Equatable` JSON value. Integers stay exact (`Int64`), and `Codable` payload helpers map structs in and out.
- `EngineShutdownOutcome`: `.exited(status:)`, `.terminated(status:)` (grace expired), `.notRunning`.

## Binary data

Frames carry JSON bodies only. The protocol has no binary payload type (wire.rs enum has none), and length-prefixed framing still carries JSON. `Data` fields in `Codable` payloads encode as base64, so the payload helpers must not carry bulk data. Architecture section 8 says bulk data stays inside the engine. A bulk transfer path needs a side channel (shared memory, a named file or pipe), which the protocol does not define. This is listed under gaps.

## Tests

`swift test` runs 29 tests: 11 codec tests (no process) and 18 process tests against `FakeEngine`, an independent Swift executable that speaks the same envelope without importing this library. `RealEngineTests` (2) run against a real Rust engine when `SWR_REAL_ENGINE` is set and are skipped otherwise. See "Real engine check".

- Handshake over JSON lines and length-prefixed framing. Version mismatch is rejected with `incompatibleProtocol`. A silent engine hits `handshakeTimeout`.
- 40 concurrent requests with out-of-order responses, each correlated to its own caller.
- Per-request timeout, with the late response dropped. Caller cancellation returns `cancelled`.
- In-flight bound returns `queueOverflow` without killing the engine.
- Typed remote error. Progress and unsolicited events on the event stream.
- Oversized response fails only its own request (`frameTooLarge` with id), and the stream resyncs.
- Crash mid-request returns `engineExited(status: 3)`. Reconnect restarts the engine. Without reconnect the crash error persists.
- Graceful shutdown (`exited(0)`). A stubborn engine is terminated after the grace period. A request before `start()` auto-starts. Typed `call` round trip.

Results: macOS (arm64, Swift 6.4, `swift test`) 29/29 passing on repeated runs. Windows (x86_64-unknown-windows-msvc, Swift 6.4 runtime) 29/29 passing, via `scripts/run-tests.ps1`. The only warnings in the Windows log come from the toolchain's WinSDK module, none from this package.

Run on Windows: `scripts/sync-to-win.sh packages/SwiftRightServices 'D:\Claude\sr3-services'`, then `win "powershell -NoProfile -ExecutionPolicy Bypass -File D:\Claude\sr3-services\scripts\run-tests.ps1"`. The script sets the Swift runtime path, runs `swift build` and `swift test`, and writes `swift-test-windows.log` (UTF-16, because of `Tee-Object`).

## Implementation notes

- Pipes are read on dedicated threads with `FileHandle.availableData`. `read(upToCount:)` waits for the full count or EOF, which stalls handshakes.
- Writes go through a serial dispatch queue per session, so frames keep their order, and writes stay off the actor. The `outboundFrames` bound counts frames queued and not yet written.
- The reader thread waits for the exit status before ending the stream, so crash errors carry the exit code.
- `SIGPIPE` is ignored on Unix so a dead engine's stdin returns an error instead of killing the host.

## Gaps to report to RightKit owners

Owners per `docs/architecture.md` section 7 and `probes/sr0-d/owner-map/RESULT.md`: `rightkit-framed-sidecar` (framed-sidecar), `rightkit-process` (owned-processes), `rightkit-service` (local-services).

1. **No handshake version negotiation.** `hello` carries one `contract_version: u32` (wire.rs:62-68). There is no min/max range, no negotiation reply, and no rule for which version wins. This client applies its own range policy. The owner should define the contract range and rejection frame.
2. **No cancel frame.** The `Frame` enum has no cancel variant (wire.rs:58-105), and "cancel" appears nowhere in `rightkit-framed-sidecar` or `rightkit-process` source. Cancelled work keeps running in the engine. A `cancel` frame or a documented cancel method is needed.
3. **No binary payload type.** Bodies are always JSON, including length-prefixed (length_prefixed.rs:1-4). Bulk data needs a defined side channel.
4. **`ready` is not normative, and the shipped Rust host does not send it.** It appears only as a doc comment (wire.rs:70). This client requires it by default (`requireReady = true`). The real engine check below shows `rightkit-jobs` treats `hello` as ready and never sends `ready`, so the default fails against it. The owner must decide whether `ready` is mandatory. Until then, consumers of real engines set `requireReady = false`.
5. **No process-tree termination in Foundation.** `Process.terminate()` stops only the direct child. `rightkit-process` provides kill-on-close and process-tree handling (`windows_job.rs:23`, `owned.rs:197-210`, `unix_containment`), and this package does not use it. A Swift adapter or C ABI over `OwnedChild` is needed. Until then, Windows grandchildren can survive shutdown.
6. **Environment allowlist not applied.** `rightkit-process` offers `DEFAULT_ENV_ALLOWLIST` (owned.rs:346) and `env_allowlist` (owned.rs:161). This client inherits the parent environment unless `environment` is set.
7. **No Swift or C ABI for any of these.** `rightkit-framed-sidecar` 0.1.0 and `rightkit-process` 0.3.1 match the registry and are Rust-only (owner-map RESULT.md, EngineService rows). No `rightkit-service` Swift client exists for `service.json` discovery or the current-user socket. Architecture section 8 allows inherited pipes, so this package uses pipes only.
8. **Restart and health policy not reused.** `rightkit-process` has `RestartPolicy` (`restart.rs:11`), `HealthPolicy` (`health.rs`) and `StderrTail` (`stderr_tail.rs:13`). This client has its own restart budget and stderr tail. I did not evaluate whether the RightKit policies could be exposed to Swift.
9. **Oversized-frame identity depends on field order.** Recovering the request id from an oversized frame requires `"id"` within the first 4096 bytes (lib.rs:196-208). serde emits `type` then `id` (wire.rs:55-57), so this holds for Rust engines. The contract should state it.
10. **No published Swift version.** This package is not published and has no version pin. It needs one before SwiftRight depends on it.

## Not done

- Not committed or pushed. No branch created.
- Unix-domain socket and named-pipe transports (architecture section 8) are not implemented. Only inherited stdin/stdout pipes are.
- Event buffering drops the oldest events when the consumer lags (`bufferingNewest`). RightKit does not define a policy.

## Real engine check

Integration check of `EngineClient` against a real Rust engine built through RightKit. It is opt-in and headless.

**Engine**

- Binary: `rightkit-jobs` example `engine_fixture` (`crates/rightkit-jobs/examples/engine_fixture.rs`, 130 lines). It is RightKit's scriptable test engine for supervisor tests, not a product engine. It is the only standalone binary in the workspace that speaks the framed-sidecar envelope. The record helper is Windows-only capture, and the shell example is a Tauri GUI app.
- Repo: `/Volumes/D/claude/rightkit`, HEAD `9f3ec2d48689fb7a7c73d269fe67490f0874369e`. The fixture and the crates it links (`rightkit-jobs` 0.2.6, `rightkit-framed-sidecar` 0.1.0, `rightkit-service` 0.1.3, `rightkit-process`, `rightkit-db`, `rightkit-fs`) had no uncommitted changes when built. The repo as a whole was dirty with other owners' work, which was left untouched.
- Build: `rightkit cargo build --release -p rightkit-jobs --example engine_fixture`, one run, 14.5 s, through RightKit. The output is in RightKit's managed target (`/Volumes/D/.rightkit-managed/rightkit-build-control/ws/bbf2da541b23/g/002/target/aarch64-apple-darwin/release/examples/engine_fixture`). SHA-256 `86f2a40b3cb7c3dd411be3ea9d6d2a1ca9fe7b0f384fe87b21f467627d50be3a`. Host: Mac arm64, Swift 6.4.
- Wire behavior, observed by piping raw requests: `hello` `{"contract_version":1,"engine":"fixture","version":"1.0"}`, then responses. No `ready` frame is sent.

**Run**

```sh
SWR_REAL_ENGINE=<path-to-engine_fixture> swift test --filter RealEngineTests
SWR_REAL_ENGINE=<path-to-engine_fixture> swift test    # full suite
```

**Results (Mac, arm64, Swift 6.4)**

| Test | Result |
|---|---|
| `testStrictHandshakeTimesOutWaitingForReadyFromRealEngine` (default `requireReady = true`) | passed. `start()` throws `handshakeTimeout(stage: "ready", after: 2s)`, as the protocol requires. |
| `testHandshakeRequestsErrorAndShutdownAgainstRealEngine` (`requireReady = false`) | passed. Covers `hello` equal to `{fixture, 1.0, 1}`, `ping` with `{pong: true}`, a nested `echo` round trip (integer, escaped string, array, float, null), a typed remote error `unknown_method` with `retryable: false`, a second request after the error, and `shutdown()` returning `.exited(status: 0)`. |

Full suite with `SWR_REAL_ENGINE` set: 31 of 31 pass (11 codec, 18 FakeEngine, 2 real). Without it: 29 pass and 2 are skipped. Before this check the baseline was 29 of 29.

**Client change made for this check**

- `EngineConfiguration.requireReady: Bool`, default `true`. When `false`, `hello` alone completes the handshake. The default behavior is unchanged. The `ready` completion code moved into `EngineClient.completeHandshake()`, which both paths share.
- Reason: a real shipped engine never sends `ready`, so the strict default cannot reach a request against it. This is a protocol decision, which is why the default stays strict and the choice is exposed as an option. See gap 4.

**Findings**

- The strict handshake fails cleanly with a typed timeout (no hang), so the failure mode is safe.
- `shutdown()` against the real engine reports `.exited(status: 0)`. The fixture answers the `bye` frame with a null-id `unknown_method` response (checked by a raw pipe). The client still reached a clean exit, so that stray response did not break shutdown.
- The real engine's request, error, and shutdown behavior matches the client's wire model. No framing or correlation mismatch was seen.
- Not exercised: oversized frames, length-prefixed framing (the fixture only speaks JSON lines), crash or restart paths, and progress events (`notify` is available in the fixture and was not wired into the test).

## Default handshake decision (2026-10-09)

`requireReady` defaults to `false`: the shipped RightKit host (`rightkit-jobs`) treats `hello` as ready and never sends `ready` (only a doc comment in `wire.rs`), so a strict default would fail against every real engine. Strict mode stays available for engines that do send `ready`. Reported to the RightKit owner as gap 4.
