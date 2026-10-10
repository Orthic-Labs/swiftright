# Matrix 07 — SR0 tuple 07, 20 runs per config

Tuple 07: FreshOnBridge 7673A2D5139172D890D3882D332C3C72321F2372D343319A1065CFEEEDFDB960 (source c0fc401: F-family release
gate in SelfTest.swift, unset env = unchanged behaviour), renderer 97CA28E84A58F0D3B44B5A6EAA8D7C912E673A07774123296C958E0D7ECCA26B
(02b3cc0: modal start via posted WM_SWR_MODAL; no ABI change), D:\Claude\sr0-r07\src; preflight ARTIFACT_OK and every run
ARTIFACT_OK. Ran under normal host use, 10 October 2026.

**320/320 PASS.** 16 configurations (F1, F2, F3 x7 variants, F4, F5, F6 + reduced motion, F7, F8, F9), 20/20 each.
319 runs passed on the first attempt. One harness retry: F7 run 14 attempt 1 could not take the foreground (the user's
Pulse window held it: `foreground_failed fg_title=[Pulse]`, `focus[Row 2]=not_foreground`, ended on the timeout waiting for
'row2 focused by AX'; no keys were sent to another app). Attempt 2 passed (18/18). Retries on a foreground failure are the
matrix rule (`scripts/run-matrix.sh` header); both attempts are kept (`F7-none-r14.a1.txt`, `.a2.txt`).

Supersedes `matrix-final` (tuple AA4353CE / 7533963D) for the SR0 tuple. Log: `run-matrix.log`.
