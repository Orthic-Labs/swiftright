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
