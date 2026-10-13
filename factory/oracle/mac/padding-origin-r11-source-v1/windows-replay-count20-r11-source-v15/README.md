# Fresh r11 Count20 memory-bound interactive successor v15

v15 replaces only staged `interactive-task-fresh-r11-v10.ps1`; v10 coordinator, dispatch, capture, first-proof, & release logic remain frozen. Before dispatch/native launch, interactive PowerShell assigns itself to a Windows Job Object with `JOB_OBJECT_LIMIT_JOB_MEMORY` (`0x200`) only & exact 1 GiB job limit. `KILL_ON_JOB_CLOSE` is never set. Descendants inherit job membership.

Before `task-result.json`, v15 queries peak job memory, limit flags, job limit, & active process count, waits up to 3 seconds for self-only active count, writes runID, issued metadata hash, parent PID, flags, 1 GiB limit, peak bytes, active count, & `killOnJobClose=false`, then disposes job handle. Any failed proof is rejected & recorded.

Native queries use audited Win32 layouts, require returned byte counts at least struct sizes, require exact `0x200` flags, & reject peak usage above job cap.

Root runs C# compile & controls. Controls prove positive self-only admission, wrong flags rejection, & child inheritance/return to self-only. Controls create only inside fresh ControlRoot & report zero native-window, compiler, remote, & lock actions. No native qualification or parity claim is made by this packet.

Stage v15 interactive script under same overlay beside frozen v10 dispatch/capture files so coordinator's staged basename remains compatible.
