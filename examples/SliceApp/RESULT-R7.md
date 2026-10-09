# R7 result: Mac clean environment (2026-10-09)

Verdict: **R7 NOT PASSED.** The quarantine/Gatekeeper checks are blocked by the VM base image; the update-mechanics checks ran and passed on the non-quarantined path.

Environment: Tart clone of `sliceapp-base` (macOS 26.6.2 25G83, arm64), run `--no-graphics --vnc-experimental` (no host window; the display device was needed to look at the Gatekeeper dialog), driven over SSH plus the guest's own Screen Sharing from the host. Clone deleted at the end. DMGs from R3, hashes verified in the guest: 0.1.0 `81742a7c...64b661`, 0.1.1 `c75155b4...071a8a`. Logs/screenshots: `/Volumes/D/sr0-artifacts/mac/r7/`.

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

Re-run after Adrian set `sliceapp-base` to "App Store & Known Developers" (`spctl --status`: developer id enabled). Fresh clone, DMGs from @rightkit/release 0.2.139 (`.app` not stapled, DMG stapled). Quarantine set as `0083;...;Safari` on the DMG, app copied with `ditto --qtn` (what Finder does). Logs/screenshots: `/Volumes/D/sr0-artifacts/mac/r7/gb*`.

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

Fresh clone of `sliceapp-base` (headless, no graphics), real unpatched 0.2.142 `install-app` (host node binary + the package copied in; VM has no Xcode tools, so the stapler-free `spctl-only` ticket path ran), 0.1.0 = the 0.2.142-built DMG (sha256 363c8768...0d5ea), 0.1.1 = `/Volumes/D/sr0-artifacts/mac/0.1.1`. Interruption injected by `scripts/interrupt-mac-install-hook.mjs` (rewritten for the 0.2.141+ flow: modes `copy`, `swap`, `swap-term`); each run: install 0.1.0, launch it once, interrupt the 0.1.1 upgrade, check, `install-app --recover`, check, uninterrupted 0.1.1 install. Logs: `/Volumes/D/sr0-artifacts/mac/0.1.0-rk0142/r7-interrupt-{copy,swap,swap-term}.log`. The VM clone was deleted afterwards.

| Phase (signal) | Right after the interrupt | `--recover` | After recovery |
|---|---|---|---|
| copy (SIGKILL during ditto into staging) | old 0.1.0 present, verifies, launches; staged copy + journal left; DMG still mounted | `cleared` (staged removed, DMG detached) | old 0.1.0, no leftovers, launches, `rows.json` sha unchanged; follow-up 0.1.1 install OK |
| swap (SIGKILL right after installed -> backup) | **app ABSENT** (backup beside it, journal "swapping"); DMG still mounted | `restored-backup` (DMG detached) | old 0.1.0 back, verifies, launches, no leftovers, `rows.json` unchanged; follow-up 0.1.1 install OK |
| swap (SIGTERM, same point) | old 0.1.0 present (handler rolled back), DMG detached, no leftovers, exit 143 | nothing to recover (0) | old 0.1.0, launches, data unchanged |

Finding: the old non-atomic outcome (old bundle stranded in `~/.Trash`) is gone; no bundle goes to the Trash before the new one verifies. Remaining window: a hard SIGKILL between the two renames leaves the install path absent until the next `install-app` or `install-app --recover` (milliseconds wide; documented behaviour of rename-only swaps without a kernel-level exchange). Signals SIGINT/SIGTERM are fully handled.
