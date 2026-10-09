# Matrix abi06c — ABI 0.6 tuple, 20 runs per config (lane R1(b))

Tuple: fixture exe 3593209A49BC540F…D68BA, renderer DLL 777F14C4FF11822B…5441 (862997c); every run printed ARTIFACT_OK.
Configs: F1, F2, F3 list-0s/list-1s/list-3s/vstack-1s/vstack-3s/lazy-1s/lazy-3s, F4, F5, F6 none/reduced, F7, F8, F9
(F6 override-on and F9 notasks are DIAG-only in run-matrix.sh and were not part of this pass).

**316/320 PASS first time.** 12 configs 20/20; F3 list-0s, F3 list-1s, F7, F8 19/20.

| Run | Outcome | Cause |
|---|---|---|
| F3 list-0s r5 | no result | scheduled task ended 0xC000013A (process terminated) at 15:18 while other agents were building on the Dell — infrastructure |
| F3 list-1s r3 | no result | same, 15:29 — infrastructure |
| F7 r14 | no result | a1: foreground taken by a Claude window on the Dell (`foreground_failed fg_title=[Claude]`); a2: its scheduled task vanished mid-wait (Get-ScheduledTask 0x80070002) — infrastructure |
| F8 r9 | FAIL 10/13, timeout waiting for 'row6 deleted by AX' | driver: `delete_near[Row 6]` found no Delete button candidate (dy=MaxDouble), so no AX Invoke was sent — driver UIA lookup race, not a product assertion |

Reruns on a quiet Dell (`reruns/`, 3 runs each): F3 list-0s 3/3, F3 list-1s 3/3, F7 3/3, F8 3/3 PASS.
Open: harden the F8 driver's Delete-button lookup (retry the UIA search before giving up); keep the Dell quiet during matrix runs.
