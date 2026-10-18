# Tuple 12 cross: the 18 foreground-lock tags re-recorded in Windows Sandbox (19 Oct 2026)

The 18 Windows tags that failed the Mac x20 cross-compare (`../tuple12-mac20-host-r1/RESULT.md`) were re-recorded on the Dell inside Windows Sandbox (`ctl/cross.wsb`: vGPU off, networking off, read-only maps of the tuple 12 BIN, Swift 6.4.0 runtime, sr0o-f1 base and recorder; VC++ runtime DLLs copied from the host). There the fixture is the only app on the desktop, so nothing takes the foreground.

- Pins: FreshOnBridge `87b8cb27…`, renderer `7578cd5d…` (same as tuple 12). UIARecorder `41c94100…`: the pinned `d255a255…` source plus a foreground check and up-to-1 s focus settle before each snapshot, both recorded in the sidecar (`foregroundAtSnapshot`, `focusSettleMs`).
- `run-cross.ps1` copy differs from the repo only in `$rt = 'C:\sb\rt'` (the runtime map).
- Result: 18/18 recorded (rc=0), every snapshot `foregroundAtSnapshot=true`, `focusSettleMs=0`; compare against Mac n<i>: **18/18 pass** (`xcmp-sbx.tar.gz`).
- Combined with the 302 passing on-desktop pairs: **320/320** Mac vs Windows pairs pass for tuple 12.
