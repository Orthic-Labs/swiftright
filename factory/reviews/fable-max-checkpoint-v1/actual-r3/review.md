**Verdict: at-risk** (unchanged from R2). Progress is real and advances block 1, but only Rectangle fill has Windows paired evidence. Rounded stroke, star.fill, Tinos Text and custom Layout have none. Zero complete blocks.

**What advanced**
- Rectangle fill paired20 is genuine: 20/20 exact 800×600 RGBA with source/case/runtime/renderer/receipt joins, `qualified:false`, semantic and timing honestly pending (`paired-comparison-v1.json:330-360`). The reader reads actual client/DPI (`compare-centered-paired20-v1.py:274`), requires `nativeParity:"hold"` (:260) and treats the 15 s deadline as lifecycle only (:282). Coordinator shows lock released and no cleanup errors (`coordinator.json:15-27`).

**Correctness findings**
1. Weak negative controls. `compare-centered-paired20-v1.py:154-183` mutate a local dict against a local `require_equal`, never `verify_mac_run`/`verify_windows_run`. Only pixel-diff (:185-191) exercises production code. "7 controls passed" overstates. Comparator v2 used real artifact faults (`rectangle-centered-full-viewport-comparison-r1.json:20-56`); match that before production-reader admission.
2. Mislabeled hashes. `macImageSha256`/`windowsPrintWindowSha256` are decoded-RGBA hashes (:134-140), not file hashes. The PNG hashes verified at :89 and :277 are unrecorded, so the report cannot be audited against `native.pixels.json:15` or `manifest.json:7`. `.convert("RGBA")` at :139 is undisclosed mode normalisation; record source modes.
3. Rendered is not displayed. `native.pixels.json:26-80` shows every occlusion-grid point owned by pid 67282, `unoccludedSampled:false`, screen repeats unstable (:155-156). Evidence is PrintWindow under full occlusion. "Working on Windows" still needs one unoccluded displayed observation per block, under the existing displayed-workload hold.
4. Semantic channel structurally stuck: Mac `accessibilityAttempted=false` on all 20 runs. For a shape-only case, define the obligation explicitly (both hosts expose no element for the fill) and recapture Mac20 with AX attempted. Otherwise Rectangle never leaves diagnostic.
5. Custom Layout: the summary says light/centered prep is pending, but `plan.json:116-118,201-205,226` already declares light, source-ready, tuple `light-centered-r11`. The pending item is the Windows build plus native Count1 (:223). No light Mac20 exists yet; R2 records Count1 only.
6. Rounded: packet only (`README.md:24`). Confirm the existing Mac20 is the full-client centered archive kind before pairing; otherwise capture fresh Mac20.
7. Wrappers: centering is a declared host correction on both sides (`plan.json:217-223`). Acceptable, but the runtime root-placement gap behind the 0,0 result stays unfixed under SR0 hold. Do not add theme or other adapters without the same declaration.

**star.fill / MSVC**
- `compile-observation.json:9,15,30-34`: compiler exit 0, streams drained but unsealed, hashes null, "job not quiescent". Cause: `produce-provider-raster-v1.ps1:119` throws before sealing at :120-121, discarding evidence of a successful compile.
- `Require-VsCeipOptOut` (:31-50) is an invented global blocker: HKLM-only, fail-closed on a host preference. `VSCMD_SKIP_SENDTELEMETRY` (:72,:78) silences only vsdevcmd's PowerShell sender, not vctip.
- Route, without global authority: (a) seal and hash streams immediately after original exit 0 and drain; (b) enumerate job PIDs (`ProviderOwnedJobProcess.cs:231`), positively identify the single lingering PID as vctip.exe by image path under the VC tools directory, terminate that owned helper via its own handle, wait, record `ownedHelperStopped{pid,path,exit}` distinctly; (c) re-read active==0, then mark quiescent. Keep `TerminateJobObject(124)` (:124) as separate forced cleanup. Record registry state as read-only diagnostic. No registry mutation, no renaming, no r3 acceptance. Segoe E735 remains a measured candidate; no SF Symbol parity.

**Resources and holds**
Jobs terminal: Count20 lock released, vctip cleanup active 0. Codex renderer at 1.86 GiB with 1.12 GiB swap is unowned pressure; keep 1 GiB hard jobs. Many untracked spike artifacts in git status need archive or ignore, not review. All table holds (`sr0-sr1-running-holds.md:11-24`) remain real; none closes.

**Next three**
1. Rounded stroke: repaired native preparer, centered final build, Count1 full-client compare, then Count20 against a full-client Mac20. Completes block 1 evidence.
2. Rectangle: fix reader controls and labels, define the shape semantic obligation, Mac20 with AX attempted, then production-reader admission.
3. star.fill compile r4 with reordered sealing and owned-vctip stop, one producer run, then E735-versus-SF geometry/coverage gap measurement. Custom Layout Windows build plus native Count1 on r11.

Next action: root runs the rounded-stroke centered preflight, build and Count1 while the source owner reorders stream sealing and replaces the registry gate.
