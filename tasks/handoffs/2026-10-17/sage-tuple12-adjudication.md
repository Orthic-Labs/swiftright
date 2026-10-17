# Sage (Opus 5.5) tuple 12 adjudication, 2026-10-17

Relayed verbatim by swiftright-a6 (session 49644702-cd60-4ca0-a22d-85e40dcb1213) to the new lead on 2026-10-17. Read-only adjudication: git blobs, local receipts, a lockfile parse. Sage ran nothing on the Dell.

## Tuple 12 adjudication (#17, #18, #20)

All three conflicts can be fixed without Adrian, but B1 lands somewhere neither option expected. The pinned EXE was not built from db08e1a1 either. The stage commit should be **a9556b77f**.

**What I found that changes B1**
- The receipt `build-r4-receipt.json` names `overlayCommit db08e1a1`. But the r4 source it actually built is the 91-file transport manifest `f45b9e0d` (`out/tuple12-startupguard-build-v1/transport-manifest-r4.json`), which records `overlayRevision 2` and overlay manifest `0d537b83` (`qualification/tuple12-startupguard-overlay-r2.json`).
- Its `StartupGuard.swift` is `05f2f684`. That file comes from a9556b77f ("import bridge types in SR0 startup guard"). db08e1a1 has `fdd0f3c5`.
- Checked against that manifest, a9556b77f differs in only 4 files, and none of them is compiled: `build-fresh.ps1` (one added exit check), `stage-tuple.ps1`, `verify-manifest.ps1`, and `qualification/renderer-actual-review.json`. db08e1a1 has those 4 plus `StartupGuard.swift`. HEAD has 37 differences.
- All 16 files in the reviewed set that gets copied to the Dell (`tuple12-stage-takeover-r1/transfer-manifest-r2.json`) match the a9556b77f (and db08e1a1) copies exactly. This includes the SliceApp `F73BE078`.
- Renderer: the recovered `Cargo.lock` (`0e28d8bb`) and the source lock (`a8716a98`) parse to the same 720 package entries (lockfile v4), with the same name, version, source, checksum and dependency lists. You said 721; the parse gives 720 distinct entries. The C62B554B DLL is recorded as `historicalArtifactMissing: true` (`tuple12-renderer-recovery-v1/source-manifest.json`). The sealed path on the Dell is `D:\Claude\swiftright\.work\sr0-stage-inputs\swiftright_render.dll`.

**1. B1, stage commit**
- The canonical stage is **a9556b77f50315afcae27fc8fc44c0cd274959e2**. Its code identity is base 0e201571 plus overlay r2 (`0d537b83`), which is source manifest `f45b9e0d`.
- Options (i) db08e1a1 and (ii) 0e201571 are both rejected: neither contains the source that built the EXE. 0e201571 also has the pre-hardening stage scripts.
- The 320/320 matrix, the 301/320 cross recordings and the F1 receipts stay valid. They are tied to the EXE, renderer and `f45b9e0d` hashes, all unchanged.
- The stage keeps EXE `87b8cb27` as the tuple member, because the r4 receipt already ties it to its source. If the stage's rebuild hashes differently (likely, since the build path differs), record that as a reproducibility note. It does not mean a re-pin.

**2. B2, renderer**
- The recovered DLL (`7578cd5d…`, 11,887,616 B) is admitted as the tuple 12 renderer.
- Admission rule to record: a lock rewritten by the broker is admissible only if it parses to the same lockfile version and the same set of package entries (name, version, source, checksum, dependencies) as the source lock. Byte order and whitespace may differ, all 11 non-lock source files must match byte for byte, and both lock hashes are recorded.
- Stage input path is the sealed copy above. The managed `ws\…\g\00x` paths are not pins.

**3. B3, lines to correct before the stage runs**
- **Do not edit scripts.** `resume-tuple.ps1:8-10` and `audit-tuple.ps1:7-9` must stay identical to the a9556b77f copies, or the reviewed set stops matching. Pass explicit `-Commit a9556b77f… -RendererDll <sealed path> -ExpectRenderer 7578CD5D…` on the audit (`docs/sr0-tuple12-staging.md:40`), resume (`:52`) and restart (`:60`) commands.
- `docs/sr0-tuple12-staging.md:9` should read a9556b77f. Line 11 should be the sealed path. Line 31 should copy from a9556b77f and check against `transfer-manifest-r2.json`.
- `docs/sr0-tuple12-startupguard-staging.md:3` and `:5` should cite overlay r2 (`0d537b83`). Line 20's receipt path does not exist yet; use the seal receipt. Line 23 should name a9556b77f, not "commit the overlay".
- Correct the db08e1a1 reference in `build-r4-receipt.json` by an addendum next to it. Do not rewrite the receipt.
- In `docs/sr0-tuple12-qualification.md`, keep `--source-commit 0e201571` at lines 36, 84 and 125, since those tie recorded receipts. Line 7 gains the a9556b77f stage identity.
- Update `docs/sr0-status.md:15` (it still says "RECOVERED-BUT-UNADMITTED" and the stale `e1d7816a→7ae3c084`) and PENDING rows A, A1 and C.

**4. SliceApp override**
- It may be used. `F73BE078` is the committed copy at db08e1a1 and a9556b77f, not unreviewed drift.
- Its differences from 0e201571 only tighten the script: it resolves the app from `$Base`, adds exit checks for `--show-bin-path` and `dumpbin`, and uses a unique verify directory. I read that diff, and it counts as the review record.
- The HEAD copy (`f10d4560`) is not admitted for this stage.

**5. What proceeds now, and what waits for Adrian**
- **Proceeds now:** the doc corrections and the decision record; the parse preflight, audit, and the build-only canonical stage at a9556b77f (no GUI, no tasks, no deletion), after the Dell process/task/lock audit and messages to the peer sessions; filling the tuple pins; the analyzers.
- **Check Adrian's own words first:** the scope of his pause is recorded only as "paused on Adrian's order" (`docs/sr0-status.md:7`). Quote it via `pulse chat said` before any Dell GUI run (smoke, pixels, TextGeom/Modal/ColdOpen, R9, R10). If it covers only cross recordings, those runs may go ahead under the desktop lock.
- **Waits for Adrian:** the 19 remaining cross recordings (F7 r11, F8 r20, F9 r4-20), W08 acceptance (#19), and any publication.
- **Separate hold:** the Mac 20-run references for F2-F9 are held on the no-prompt signer.
- **Certificate:** PENDING row 7 approves short-lived Azure reissue with "no fixed expiry deadline". That covers new signing, unless reissue needs interactive Azure login, which is forbidden and would make it Adrian's step. Whether the 14 Oct MSIX timestamps verify is unknown; check before package qualification.

**Decision text for `docs/sr1-decisions.md`** (it already holds dated Sage adjudications; add one line to `docs/sr0-status.md` pointing to it):

> ## 17 October: tuple 12 stage identity and renderer admission (Sage adjudication; issues #17, #18, #20)
> Canonical tuple 12 stage commit is `a9556b77f50315afcae27fc8fc44c0cd274959e2`: its compiled closure equals source manifest `f45b9e0d…` (base `0e201571` + overlay r2 `0d537b83…`), which built FreshOnBridge `87b8cb27…` (r4); the r4 receipt's `overlayCommit db08e1a1` names overlay r1 and is superseded, since db08e1a1 carries StartupGuard `fdd0f3c5`, not the built `05f2f684`. Neither 0e201571 nor db08e1a1 is a valid stage. FreshOnBridge `87b8cb27…` stays the tuple member; a non-identical stage rebuild is recorded as a reproducibility note, not a re-pin. Windows Full16 x20 320/320 and cross x20 301/320 stay valid (bound to EXE, renderer and `f45b9e0d`). Renderer `7578cd5d…` (11,887,616 B, staged from `D:\Claude\swiftright\.work\sr0-stage-inputs\swiftright_render.dll`) is admitted under this rule: a broker-rewritten Cargo.lock is admissible only if it parses to the same lockfile version and the same set of package entries (name, version, source, checksum, dependencies) as the source lock, with all non-lock closure files byte-identical; `a8716a98…` and `0e28d8bb…` satisfy it (720 entries each, v4). Stage scripts and SliceApp `build-windows.ps1` (`f73be078…`) are the a9556b77f copies and stay unedited; resume and audit get explicit `-Commit`, `-RendererDll` and `-ExpectRenderer`. Cross recordings stay paused pending Adrian; W08 stays open pending #19.

**Reopen if any of these happen:**
- The stage clone at a9556b77f differs from `f45b9e0d` in any compiled file, or the Swift toolchain hash differs from `1e406093…`.
- The sealed DLL or lock hashes differ on the Dell, or any change touches `render/` or the lock beyond reordering.
- Any file in the copied script set differs from `transfer-manifest-r2.json`.
- A tuple 12 receipt binds an EXE other than `87b8cb27…`.
- Adrian's quoted pause covers more than cross recordings.
- Azure reissue needs interactive authentication.

## swiftright-a6 context notes (same relay)

`pulse` is not on this Mac's PATH, so the `pulse chat said` check could not be run. Dell check (read-only, SSH): sr0-stage-inputs holds the DLL 7578CD5D... (11,887,616 B) and Cargo.lock 0E28D8BB... (181,537 B); D:\Claude\swiftright\.work\sr0-r12 does not exist; desktop.lock reads free; C:\sbq\state is empty; the override set .work\sr0-stage-tools has 16 files of which 14 match transfer-manifest-r2.json and two differ (verify-artifacts.ps1 manifest d412213c vs Dell ec56c548; verify-manifest.ps1 dab18b0e vs d0d6e0b4) plus manifest.json and transfer-manifest.json present only on the Dell. Also posted on issues #17 and #18.
