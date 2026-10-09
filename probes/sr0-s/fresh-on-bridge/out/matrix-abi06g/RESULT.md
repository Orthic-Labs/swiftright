# Matrix abi06g — FINAL SR0 tuple, 20 runs per config

Tuple: fixture FreshOnBridge AFE131A1B75C70B0939CD2077C5A5E3E4788FA198E8739FC80EC48F0E8617B0F, renderer
4FB068F0B6C73DE9A5DDE1A536E97EEDD08E2FEA3C0DD8B92FC0E4A78E53298F (D:\Claude\sr0s-bridge06f); every run ARTIFACT_OK.

**318/320 PASS first time; 16 configs.** 14 configs 20/20; F3 lazy-1s 19/20, F7 19/20.
Both misses are infrastructure (no result): F3 lazy-1s r3 — its scheduled task was removed mid-run by another
process on the Dell ("Unregister-ScheduledTask: cannot find the file"); F7 r15 — no output after the task registered.
Reruns on the same tuple (`reruns/`, 3 each): F3 lazy-1s 3/3, F7 3/3 PASS. No product assertion failed.
F8 (fixed by c31f1b5: button AX focus logged separately) 20/20; pre-fix run 3/3 in `f8-check/`.
