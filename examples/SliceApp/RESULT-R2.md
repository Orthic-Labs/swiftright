# R2 Windows MSIX result (2026-10-09)

Host: Dell (bogus-dell), @rightkit/release 0.2.139 (published), built through a one-shot Interactive/Limited hidden scheduled task (non-elevated, `elevated=False` in every log), no upload, no interactive auth, no window.
Old: clone `D:\Claude\sr0-r2b\clean` at origin/master d70d36bd (0.1.0 / MSIX 0.1.0.0). New: `clean2` at clone-local commit 5251e9f1 on d70d36bd (0.1.1 / 0.1.1.0, patch `/Volumes/D/sr0-artifacts/win/r2-msix/sliceapp-0.1.1.patch`: version fields + one Swift diagnostic string in WindowsBootstrap.swift).
Clone-local setup: `.right-release/` added to `.git/info/exclude` (build writes `.right-release/locks/win.lock.json` into the repo root before ownership's clean-tree check; repo needs a `.gitignore` entry), `core.autocrlf=false`, `core.symlinks=false`.

| Check | Result | Evidence |
|---|---|---|
| doctor | PASS | log-doctor7.txt (ownership ok, trust gate passed, no "not registered" error) |
| MSIX built old/new | PASS | SliceApp_0.1.0.0_x64.msix sha256 A2D6BC08A9AA573F46D79240AACF99C7D04DF9131A2B4D4A9AE77ECF5A63119E (28,898,260 B); SliceApp_0.1.1.0_x64.msix BB2031CAC1A53B555CD344B1F69E1DAC2D7693E9B286D1DC0627175DED86FD23 (28,898,270 B) |
| Signed + verify | PASS | both: Get-AuthenticodeSignature Valid, CN=Damned Ventures LLC, thumb 70C7267389389DE64BAF5A5A96BF215B5B44450F, RFC3161 timestamp; `signtool verify /pa` "Successfully verified", exit 0 |
| Renderer in package = pinned 0.6 DLL | PASS (see note) | stage copy sha256 777F14C4FF11822BF6E2174E127B3A4A325D83A6B322FA599C7FC4408B335441 (prepackage "sha256 matches pin"). Packaged DLL is Authenticode-signed by RightKit (certSize 14800, 11,793,872 B; raw sha256 FA5A48EE...DECF in 0.1.0, 35628CAC...E664 in 0.1.1). Its Authenticode digest 01063E20...A468 equals the pinned DLL's |
| Swift-only rebuild proof | PASS by manual check; `scripts/swift-only-proof.mjs` FAILS | Authenticode digests of every payload DLL identical old vs new; only SliceApp.exe differs (CB09594F... vs 08C2988B...); AppxManifest/BlockMap differ by version only; 0 cargo/rustc/Compiling lines in both build logs; changed sources contain no Rust inputs |

Defects found:
1. `swift-only-proof.mjs` and the `verify-package-layout.ps1 -Mode Installed` raw-sha-vs-pin check compare seal/payload raw sha256. RightKit Authenticode-signs every PE in the payload (new timestamp per build), so the seal hash of every DLL differs per build and never equals the pin. Both must compare the Authenticode digest (PE hash excluding checksum and certificate table) or the pre-sign stage hash. R5's installed check will fail on this until fixed.
2. `.right-release/` needs a `.gitignore` entry (see above).
3. `right-release release --tier patch ... --no-upload` fails with "build is tier-neutral"; use `right-release build --platform win --config ...` (sealed, no upload). PACKAGING.md's sealed-build command needs that change.
Artifacts: /Volumes/D/sr0-artifacts/win/r2-msix (msix, seals, logs, patch); Dell copies in `D:\Claude\sr0-r2b\artifacts\0.1.0`, `clean*/dist/win`.
