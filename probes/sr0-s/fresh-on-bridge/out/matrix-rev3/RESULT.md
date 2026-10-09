# Matrix rev3 — after cc605bf/8f3ffeb, ABI 0.5, Windows

F1–F5, F6 (none/reduced) 3/3 PASS; F6 override-on 2/2 PASS (run 3 lost to a hung SSH call, rerun in rev4).
F7 0/3, F8 2/3, F9 2/3, F9-notasks 0/3. Causes (cc4c93a): F7/F8-run2 evidence from a pre-cc605bf exe;
F9-notasks read live_nodes before the renderer released its tree; F9 run3 pump ended early (renderer, under diagnosis).
