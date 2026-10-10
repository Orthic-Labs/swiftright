# Mac clean environment checklist (SR0 R7, harness run in R8)

Status: the harness ran on 10 Oct 2026 in two fresh Tart clones of `sliceapp-base` (macOS 26.6.2, arm64) against the
R3 final DMGs (old 0.1.0 `b976ac70…`, new 0.1.1 `75f3cd75…`): automated profile 11/11 PASS, window-server profile 1/1 PASS,
`qualification/run.py --stages package` macOS union 12/12 PASS, tuple-pinned. Results and receipts: `qualification/R8-PARTIAL.md`
("macOS package record"). Runner: `mac-clean-run.sh`. Offline helper: `mac-vm-offline.sh`. Receipts: `receipt.schema.json`.

## Who runs this

- Inside a throw-away Tart clone of `sliceapp-base` (`tart clone`, `tart run --no-graphics`, no `--dir` shares). Never on the
  host Mac: the harness writes `~/Downloads`, `~/Applications`, `~/Library/Application Support/SliceApp`, mounts DMGs and starts
  the app. Delete the clone afterwards. A dedicated test user on a physical Mac still works, with the limits below.
- The guard (`guard_identity`) refuses root, the name `adrdsouza`, a user missing from the allow-list, an allow-list not owned by
  the user or group/world writable, `HOME` other than `/Users/<user>`, any path outside `$HOME`, and a non-empty receipts
  directory. It refuses **uid 501 only when the machine is not a VM**: the guest's `admin` is uid 501, so a uid test alone cannot
  tell the guest from the workspace user. A VM is `sysctl kern.hv_vmm_present` = 1 and `hw.model` = `VirtualMac*`. Values observed
  in a Tart guest on 10 Oct 2026: `1` and `VirtualMac2,1` (`id` = `uid=501(admin)`, macOS 26.6.2 25G83). The host reports `0` and
  `Mac18,5` and still refuses uid 501. Inside a guest the remaining protection is that the clone holds nothing of Adrian's and is
  deleted afterwards; the name and allow-list checks stay as the second layer.
- The test user creates `~/clean-machine-allow.txt` (one user name per line, `admin` in the guest), mode 600.
- One profile per fresh clone. A launch that Gatekeeper holds (for example an unanswered first-open prompt) leaves a pending
  evaluation for that install path in the guest's `syspolicyd`, and every later launch from the same path then waits on it.
  The harness also refuses a first launch when `rows.json` already exists.

## Profiles (the runner takes the union)

| Profile | Checks | Needs |
|---|---|---|
| `automated` (default) | M00-M10 | both DMGs and seal hashes, `--node-bin`, `--right-release-cli`, `--interrupt-script`; guest offline (`mac-vm-offline.sh`) |
| `window-server` | M11 | old DMG and seal hashes; fresh clone; unattended |
| `manual` | M11 | a screenshot file, `--observer`, `--note`; no app launch |

Give the runner exactly one of `window-server` and `manual`: both would record M11 with different evidence, which the union rule
fails. `--plan [--profile P]` prints a profile's check order and touches nothing.

## Commands (host side, per fresh clone)

```sh
export TART_HOME=/Volumes/D/tart-home; T=/Volumes/D/tart-install/dl/tart.app/Contents/MacOS/tart
cd /Volumes/D/claude/swiftright; K="-i $TART_HOME/keys/vmkey -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"
$T clone sliceapp-base sr0-mac-rec-a; (nohup $T run sr0-mac-rec-a --no-graphics >/dev/null 2>&1 &)
IP=$($T ip sr0-mac-rec-a --wait 120)                         # then wait until ssh admin@$IP answers
ssh $K admin@$IP 'mkdir -p ~/r8/dmg ~/r8/node_modules; printf "admin\n" > ~/clean-machine-allow.txt; chmod 600 ~/clean-machine-allow.txt'
scp $K qualification/clean-machine/mac-clean-run.sh qualification/clean-machine/mac-vm-offline.sh \
  examples/SliceApp/scripts/interrupt-mac-install.sh examples/SliceApp/scripts/interrupt-mac-install-hook.mjs admin@$IP:r8/
scp $K "$(command -v node)" admin@$IP:r8/node               # the host node binary, as R7 did
tar -C examples/SliceApp/node_modules/.pnpm/@rightkit+release@0.2.145/node_modules -chf - . | ssh $K admin@$IP 'tar -C ~/r8/node_modules -xf -'
scp $K /Volumes/D/sr0-artifacts/mac/r3-final/SliceApp_0.1.0_arm64.dmg /Volumes/D/sr0-artifacts/mac/r3-final-011/SliceApp_0.1.1_arm64.dmg admin@$IP:r8/dmg/
ssh $K admin@$IP 'chmod 644 ~/r8/dmg/*.dmg; bash ~/r8/mac-vm-offline.sh'
ssh $K admin@$IP 'cd ~/r8; bash mac-clean-run.sh --allowlist ~/clean-machine-allow.txt \
  --old-dmg dmg/SliceApp_0.1.0_arm64.dmg --old-sha sha256:b976ac70f268e1b0b2d998895685fd772736492f59e8cbbf641913541c39b4f4 --old-version 0.1.0 \
  --new-dmg dmg/SliceApp_0.1.1_arm64.dmg --new-sha sha256:75f3cd75cbd5e0f2eb1f561ae4d273f2522dedc19c75713b138a919678dd4b3b --new-version 0.1.1 \
  --node-bin ~/r8/node --right-release-cli ~/r8/node_modules/@rightkit/release/cli/right-release.mjs --interrupt-script ~/r8/interrupt-mac-install.sh'
scp $K -r admin@$IP:clean-machine-receipts/<run id> qualification/receipts/package/mac-<run id>
$T stop sr0-mac-rec-a; $T delete sr0-mac-rec-a
```

M11 in a second fresh clone (no offline step, no node or right-release; only the harness, the old DMG and the allow-list):

```sh
ssh $K admin@$IP 'cd ~/r8; bash mac-clean-run.sh --profile window-server --allowlist ~/clean-machine-allow.txt \
  --old-dmg dmg/SliceApp_0.1.0_arm64.dmg --old-sha sha256:b976ac70f268e1b0b2d998895685fd772736492f59e8cbbf641913541c39b4f4 --old-version 0.1.0 \
  --new-sha sha256:75f3cd75cbd5e0f2eb1f561ae4d273f2522dedc19c75713b138a919678dd4b3b --new-version 0.1.1'
```

Seal hashes come from the seals (`examples/SliceApp/r3-final/release-manifest.json`, `r3-final-011/release-manifest.json`), never
from a hash of the copy (M01). Then run the package stage on the Windows run directories plus the macOS ones:
`python3 -I qualification/run.py run --stages package --package-receipts <windows dirs> qualification/receipts/package/mac-*`.

## What each check does

- **M00** arm64; no default route at all (v4, v6, scoped: `netstat -rn`); `https://www.apple.com` unreachable (curl code 000).
  `mac-vm-offline.sh` removes the routes first. It runs outside the harness, refuses unless the machine is a VM, and changes only
  the runtime routing table (R7's method). The harness itself changes no system setting.
- **M01** both DMGs equal the seal hashes passed on the command line.
- **M02** each DMG is copied to `~/Downloads`, made writable (a sealed DMG is mode 0444 and `xattr -w` needs write access),
  compared with the seal again, and given a browser-style `com.apple.quarantine` attribute.
- **M03** replaces `xcrun stapler validate` (the vanilla guest has no Xcode tools: `xcrun` is a shim that pops an install dialog).
  For the old and the new DMG and the `.app` inside each: `spctl --assess` must report `source=Notarized Developer ID`, and
  `syspolicy_check distribution` must pass. The spctl source proves Gatekeeper accepts the artifact as notarized (ticket or
  online lookup). `syspolicy_check distribution` proves the notarization ticket is physically stapled to that artifact: a missing
  staple is the fatal "Notary Ticket Missing", the offline-first-launch precondition (R7 0.2.139 baseline failed exactly there);
  it also covers signature and hardened-runtime pre-distribution checks. It does not prove an `.app` delivered without its DMG.
- **M04** mount the quarantined DMG read-only, verify (codesign, `spctl --type execute`, version, bundle id), then `ditto` to
  `~/Applications`. The copy inherits the DMG's quarantine attribute.
- **M05 / M06 / M09 launches.** The binary is executed directly from the SSH session. In the Tart guest that session reaches the
  console session's window server: the check passes only if the app process is alive and the window server (CGWindowList through
  `osascript`, VM only) lists an on-screen window of it within 60 s; the time, the window size and syspolicyd's "GK eval" verdict
  counts are recorded. An app that is not alive, or has no window, is a FAIL. `open` and `launchctl asuser` were not used: the
  installed copy is quarantined, so `open` shows the first-open prompt, which an unattended run cannot answer (R7 final answered it
  over VNC). Direct exec still makes Gatekeeper evaluate the quarantined app (R8 logs: `GK eval - was allowed: 1, show prompt: 0`,
  offline), but it does not exercise the LaunchServices prompt; R7 final covered that by hand (10/10 PASS).
- **M05** also requires that `rows.json` did not exist before the launch (a clean machine), and schema 1 after it.
- **M06** upgrade by DMG replace, `rows.json` unchanged by the install, new build launches. Needs two different builds
  (`--allow-same-dmg` is a dry-run switch and makes M06 FAIL).
- **M07** a Mach-O with one flipped byte fails the install gate and the installed bundle is unchanged.
- **M08** R7's interrupt method: `interrupt-mac-install.sh` and its hook against the real `right-release install-app --recover`
  (host node binary and the pinned `@rightkit/release` copied into the guest), scratch destination under `~/clean-machine-work`,
  modes `copy` (SIGKILL during the ditto into staging), `swap` (SIGKILL between the two swap renames) and `swap-term` (SIGTERM at
  the same point). Per mode the receipt records the script exit code, whether the hook fired, the EXPECT PASS and FAIL counts, the
  state right after the interrupt and after `--recover`; the log is hashed. All three must exit 0 with the hook fired. Known R7
  outcome, not a defect of the harness: after a SIGKILL between the two renames the install path is absent until `--recover`.
- **M09** the old build reads data written by the new one. **M10** the bundle is moved to `~/clean-machine-work/<run id>/uninstalled/`
  (not the Trash) and `rows.json` is unchanged.
- **M11, window-server profile.** Install the old build from its quarantined DMG on a clean machine, launch it, and require an
  on-screen, visible (alpha > 0) layer-0 window of at least 200x100 in the window server's list for the app process. The raw
  window-server entries are the evidence artifact. This is not a screenshot and does not show that the window renders correctly.
- **M11, manual profile.** `--evidence <png> --observer <name> --note <what was seen>`: the harness checks the PNG signature,
  copies and hashes it, and records `manual: "true"`, the observer and the note. It cannot inspect pixels. `observer` `harness` is
  refused. Take the screenshot while the app window is up (for example during a `window-server` run you keep open, or by hand).

## Why M11 is not a harness screenshot

`screencapture` in the guest fails ("could not create image from display", also with `--vnc-experimental`): `tccd` logs
`kTCCServiceScreenCapture does not allow prompting; returning denied`. Granting Screen Recording is a TCC (system privacy)
setting that an agent must not change, so an unattended harness screenshot is not possible. The window-server profile is the
honest automated substitute; the manual profile is for a person or agent that looked at a screenshot.

## Things the harness does not do (on purpose)

- No `python3` (the guest has only the Command Line Tools shim; the harness writes JSON with the system `perl`), no `xcrun`.
- No system setting changes (offline is `mac-vm-offline.sh`, outside the harness), no TCC changes, no Trash, no `rm -rf` of anything.
- Outside a VM neither `osascript` nor `open` is used. No upload. Receipts stay local until Adrian names them.

## Open items

- The data path `~/Library/Application Support/SliceApp/rows.json` is the one in `examples/SliceApp/PACKAGING.md`; M05 confirmed
  it on the shipped 0.1.0 and 0.1.1 builds.
- The LaunchServices first-open prompt (quarantined app opened from Finder) is not automated; R7 final observed it by hand.
- The DMG is arm64 only (scope revision 1). Do not run this on an Intel Mac.
