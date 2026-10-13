# MTA Count1 r5 source stager

This packet is source-only. `stage_mta_count1_r5.py` derives fresh Text or Circle Count1 packages from explicit frozen r4 stage manifests & profile-owned `install-count1-r4.ps1` templates. It refuses existing outputs, symlinks, path traversal, donor drift, >256 files, >8 MiB file, or >32 MiB total. It does no discovery, execution, native launch, lock action, or compiler action.

Staging uses exact full path tokens (`admission-count1-r4`, `producer-count1-r4`, `overlay-count1-r4`, `count1-r4`) & exact donor `.work` namespace. It never performs broad `r1`/`r4` replacement, so `r10` cannot be corrupted. `producer/support/final-exit-certificate.ps1` remains renderer helper. Worker closure requires `producer/dependencies/uia-worker/invoke-worker-mta.ps1`, keeps worker final-exit helper distinct, reseals integration bindings after transformations, then writes source-inputs & computes its actual SHA256. Generated closure controls, profile integration controls, issuer, config, & coordinator preflight are all source package outputs; native/lock/compiler counts remain zero until root executes installer.

Root-run commands (choose fresh namespaces & paths, with no pre-existing outputs):

```powershell
python .\factory\pipeline\pilot-next-source-v1\mta-pilot-stage-v1\stage_mta_count1_r5.py --profile text --donor-root .\factory\native\windows\pilot-text-paint-root-v2\capture-count1-r4-sources --installer-template .\factory\native\windows\pilot-text-paint-root-v2\install-count1-r4.ps1 --output-root .\.factory-work\mta-pilot-stage-v1\text-r5-stage --output-zip .\.factory-work\mta-pilot-stage-v1\text-r5.zip --output-installer .\.factory-work\mta-pilot-stage-v1\install-text-r5.ps1 --namespace text-mta-r11-v5
python .\factory\pipeline\pilot-next-source-v1\mta-pilot-stage-v1\stage_mta_count1_r5.py --profile circle --donor-root .\factory\native\windows\pilot-circle-root-v1\capture-count1-r4-sources --installer-template .\factory\native\windows\pilot-circle-root-v1\install-count1-r4.ps1 --output-root .\.factory-work\mta-pilot-stage-v1\circle-r5-stage --output-zip .\.factory-work\mta-pilot-stage-v1\circle-r5.zip --output-installer .\.factory-work\mta-pilot-stage-v1\install-circle-r5.ps1 --namespace circle-mta-r11-v5
```

Installer commands are intentionally separate from staging. Root must review generated receipt, transport package & run each fresh installer on Dell. Installer expands once, verifies every manifest row, runs MTA closure & profile fault controls, copies fresh producer/admission/overlay roots only into collision-free namespace, recomputes installed source-inputs hash, issues metadata from measured refs, writes dynamic config, then invokes existing coordinator `-PreflightOnly`. No native action is claimed by this packet.

Frozen donor source remains untouched. Generated `*.receipt.json` beside each zip records donor/template hashes, stage bounds, package hash, installer hash, source-inputs hash, renderer/worker helper paths, & zero action counters.
