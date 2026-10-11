# Count20 repeat-r4 telemetry overlay

r4 derives repeat-r3 with one bounded telemetry addition in `capture-repeat-r4.ps1`: each native observation records actual `ownedIdentity` (`pid`, `path`, `startedAt`) & measured owned `hwnd`. Initial HWND-ready deadline is 30s diagnostic, matching Count1 r7. All cleanup, release, worker, source, prefix-issuer, native parity, timing, & tuple gates remain unchanged. Source-only; no native/lock/compiler/remote actions.
