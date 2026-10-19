# R5 runbook: Windows Sandbox clean-guest checks (ordered commands)

Status: PREP. Nothing below has been run. The Dell hosts a timing-sensitive matrix at the time of writing: run nothing until the Dell is
declared free (builds and the Sandbox window both need a quiet desktop; coordinate per the peer-session rule).

**Update 2026-10-10 (final2 round, RESULT-R5.md):** the Sandbox is now run twice per tuple: `run-sandbox.ps1 -RunProfile Offline` (networking disabled; every check except W12) and `-RunProfile Network` (networking enabled; W00, W01, W12). Use a distinct `-RunId` per run. W08 interrupts through `interrupt-windows-install.ps1 -Mode KillClient|CancelOperation` (no AppXSvc kill, no reboot). RightKit refuses to rebuild a version already sealed in the clone from another commit: move the old `.right-release\sealed\<release>` directory out of the clone (do not edit RightKit state). Gotcha: through `win` and `sh`, `-Cmd ''& script''` loses its quotes and the remote PowerShell 7 treats the bare `&` as a background operator, so the wrapper never runs; write the launch into a .ps1 and pass its path.

## 0. Facts established (read-only, 2026-10-09)

| Question | Answer |
|---|---|
| Windows Sandbox enabled on the Dell? | YES: `Get-WindowsOptionalFeature -Online -FeatureName Containers-DisposableClientVM` returned `State : Enabled` (no elevation needed from the SSH session). `C:\WINDOWS\system32\WindowsSandbox.exe` exists. There is NO `wsb` CLI, so `run-sandbox.ps1` falls back to `WindowsSandbox.exe <wsb>` (no sandbox id); the guest harness therefore ends with `Stop-Computer` after the receipts are flushed. Console session `adrds` is Active; Dell has node, git, pnpm, 562 GB free on D:. |
| Do the R5 packages have to be rebuilt? | YES. The R2 MSIX (0.1.0.0/0.1.1.0) carry renderer 777F14C4 (RightKit-signed, Authenticode digest 01063E20...) and SliceApp from d70d36b. The final tuple renderer is `4FB068F0B6C73DE9A5DDE1A536E97EEDD08E2FEA3C0DD8B92FC0E4A78E53298F` (`D:\Claude\sr0s-bridge06f\payload\bin\swiftright_render.dll`, 11,789,312 B, verified present). R5 receipts bind to the tuple only if the packaged renderer is that DLL, and the pin check (`verify-package-layout.ps1 -Mode Installed`) compares against `Windows/renderer-pin.json`. The pin is updated in this change (sha256 4FB068F0..., Authenticode digest `B77F7A5EDBE5AF03A375A59561796E9A12CA76078DB6D660CE4C47DCF2B75F49`, computed on the Mac from the Dell copy and cross-checked with the node `authenticodeDigest` in `swift-only-proof.mjs`; import closure unchanged: `imm32.dll` was already in the pin). The old R2 packages stay valid R2 evidence only. No Rust is rebuilt: the renderer is copied, not compiled. |
| Packaged DLLs and raw hashes | RightKit Authenticode-signs every PE in the payload with a new timestamp per build, so raw sha256 differs per build and never equals the pin. All checks compare the Authenticode digest (PE hash excluding checksum + certificate table): `verify-package-layout.ps1` (Stage and Installed modes, already fixed in 1ab091c), `swift-only-proof.mjs --old-msix --new-msix` (fixed in 1ab091c; re-run on the R2 artifacts for this prep: `ok: true`). |

## 1. Harness changes made for R5 (uncommitted; Adrian commits and pushes before section 3)

- `Windows/renderer-pin.json`: final renderer 4FB068F0 (see above).
- `scripts/make-local-appinstaller.mjs`: finds RightKit through `$RIGHTKIT_RELEASE_DIR`, else the app's own `node_modules/@rightkit/release` (0.2.142), else the old tools tree. Run on the Mac; the guest needs no node.
- `scripts/interrupt-windows-install.ps1`: refuses to run with the package already registered, writes structured JSON (`-ResultJson`), valid only when AppXSvc was stopped mid-flight AND the cmdlet failed.
- `scripts/run-unelevated-step.ps1` (new): one-shot Interactive/Limited hidden scheduled task, the non-elevated method of RESULT-R2.md (log first line `elevated=False`, last line `EXIT=<n>`).
- `scripts/bump-version-win.ps1` (new): the R2 "0.1.1" recipe as a script (version fields + one Swift diagnostic string) for the clone-local commit.
- `qualification/clean-machine/windows/guest/sandbox-run.ps1` and `run-sandbox.ps1`: W08 (real interrupted update) and W11 (physical paths, legacy data, virtualization manifest) now implemented; new W12 (App Installer feed install + OnLaunch update + publisher-mismatch rejection over a guest-local https feed), W13 (installed renderer by Authenticode digest via `verify-package-layout.ps1 -Mode Installed`), W14 (update deferred while the app runs). W06 now makes the new build write a row, so W09 proves the old build reads data written by the new one. Host requires `-ExpectOldSha256/-ExpectNewSha256` (the seal hashes), `-FeedDir`, and hash-binds every staged script, feed file and the pin. Marker rows are written into the new empty row (previous versions overwrote the last row).
- `qualification/run.py` `PACKAGE_CHECKS["windows-x64"]` extended with W12, W13, W14 (declared order; `qualification` tests 74/74 pass).
- All four PowerShell files parse clean (`System.Management.Automation.Language.Parser` on the Dell, no execution). NOT executed: first real run may need small fixes; each failed check records its reason.

Plan check to harness check: install = W03, offline launch = W00+W04, upgrade = W06, real interrupted update = W08 (+W14), corrupt update rejection = W07, rollback readability = W09, uninstall keeps data = W10, virtualization physical paths = W11, renderer layout = W13, App Installer route = W12.

## 2. Commit and push (Adrian; I made no git writes)

```sh
cd /Volumes/D/claude/swiftright
git add examples/SliceApp qualification && git commit   # then push to origin master
FINAL=$(git rev-parse HEAD); echo $FINAL
```

## 3. Rebuild the MSIX pair on the final renderer (Dell, non-elevated, no upload)

Do not start until the Dell is free. Builds are `right-release build` (sealed, no upload; `release --no-upload` fails with "build is tier-neutral").

QA gate (@rightkit/release 0.2.144): `build` also refuses without a passing `right-release qa --stage source` receipt for the exact commit of that clone (PACKAGING.md "QA gate"). Run `D:\Claude\sr0-r5\step-qa-0.1.0.ps1` (clone `clean`) and `step-qa-0.1.1.ps1` (clone `clean2`) BEFORE the build steps below, or pass `-Build` to chain the build in the same task. QA opens SliceApp windows on the Dell desktop and needs `D:\Claude\sr0-r5\bin\rightkit-qa.exe` (the launchers put it on PATH for their own process). The clones carry a clone-local QA commit delivered by bundle (`sr0-r5d.bundle`); a different commit needs its own QA run.

```sh
FINAL=<sha from section 2>
cd /Volumes/D/claude/swiftright/examples/SliceApp
# helper scripts outside any repo (the clone must stay clean)
win 'New-Item -ItemType Directory -Force D:\Claude\sr0-r5\in | Out-Null'
scp scripts/run-unelevated-step.ps1 win:D:/Claude/sr0-r5/run-unelevated-step.ps1
# two independent clones at the same commit: clean (0.1.0.0) and clean2 (0.1.1.0)
for c in clean clean2; do
  win "git clone --no-checkout git@github.com:bogusyogi/swiftright.git D:\Claude\sr0-r5\\$c; Set-Location D:\Claude\sr0-r5\\$c; git config core.autocrlf false; git config core.symlinks false; git checkout -q -B sr0-r5-final $FINAL; Add-Content .git\info\exclude '.right-release/'; git rev-parse HEAD; git status --porcelain"
done
# new tree: version bump + Swift-only string, committed clone-locally (clean2 only)
win 'powershell -NoProfile -ExecutionPolicy Bypass -File D:\Claude\sr0-r5\clean2\examples\SliceApp\scripts\bump-version-win.ps1 -AppDir D:\Claude\sr0-r5\clean2\examples\SliceApp'
win 'Set-Location D:\Claude\sr0-r5\clean2; git -c user.name=sr0-r5 -c user.email=sr0-r5@local commit -qam "SliceApp 0.1.1: version fields + Swift-only diagnostic string (R5 new package)"; git rev-parse HEAD; git status --porcelain'   # record NEWSHA
# preflight (no build): ownership/trust/toolchain, non-elevated
win 'powershell -NoProfile -ExecutionPolicy Bypass -File D:\Claude\sr0-r5\run-unelevated-step.ps1 -Log D:\Claude\sr0-r5\log-doctor.txt -WorkDir D:\Claude\sr0-r5\clean\examples\SliceApp -TimeoutMin 20 -Cmd ''$env:SWIFTRIGHT_RENDERER_SRC=''''D:\Claude\sr0s-bridge06f\payload\bin\swiftright_render.dll''''; pnpm install --frozen-lockfile; pnpm exec right-release doctor --platform win --config right-release.config.mjs'''
# build 0.1.0.0 (log must show elevated=False and "renderer pinned ok ... sha256=4FB068F0")
win 'powershell -NoProfile -ExecutionPolicy Bypass -File D:\Claude\sr0-r5\run-unelevated-step.ps1 -Log D:\Claude\sr0-r5\log-build-0.1.0.txt -WorkDir D:\Claude\sr0-r5\clean\examples\SliceApp -TimeoutMin 60 -Cmd ''$env:SWIFTRIGHT_RENDERER_SRC=''''D:\Claude\sr0s-bridge06f\payload\bin\swiftright_render.dll''''; pnpm install --frozen-lockfile; pnpm exec right-release build --platform win --config right-release.config.mjs'''
# build 0.1.1.0
win 'powershell -NoProfile -ExecutionPolicy Bypass -File D:\Claude\sr0-r5\run-unelevated-step.ps1 -Log D:\Claude\sr0-r5\log-build-0.1.1.txt -WorkDir D:\Claude\sr0-r5\clean2\examples\SliceApp -TimeoutMin 60 -Cmd ''$env:SWIFTRIGHT_RENDERER_SRC=''''D:\Claude\sr0s-bridge06f\payload\bin\swiftright_render.dll''''; pnpm install --frozen-lockfile; pnpm exec right-release build --platform win --config right-release.config.mjs'''
```

Expect `dist\win\SliceApp_0.1.0.0_x64.msix` in `clean` and `SliceApp_0.1.1.0_x64.msix` in `clean2`. Locate the seals (RightKit state root; the R2 copies were taken from there): `win 'Get-ChildItem D:\Claude\sr0-r5,D:\Claude\.rightkit -Recurse -Filter msix-seal*.json -ErrorAction SilentlyContinue | Sort LastWriteTime | Select FullName,LastWriteTime'`.

## 4. Pull artifacts to the Mac (canonical copy) and verify

```sh
A=/Volumes/D/scratch/swiftright/sr0-artifacts/win/r5-msix; mkdir -p $A
scp win:D:/Claude/sr0-r5/clean/examples/SliceApp/dist/win/SliceApp_0.1.0.0_x64.msix $A/
scp win:D:/Claude/sr0-r5/clean2/examples/SliceApp/dist/win/SliceApp_0.1.1.0_x64.msix $A/
scp win:D:/Claude/sr0-r5/log-doctor.txt win:D:/Claude/sr0-r5/log-build-0.1.0.txt win:D:/Claude/sr0-r5/log-build-0.1.1.txt $A/
# seals: copy the two msix-seal.json found above as $A/msix-seal-0.1.0.json and msix-seal-0.1.1.json
cd $A && shasum -a 256 SliceApp_*.msix        # must equal msix.sha256 in each seal (lowercase)
# Swift-only proof on the final pair (Authenticode digests; renderer = new pin)
cd /Volumes/D/claude/swiftright/examples/SliceApp
git -C /Volumes/D/claude/swiftright fetch -q 2>/dev/null; OLDC=$FINAL; NEWC=<NEWSHA>
# the proof runs `git diff old..new` in --repo: use a Mac checkout that has both commits (NEWSHA exists only in the Dell clone: fetch it first)
node scripts/swift-only-proof.mjs --old-seal $A/msix-seal-0.1.0.json --new-seal $A/msix-seal-0.1.1.json --old-commit $OLDC --new-commit $NEWC --repo <dir containing both commits> --build-log $A/log-build-0.1.0.txt --build-log $A/log-build-0.1.1.txt --old-msix $A/SliceApp_0.1.0.0_x64.msix --new-msix $A/SliceApp_0.1.1.0_x64.msix
# signatures (Dell read-only; signtool is not on PATH, RightKit finds it; Get-AuthenticodeSignature is enough here)
win 'Get-AuthenticodeSignature D:\Claude\sr0-r5\clean\examples\SliceApp\dist\win\SliceApp_0.1.0.0_x64.msix,D:\Claude\sr0-r5\clean2\examples\SliceApp\dist\win\SliceApp_0.1.1.0_x64.msix | Select Status,@{n="Thumb";e={$_.SignerCertificate.Thumbprint}} | Format-Table'   # expect Valid, 70C72673...
```

If NEWSHA is not reachable from a Mac checkout, run the proof on the Dell (node exists) with `--repo D:\Claude\sr0-r5\clean2`; commit-range check is the only part that needs git.

## 5. Generate the local App Installer feeds on the Mac (RightKit 0.2.142 generator)

```sh
cd /Volumes/D/claude/swiftright/examples/SliceApp/scripts
F=/Volumes/D/scratch/swiftright/sr0-artifacts/win/r5-msix/feed; mkdir -p $F/0 $F/1
node make-local-appinstaller.mjs --msix $A/SliceApp_0.1.0.0_x64.msix --version 0.1.0.0 --out $F/0
node make-local-appinstaller.mjs --msix $A/SliceApp_0.1.1.0_x64.msix --version 0.1.1.0 --out $F/1
cp $F/0/SliceApp.appinstaller $F/SliceApp.0.appinstaller; cp $F/1/SliceApp.appinstaller $F/SliceApp.1.appinstaller
cat $F/SliceApp.0.appinstaller   # Publisher must equal the MSIX identity publisher; Version 0.1.0.0; URLs https://localhost:8443/sliceapp/...
```

The config's own App Installer URLs are `.invalid` placeholders; the production host/TLS chain stays UNTESTED and must be recorded as such.

## 6. Copy to the Dell and run the Sandbox (needs the Dell console desktop; guest runs ~30 to 45 min)

```sh
cd /Volumes/D/claude/swiftright
OLD=$(shasum -a 256 $A/SliceApp_0.1.0.0_x64.msix | cut -d' ' -f1); NEW=$(shasum -a 256 $A/SliceApp_0.1.1.0_x64.msix | cut -d' ' -f1)
# harness tree from the pushed commit (no working-tree leftovers)
git archive --format=tar $FINAL qualification/clean-machine/windows examples/SliceApp/scripts examples/SliceApp/Windows/renderer-pin.json -o /private/tmp/r5-harness.tar
scp /private/tmp/r5-harness.tar win:D:/Claude/sr0-r5/r5-harness.tar
win 'New-Item -ItemType Directory -Force D:\Claude\sr0-r5\harness | Out-Null; tar -xf D:\Claude\sr0-r5\r5-harness.tar -C D:\Claude\sr0-r5\harness'
scp $A/SliceApp_0.1.0.0_x64.msix $A/SliceApp_0.1.1.0_x64.msix $F/SliceApp.0.appinstaller $F/SliceApp.1.appinstaller win:D:/Claude/sr0-r5/in/
# hash check on the Dell (run-sandbox.ps1 also refuses any other bytes)
win 'Get-FileHash D:\Claude\sr0-r5\in\*.msix -Algorithm SHA256 | Select Hash,Path'
# launcher script (the Sandbox window needs the interactive session, so it goes through the same Interactive task)
cat > /private/tmp/r5-launch.ps1 <<EOF
Set-Location D:\Claude\sr0-r5\harness\qualification\clean-machine\windows
.\run-sandbox.ps1 -OldMsix D:\Claude\sr0-r5\in\SliceApp_0.1.0.0_x64.msix -NewMsix D:\Claude\sr0-r5\in\SliceApp_0.1.1.0_x64.msix -FeedDir D:\Claude\sr0-r5\in -ExpectOldSha256 $OLD -ExpectNewSha256 $NEW -RunId r5-final -OutRoot D:\Claude\sr0-r5\runs
EOF
scp /private/tmp/r5-launch.ps1 win:D:/Claude/sr0-r5/r5-launch.ps1
# stage only (no sandbox start) to validate staging and the .wsb:
win 'Set-Location D:\Claude\sr0-r5\harness\qualification\clean-machine\windows; (Get-Content D:\Claude\sr0-r5\r5-launch.ps1 -Raw).Replace("-RunId r5-final","-RunId r5-dry -DryRun") | Set-Content D:\Claude\sr0-r5\r5-dry.ps1; powershell -NoProfile -ExecutionPolicy Bypass -File D:\Claude\sr0-r5\r5-dry.ps1'
# real run (Dell desktop must be free; Sandbox ends itself with Stop-Computer; host verdict written to runs\r5-final\receipts\run.json)
win 'powershell -NoProfile -ExecutionPolicy Bypass -File D:\Claude\sr0-r5\run-unelevated-step.ps1 -Log D:\Claude\sr0-r5\log-sandbox.txt -WorkDir D:\Claude\sr0-r5 -TimeoutMin 90 -Cmd ''& D:\Claude\sr0-r5\r5-launch.ps1'''
```

Note: `r5-launch.ps1` is written with LF line endings by the Mac heredoc; PowerShell accepts that. The Sandbox is started by the logged-in user with the guest networking disabled; do not touch the Sandbox window while it runs.

## 7. Collect the verdict

```sh
mkdir -p $A/receipts && scp -r win:D:/Claude/sr0-r5/runs/r5-final/receipts/* $A/receipts/
scp win:D:/Claude/sr0-r5/log-sandbox.txt $A/
jq '{status,reason,checks}' $A/receipts/run.json      # PASS only if all 15 declared checks are pass + implemented
```

R5 PASS requires `status: pass` in `run.json` (every check pass, implemented, hashes equal the host's) plus the recorded untested limits: production App Installer host/TLS, the AppXSvc-stop technique is fault injection (not a Microsoft procedure), and the Sandbox uses the desktop vGPU.

## 8. Cleanup

Recycle (do not permanently delete) `D:\Claude\sr0-r5\clean`, `clean2` and `runs` after the artifacts and receipts are on the Mac. Keep `/Volumes/D/scratch/swiftright/sr0-artifacts/win/r5-msix/`.

## 9. Known risks for the first real run

1. W02: the signer chain is trusted online on the Dell; the offline guest gets only the public `.cer` in TrustedPeople (sideload trust). If `Add-AppxPackage` still reports a chain error, record the HRESULT; do not add network.
2. W13/W11 read files under `C:\Program Files\WindowsApps\<package>`; ACLs normally allow the installing user. If denied, W13's receipt shows the exact error.
3. W12 depends on guest loopback https while the `.wsb` sets `Networking Disable`; if loopback is blocked the check fails with "local feed did not come up" and the App Installer route stays UNTESTED (the plain local upgrade W06 still covers upgrade).
4. W08 timing: a 28 MB package may finish deploying before the stop lands; the script then reports `valid=false` (the check fails rather than passing) and should be retried, at most twice before escalation.
5. `workload` probe defaults (`probes/sr0-b/workload/scripts/*.ps1`) and `run-matrix.sh` still default to renderer 777F14C4: that is the R10/R1 owners' pin, not touched here.
