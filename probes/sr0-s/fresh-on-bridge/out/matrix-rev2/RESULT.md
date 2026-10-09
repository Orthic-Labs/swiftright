# Matrix rev2 — fixed runtime (000679e) via fresh-on-bridge (55ebc73), ABI 0.4, Windows

15 configs x 3 runs. **All configs FAIL — regression vs out/matrix (4112d8c: F1 15/15, F2 11/11, 7 configs pass).**

Common failures:
- `commits-accepted` errors=1 in every config: nil-root teardown commit sent after renderer shutdown (`SWR_E_SHUTDOWN (-13) in swr_commit v5`, phase teardown-rejected).
- Remounts: F1 row5-not-torn-down, F2 no-teardown-on-move, F7 no-teardown; F1 caret-follows-typing caret=nil.
- F3 list-0s/list-1s reinsert focus does not match Mac oracle (headless runtime passes).
- F8 toolbar-task-restarts-per-request.
- F9: 3 blocked (bridge post-close pump, no live-node counter in ABI 0.4) + teardown/ledger failures.

Separately the F1 cross-platform compare (probes/sr0-o/f1-cross) fails only on AX tree shape:
BridgeBackend.walk() emits no list/list-item semantics. Fix in progress.
