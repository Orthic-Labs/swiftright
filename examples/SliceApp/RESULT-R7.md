# R7 result: Mac clean environment (2026-10-09)

Verdict: **R7 NOT PASSED.** The quarantine/Gatekeeper checks are blocked by the VM base image; the update-mechanics checks ran and passed on the non-quarantined path.

Environment: Tart clone of `sliceapp-base` (macOS 26.6.2 25G83, arm64), run `--no-graphics --vnc-experimental` (no host window; the display device was needed to look at the Gatekeeper dialog), driven over SSH plus the guest's own Screen Sharing from the host. Clone deleted at the end. DMGs from R3, hashes verified in the guest: 0.1.0 `81742a7c...64b661`, 0.1.1 `c75155b4...071a8a`. Logs/screenshots: `/Volumes/D/scratch/swiftright/sr0-artifacts/mac/r7/`.

## Blocker: base image Gatekeeper is "App Store only"

`spctl --status --verbose` in `sliceapp-base` reports `assessments enabled / developer id disabled` (System Settings > Privacy & Security > "Allow applications from: App Store"). Every Developer ID app is refused. Evidence: `g1-quarantined-launch-offline.png` ("SliceApp can't be opened because it was not downloaded from the App Store"), `s1-install-assess.log` (`spctl -a` rejects even the notarized, stapled DMG, which the host accepts, and `syspolicy_check distribution` passes the DMG). The earlier `spctl --global-enable` in the base does not enable Developer ID. Changing it needs the admin password in a system auth dialog (the SecAssessmentUpdate route returns errSecAuthFailed; SystemPolicy DB is SIP-protected), which an agent must not type. **Adrian action (one time, in `sliceapp-base`):** set "Allow applications from" to "App Store & Known Developers", then re-run R7.

## Checks

| Check | Result | Evidence |
|---|---|---|
| Quarantined delivery, mount, copy, `spctl -a -vv` | **BLOCKED** (invalid under the base setting; quarantine xattr and DMG-to-app inheritance did work) | s1, s2 |
| `syspolicy_check distribution` | DMG PASS; .app **FAIL: "Notary Ticket Missing", Fatal** (online and offline) | s1, u7 |
| First launch under Gatekeeper (quarantined) | **BLOCKED**: process held at `_dyld_start`, never ran | s3, s4, s4b |
| Install (install-app, non-quarantined) | PASS, window visible, `rows.json` seeded, 5 rows | u1 |
| Offline first launch | **Gatekeeper outcome NOT OBSERVABLE** (same block). Non-quarantined offline launch PASS (default routes removed, apple.com/ocsp unreachable): app needs no network, data unchanged | u3 |
| Upgrade 0.1.0 -> 0.1.1 (install-app, app running) | PASS: app quit, swapped, `rows.json` sha unchanged, 0.1.1 reads 6 rows and writes 8 | u4 |
| Rollback 0.1.1 -> 0.1.0 | PASS: 0.1.0 shows all 8 rows written by 0.1.1, no error text | u5 |
| Corrupt update rejection | PASS: byte-flipped DMG refused at attach (installed bundle untouched); byte-flipped Mach-O fails `codesign --verify` and the kernel kills it (exit 137) | u6 |
| Interrupted update (real) | PASS for ditto kill (old bundle restored, verifies, recovery OK). Installer kill: **dest ABSENT, old bundle left in ~/.Trash, DMG left mounted** (RightKit non-atomic swap, reported not fixed) | interrupt-run3 |
| Data kept after uninstall | PASS: app moved to Trash, `rows.json` sha unchanged, 8 rows | u7 |

## Offline first launch vs the missing .app staple

Not decided. The only evidence is static: `syspolicy_check` calls the unstapled .app a Fatal "Notary Ticket Missing" even though it passes for the stapled DMG, so an offline Gatekeeper ticket lookup for the copied app has nothing to read; the real offline Gatekeeper outcome still needs the corrected base. Separately and decisive for the update path: **`right-release install-app` refuses these DMGs** (`stapler-validate` on the mounted .app: "does not have a ticket stapled to it", `install-app-host-0.1.0.log`, reproduced on the host). The VM runs used a patched copy of `install-app.mjs` with the assess and staple checks off (VM has no stapler or Developer ID rule), so the swap/restore code was real but the verify gate was bypassed.

## Harness defects

1. `scripts/interrupt-mac-install.sh` (fixed): the external `pgrep`/`kill` poll never hit the ~50 ms swap (run 1 exited 0 with nothing interrupted). Now uses `scripts/interrupt-mac-install-hook.mjs` (NODE_OPTIONS import, deterministic), exits 3 when nothing fired, asserts outcomes, detaches the DMG left mounted by a killed install, recovers, and checks `rows.json`.
2. `qualification/clean-machine/mac-clean-run.sh` refuses uid 501 and needs an allow-list; the VM user `admin` is uid 501, so it cannot run there unmodified. Not run; checks were done by hand.
3. `sliceapp-base` Gatekeeper state (above). The stray 0-byte `/var/db/SystemPolicy` I created while probing was removed.
4. Typing into a SwiftUI row field over Screen Sharing did not register; row edits were driven with the Insert above button instead.

## Gatekeeper baseline (0.2.139)

Re-run after Adrian set `sliceapp-base` to "App Store & Known Developers" (`spctl --status`: developer id enabled). Fresh clone, DMGs from @rightkit/release 0.2.139 (`.app` not stapled, DMG stapled). Quarantine set as `0083;...;Safari` on the DMG, app copied with `ditto --qtn` (what Finder does). Logs/screenshots: `/Volumes/D/scratch/swiftright/sr0-artifacts/mac/r7/gb*`.

| Check | Result |
|---|---|
| `spctl -a -t open` on quarantined DMG | PASS: accepted, Notarized Developer ID (`gb1`) |
| `spctl -a -vv` on installed .app (0.1.0) | PASS: accepted, Notarized Developer ID (`gb1`) |
| `syspolicy_check distribution` on .app | FAIL: Fatal "Notary Ticket Missing" (the .app staple gap) |
| Quarantined first launch, online | PASS: translocated, standard "downloaded from the Internet" prompt ("Apple checked it for malicious software and none was detected"); after Open the app runs and writes `rows.json` (`gb2`, `gb2b`) |
| Quarantined first launch, guest network OFF | PASS: v4 and v6 default routes removed, apple.com, ocsp.apple.com and cloudkit unreachable. 0.1.1 was used so its app hash had never been seen online by this clone. `spctl` accepted the DMG and the .app offline, the same prompt appeared with the text "As of October 9, 2026, Apple checked it for malicious software and none was detected", and after Open the app ran and wrote `rows.json` (`gb3`, `gb3b`) |
| Real unpatched `right-release install-app` | REFUSES: fails at verify on `stapler-validate`. On the host the message is "SliceApp.app does not have a ticket stapled to it" (`install-app-host-0.1.0.log`); in the VM it fails earlier because the VM has no Xcode tools (`gb3`). Recorded as the result: the real install path cannot install a 0.2.139 DMG. |

Staple-gap conclusion: with the stapled DMG as the carrier, Gatekeeper decides the copied, unstapled .app offline without any prompt or block beyond the normal first-open dialog. The ticket evidently comes from the DMG's staple when the app is opened from a quarantined DMG copy; this is not proven for an app delivered without the DMG (for example a zip), which is not a shipped format here. The real gap is `install-app`'s staple gate and `syspolicy_check`, not first launch. Re-run on 0.2.140.

## Interrupted install on @rightkit/release 0.2.142 (atomic swap, --recover)

Fresh clone of `sliceapp-base` (headless, no graphics), real unpatched 0.2.142 `install-app` (host node binary + the package copied in; VM has no Xcode tools, so the stapler-free `spctl-only` ticket path ran), 0.1.0 = the 0.2.142-built DMG (sha256 363c8768...0d5ea), 0.1.1 = `/Volumes/D/scratch/swiftright/sr0-artifacts/mac/0.1.1`. Interruption injected by `scripts/interrupt-mac-install-hook.mjs` (rewritten for the 0.2.141+ flow: modes `copy`, `swap`, `swap-term`); each run: install 0.1.0, launch it once, interrupt the 0.1.1 upgrade, check, `install-app --recover`, check, uninterrupted 0.1.1 install. Logs: `/Volumes/D/scratch/swiftright/sr0-artifacts/mac/0.1.0-rk0142/r7-interrupt-{copy,swap,swap-term}.log`. The VM clone was deleted afterwards.

| Phase (signal) | Right after the interrupt | `--recover` | After recovery |
|---|---|---|---|
| copy (SIGKILL during ditto into staging) | old 0.1.0 present, verifies, launches; staged copy + journal left; DMG still mounted | `cleared` (staged removed, DMG detached) | old 0.1.0, no leftovers, launches, `rows.json` sha unchanged; follow-up 0.1.1 install OK |
| swap (SIGKILL right after installed -> backup) | **app ABSENT** (backup beside it, journal "swapping"); DMG still mounted | `restored-backup` (DMG detached) | old 0.1.0 back, verifies, launches, no leftovers, `rows.json` unchanged; follow-up 0.1.1 install OK |
| swap (SIGTERM, same point) | old 0.1.0 present (handler rolled back), DMG detached, no leftovers, exit 143 | nothing to recover (0) | old 0.1.0, launches, data unchanged |

Finding: the old non-atomic outcome (old bundle stranded in `~/.Trash`) is gone; no bundle goes to the Trash before the new one verifies. Remaining window: a hard SIGKILL between the two renames leaves the install path absent until the next `install-app` or `install-app --recover` (milliseconds wide; documented behaviour of rename-only swaps without a kernel-level exchange). Signals SIGINT/SIGTERM are fully handled.

## R7 final: quarantined first launch on the stapled-.app build (R3 final DMG b976ac70...)

Date 2026-10-10 (guest clock UTC 01:43-01:49). Artifact `/Volumes/D/scratch/swiftright/sr0-artifacts/mac/r3-final/SliceApp_0.1.0_arm64.dmg`, sha256 `b976ac70f268e1b0b2d998895685fd772736492f59e8cbbf641913541c39b4f4` (verified on the host and again in the guest after scp), built on commit 4496474 with @rightkit/release 0.2.144 (inner .app notarized and stapled before the DMG). Guest: macOS 26.6.2 (25G83) arm64, vanilla, `spctl --status`: assessments enabled / developer id enabled. Fresh clones of `sliceapp-base`, run `tart run --no-graphics --vnc-experimental` (no host window), driven over SSH as `admin`. Raw transcript: `examples/SliceApp/r7-final-transcript.txt`; full syspolicyd logs: `/Volumes/D/scratch/swiftright/sr0-artifacts/mac/r7/final/`. All VM clones deleted at the end (`tart list` shows only `sliceapp-base` and `sliceapp-clean-pristine`).

Procedure, same as the 0.2.139 baseline: quarantine xattr set on the DMG as a Safari download would (`xattr -w com.apple.quarantine "0083;<hex time>;Safari;<uuid>"`), `hdiutil attach -nobrowse`, `ditto --qtn` of the .app to `/Applications` (quarantine propagates), `spctl`, first launch with `open`. Offline = v4 and v6 default routes removed in the guest (www.apple.com, ocsp.apple.com, api.apple-cloudkit.com all unreachable before and after the launch; SSH stays up on the on-link subnet).

| # | Check (command) | Result |
|---|---|---|
| 1 | Hash `shasum -a 256` of the DMG, host and guest | PASS: both `b976ac70...41b4f4` |
| 2 | `spctl -a -vv -t open --context context:primary-signature` on the quarantined DMG | PASS: accepted, `source=Notarized Developer ID`, `origin=Developer ID Application: Adrian D'souza (6KLGD3LLKF)` (online, and offline in both offline runs) |
| 3 | Mount, `ditto --qtn` .app to `/Applications`, `xattr -l` | PASS: .app on the mounted volume has no xattr; the copy carries the DMG's exact quarantine (`0083;...;Safari;<same uuid>`) |
| 4 | `spctl -a -vv -t exec /Applications/SliceApp.app` | PASS: accepted, Notarized Developer ID, same origin (online and both offline runs); `codesign --verify --deep --strict` valid, flags=runtime, TeamIdentifier 6KLGD3LLKF, id `dev.orthic.sliceapp` |
| 5 | `xcrun stapler validate` on the .app | PASS: "The validate action worked!" rc=0 on the guest-installed (quarantined) copy, on the .app inside the DMG, and on the DMG; the ticket file (`Contents/CodeResources`) is byte-identical between guest copy and DMG. Run on the host (Xcode 27 RC stapler): the vanilla guest has no Command Line Tools, so `xcrun`/`stapler` cannot run there. |
| 6 | `syspolicy_check distribution` on the installed .app | PASS: "App passed all pre-distribution checks and is ready for distribution." |
| 7 | First launch, quarantined, ONLINE: `open /Applications/SliceApp.app` | PASS: process starts translocated (`/private/var/folders/.../AppTranslocation/<uuid>/d/SliceApp.app`) and is held at 0:00.00 CPU for about 6 s until the first-open prompt is answered; syspolicyd: `GK process assessment` then `GK eval - was allowed: 1, show prompt: 1`, `present prompt ... type=QuarantineFirstOpen`, `Prompt shown (5, 0), waiting for response`; after the answer `Marked application as user approved: 1`, the app runs, writes `rows.json`; quarantine flag becomes `00c3`. Zero rejected/denied/`was allowed: 0` lines in the log window. |
| 8 | First launch OFFLINE, same VM (app moved aside, DMG re-quarantined, re-copied, routes removed, same app hash as the online run) | PASS: `spctl` accepts DMG and .app offline; syspolicyd `cloudkit request failed ... Code=-1009` (not connected), then `was allowed: 1, show prompt: 1`, prompt shown, approved, app runs and writes `rows.json`. No rejection. |
| 9 | First launch OFFLINE, fresh clone with the routes removed BEFORE the DMG was delivered (first-ever evaluation of this app, nothing cached online) | PASS: same sequence (`cloudkit request failed -1009`, allowed, QuarantineFirstOpen prompt, approved, runs, `rows.json`). No rejection. |
| 10 | Process stays up, quits cleanly | PASS (all three runs): alive 16-26 s after launch (10-19 s after the approval); quit through `NSRunningApplication.terminate` (the Cmd+Q path), process gone in about 1 s, `rows.json` sha unchanged across the quit, no SliceApp crash or diagnostic report. |

Differences from the 0.2.139 baseline:

- `syspolicy_check distribution` on the .app flipped from FAIL ("Notary Ticket Missing", Fatal) to PASS, and `stapler validate` now works on the .app itself (baseline: no ticket on the .app, which is also what made `install-app` refuse the DMG). The staple gap is closed on this build.
- Gatekeeper outcome is unchanged: accepted as Notarized Developer ID, the same translocation, the same one-time first-open prompt, the same behaviour offline. Both the DMG and the .app now carry a ticket, so these runs cannot say which one Gatekeeper used offline; the baseline's open question (an app delivered without the stapled DMG, for example a zip) was not exercised.
- Method differences: no screenshots (the headless VZ display is not rendered, so the dialog text was not captured). The prompt was answered with the Return key (default button Open) through a held headless VNC input session, and its presence is proven by the syspolicyd lines plus the process being held until the key. The baseline's offline run reused the clone with a different app version; this run did both that variant (same VM, same hash) and a stricter fresh-clone variant.
- Not re-run here (out of scope for this lane): real unpatched `right-release install-app` against this DMG, interrupted-install runs.
- Harness notes: the VZ VNC server dies if a second client connects or if a client omits pseudo-encodings (two throwaway VMs lost while building the input client; no data taken from them), and an early attempt was discarded because the DMG arrived mode 0444 and `xattr -w` failed, so nothing was quarantined; the reported runs are on clean clones with the quarantine verified by `xattr -l` first.

PENDING item "R7 re-run of the quarantined launch on the stapled-.app build (0.2.140+)": done for the R3 final DMG (checks 1-10 PASS).
