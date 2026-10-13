# MTA Count20 source stage

`stage_mta_count20.py` creates fresh Text or Circle Count20 source packages from an explicit admitted Count1 r5 stage, an exact successful Count1 coordinator certificate, & Count20 lifecycle sources. It verifies certificate bytes/hash, requires Count1 `count=1`, successful status, `lockReleased=true`, `wholeBatchExitConfirmed=true`, parent kernel proof, measured source/issued/compile/exe hashes, then copies certificate into fresh admission. It stages real Count20 coordinator/interactive/dispatch/capture sources, retains profile-specific Count1 capture guard body, installs & reseals MTA worker contract, refreshes transformed build-preflight/capture-plan/integration/worker identity hashes, runs pinned MTA config/UIA production controls, keeps renderer & worker final-exit helpers distinct, emits fresh overlay source rows, & never creates `runRoot` before dispatch.

No native, compiler, lock, remote, or test action is performed. Root must review package, transport it, run installer, then run Count20 preflight/effects.

```powershell
python .\factory\pipeline\pilot-next-source-v1\mta-pilot-count20-stage-v1\stage_mta_count20.py --profile text --donor-root .\path\to\text-count1-r5-stage --count1-certificate .\path\to\count1-coordinator.json --count1-certificate-sha256 <64hex> --count1-certificate-bytes <bytes> --lifecycle-root .\factory\pipeline\pilot-next-source-v1\count20-lifecycle-v1 --output-root .\.factory-work\mta-pilot-count20-stage-v1\text-r5-stage --output-zip .\.factory-work\mta-pilot-count20-stage-v1\text-r5.zip --output-installer .\.factory-work\mta-pilot-count20-stage-v1\install-text-r5.ps1 --namespace text-mta-r11-count20-r5
.\install-text-r5.ps1 -PackagePath D:\\Claude\\swiftright\\.factory-work\\hosts\\text-mta-count20-r5.zip
```

Circle uses `--profile circle` with its own admitted Count1 donor. Installer temp roots stay under `hosts\text-baseline` or `hosts\circle`. Paths are explicit, fresh, collision-refusing, bounded to 256 files/8 MiB each/32 MiB total.
