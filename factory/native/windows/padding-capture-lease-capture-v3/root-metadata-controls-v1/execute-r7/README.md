# Count1 execute-r7 telemetry overlay

r7 derives execute-r6 with one bounded telemetry addition in `capture-repeat-r7.ps1`: each native observation records actual `ownedIdentity` (`pid`, `path`, `startedAt`) & measured owned `hwnd`. Initial HWND-ready deadline remains 30s diagnostic. All cleanup, release, worker, source, prefix-issuer, native parity, timing, & tuple gates remain unchanged. Source-only; no native/lock/compiler/remote actions.
