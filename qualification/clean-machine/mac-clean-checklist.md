# Mac clean environment checklist (SR0 R7)

Status: prep only. Nothing here has run. Inputs are the sealed R3 DMGs (old 0.1.0 and new 0.1.1) and their
hashes from the seal. Runner: `mac-clean-run.sh`. Receipts: `receipt.schema.json`.

## Who runs this

- A dedicated test user (or a clean macOS VM). Adrian creates the user. Agents never create OS accounts.
- Never run this as Adrian's account (`adrdsouza`, uid 501). The runner refuses that user and any root run.
- The test user creates the allow-list at `~/clean-machine-allow.txt`, one user name per line (for example
  `sr0test`). It must be owned by that user and not group- or world-writable. The runner checks all of this.
- Networking: turn Wi-Fi off, or use a VM with no default route. The runner refuses an online run for M00 and M05.

## Steps (in order; the runner does the automated ones)

1. **Preflight (manual, once).** Confirm `id -un` is the test user, `echo $HOME` is `/Users/<test user>`, and
   `route -n get default` prints nothing (offline). Record `sw_vers` and `uname -m` (must be `arm64`).
2. **Seal hashes in hand.** Copy the old and new DMG hashes from the R3 seal output (`sha256:<hex>`). Do not compute
   them from the copy you are about to test: the runner checks the copies against the seal values (M01).
3. **Run the automated checks.**
   ```sh
   bash ~/clean-machine/mac-clean-run.sh \
     --allowlist ~/clean-machine-allow.txt \
     --old-dmg ~/clean-machine/SliceApp_0.1.0_arm64.dmg --old-sha sha256:<hex> --old-version 0.1.0 \
     --new-dmg ~/clean-machine/SliceApp_0.1.1_arm64.dmg --new-sha sha256:<hex> --new-version 0.1.1
   ```
   `--plan` prints the check order without touching anything. Receipts go to
   `~/clean-machine-receipts/<run id>/` (one `<check id>.json` each, plus `run.json`).
   The runner writes only under `$HOME`: `~/Downloads` (quarantined copies), `~/Applications` (install target),
   `~/Library/Application Support/SliceApp` (app data), and `~/clean-machine-work/<run id>`.
4. **Gatekeeper and quarantine, by hand (Finder).** The runner starts the binary directly, so it does not exercise the
   Finder first-launch prompt. Double-click the quarantined copy of `SliceApp.app` in `~/Applications`, accept the
   Gatekeeper prompt once, and note the result in the run notes. Do not click through a prompt that is not shown.
5. **Window observation (M11, manual).** While the app is open after first launch, take one screenshot of the
   window and save it under the receipts folder as `M11-window-visible.png`. Record the observation text in
   `M11-window-visible.note.txt`. M11 stays FAIL in the automated receipt; this note is evidence for a human
   reviewer, not an automated pass. Do not use `screencapture` from the runner (workspace rule). Use the native
   screenshot shortcut on the test user's desktop.
6. **Upgrade and rollback are in the runner** (M06, M09). Expect `rows.json` to match before and after each
   replace, and the old build to read the new data.
7. **Uninstall (M10)** moves the bundle to `~/clean-machine-work/<run id>/uninstalled/`, not the Trash. Empty
   that folder only after the receipts are copied out.
8. **Interrupted install (M08) is a placeholder that always FAILS.** The procedure for interrupting the copy or swap
   is not defined yet (close plan F6). Define it before R7 can pass. Do not mark M08 by hand.
9. **Collect.** Copy the receipts folder out of the test user's home. Check `run.json`: a pass requires every
   expected check (M00 to M11) with `status: pass` and `implemented: true`. The run cannot pass while M08 or M11 is
   a placeholder.

## Things the checklist does not do (on purpose)

- No `open`, `osascript`, `screencapture`, or `notifyutil -p` (workspace rule). Use `right-release install-app`
  only when Adrian asks for that path; this checklist copies the bundle with `ditto` so it tests the drag-to-folder path.
- No system setting changes (networking is turned off by hand, not with `networksetup`).
- No `rm -rf` of anything outside `~/clean-machine-work` and the test user's own data folder.
- No upload. Receipts stay local until Adrian names them for upload.

## Open items

- The data path `~/Library/Application Support/SliceApp/rows.json` is the one in `examples/SliceApp/PACKAGING.md`.
  Confirm it against the shipped app before R7 counts as a pass.
- Gap 3b (PACKAGING.md): whether the copied `.app` passes Gatekeeper with only the DMG ticket is decided by M03 and step 4.
- The DMG is arm64 only (scope revision 1). Do not run this on an Intel Mac.
