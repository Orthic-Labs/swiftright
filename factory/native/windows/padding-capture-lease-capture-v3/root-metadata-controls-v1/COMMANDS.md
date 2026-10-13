# Root commands

These commands use explicit paths & fresh output lanes. They do not invoke frozen r3 transport commands.

## 1. Dell: issue Count1 metadata

Run in PowerShell on Dell after root has actual compiler receipt, executable, & serializer hashes. `$CompileHash`, `$ExeHash`, & `$SerializerHash` are bare 64-hex hashes; builder preflight & frozen guard require serializer bare value.

```powershell
$ErrorActionPreference = 'Stop'
$repo = 'D:\Claude\swiftright'
$pkg = Join-Path $repo 'factory\native\windows\padding-capture-lease-capture-v3'
$CompileHash = '<actual compiler receipt SHA256>'
$ExeHash = '<actual executable SHA256>'
$SerializerHash = '952c75251160871870cb6d5f4a3af9d4ba2b8d204fbca40aa7fc437655af1bba'
$run = Join-Path $pkg 'actual-single-r1'
$issued = Join-Path $pkg 'coordinator-single-r1\issued-metadata.json'
& (Join-Path $pkg 'issue-before-launch.ps1') -Count 1 -RunRoot $run -OutputPath $issued -CompileReceiptSha256 $CompileHash -ExeSha256 $ExeHash -SerializerControlSha256 $SerializerHash
$IssuedHash = (Get-FileHash -LiteralPath $issued -Algorithm SHA256).Hash.ToLowerInvariant()
```

`issue-before-launch.ps1` must finish before any Process.Start. Keep old11/source-bound context (`candidateID=sr1-source-bound-r11-20261011`, `frozenTupleBound=false`); historical template tuple is metadata only.

## 2. Dell: run frozen full guard controls

```powershell
$controls = Join-Path $pkg 'root-metadata-controls-v1\actual\controls-r1'
$result = Join-Path $pkg 'root-metadata-controls-v1\actual\metadata-controls-r1.json'
& (Join-Path $pkg 'root-metadata-controls-v1\test-metadata-guard-controls.ps1') `
  -IssuedMetadataPath $issued -IssuedMetadataHash $IssuedHash -RunRoot $run -Count 1 `
  -CompileHash $CompileHash -ExeHash $ExeHash -SerializerHash $SerializerHash `
  -ProducerRoot $pkg -ControlRoot $controls -OutputPath $result
```

Expected output: actual admitted baseline, relocated-resealed admitted baseline, plus 11 rejected one-field faults; every fault has `outerMetadataResealed=true`, `nativeWindowActions=0`, & no compiler/GUI/remote/lock actions. Controls must fail if actual baseline rejects.

## 3. Dell: enumerate actual Count1 adapter closure & make fresh result bundle

Fourteen static Mac/canonical refs in `prelaunch-dependencies-manifest.json` are source inputs only. After Count1, adapter inputs must enumerate every transitive Windows raw/capture/exe/runtime/source/coordinator ref. Inputs must use repo-relative archive paths, exact `sha256`, & exact `bytes`; script rejects UNC, drive-relative, absolute, traversal, separator or colon paths; checks destination containment, conflicts, missing files, drift, manifest escape, or overwrite. It validates full source closure before creating transport files.

Run pure path controls before staging closure. This only dot-sources pinned guards & emits one fresh control receipt; it performs no source/archive writes, compiler/native, GUI, remote, or lock action:

```powershell
$pathControls = Join-Path $pkg 'root-metadata-controls-v1\test-transport-path-controls.ps1'
$pathControlOutput = Join-Path $pkg 'root-metadata-controls-v1\path-controls-r1.json'
if(Test-Path -LiteralPath $pathControlOutput){throw 'Fresh path-control output required'}
& $pathControls | Set-Content -Encoding UTF8 $pathControlOutput
```

Require `status=passed-source-only`, 14 named cases, `nativeWindowActions=0`, `lockActions=0`, & fresh output before continuing.

```powershell
$adapterInputs = '<explicit path to actual Count1 adapter inputs JSON>'
$transport = Join-Path $pkg 'root-metadata-controls-v1\actual\dell-dynamic-transport-r1'
$dynamicManifest = Join-Path $transport 'dynamic-input-transport-manifest.json'
& (Join-Path $pkg 'root-metadata-controls-v1\enumerate-and-stage-input-refs.ps1') `
  -AdapterInputsPath $adapterInputs -RepoRoot $repo -TransportRoot $transport -ManifestPath $dynamicManifest
```

Transfer resulting `adapter-count1-dynamic-transport.zip` plus printed SHA256 to Mac. Preserve zip contents & use a fresh destination.

## 4. Mac: consume Dell bundle with existing venv

```zsh
set -euo pipefail
repo=/Volumes/D/claude/swiftright
zip=/path/from/Dell/adapter-count1-dynamic-transport.zip
transport="$repo/factory/native/windows/settled-capture-adapter-v3/transport/adapter-count1-dynamic-result-r1"
if [ -e "$transport" ]; then echo "fresh destination required: $transport" >&2; exit 2; fi
mkdir -p "$transport"
unzip -q "$zip" -d "$transport"
test -f "$transport/inputs.json"
test -d "$transport/archive"
test -f "$transport/dynamic-input-transport-manifest.json"
cd "$repo"
factory/.venv/bin/python factory/native/windows/settled-capture-adapter-v3/run-adapter.py \
  --inputs "$transport/inputs.json" \
  --archive-root "$transport/archive" \
  --output "$transport/normalized.json"
```

CLI is verified as `run-adapter.py --inputs INPUTS --archive-root ARCHIVE --output OUTPUT`; output path must be new. Adapter remains observational (`qualified=false`).

## 5. Mac: validate actual tuple against local common.schema

```zsh
cd /Volumes/D/claude/swiftright
rootNonce='<issued metadata runID from coordinator-single-r1>'
sourceHash='<issued metadata sourceHash from coordinator-single-r1>'
schemaReceipt="$transport/mac-schema-validation-r1.json"
sourceBindingFile="$repo/factory/native/windows/padding-capture-lease-build-v1/metadata/source-binding.json"
sourceArchiveFile='<explicit Mac source archive manifest/file path>'
factory/.venv/bin/python factory/native/windows/padding-capture-lease-capture-v3/root-metadata-controls-v1/verify-common-schema.py \
  --tuple "$transport/archive/factory/native/windows/padding-capture-lease-capture-v3/coordinator-single-r1/candidate-tuple.json" \
  --schema factory/native/windows/settled-capture-adapter-v3/dependencies/common.schema.json \
  --root-nonce "$rootNonce" --source-hash "$sourceHash" \
  --source-binding-file "$sourceBindingFile" --source-archive-file "$sourceArchiveFile" > "$schemaReceipt"
```

This validates required tuple fields with local `common.schema.json`, requires exact old11 source-bound candidate ID, rejects frozen tuple binding, verifies explicit Mac source-binding bytes against original Windows ref, and emits hash-bound candidate tuple, schema, verifier tool, original source, actual Mac source archive, exit0, and rootNonce refs with no host action. Transfer receipt to Dell without changing bytes.

## 6. Dell: resume Count1 from admitted prelaunch folder

Transfer Mac schema receipt to Dell without changing its bytes. Then run prospective coordinator; frozen `coordinator.ps1` is not used because it would reissue into an already populated folder.

Place exact Mac `settled-capture-adapter-v3/dependencies/common.schema.json` beside capture package on Dell before launch; coordinator hashes this file against receipt.

```powershell
$schemaReceipt = '<explicit Dell path to transferred Mac schema receipt JSON>'
$schemaReceiptHash = (Get-FileHash -LiteralPath $schemaReceipt -Algorithm SHA256).Hash.ToLowerInvariant()
$guardHash = (Get-FileHash -LiteralPath $result -Algorithm SHA256).Hash.ToLowerInvariant()
& (Join-Path $pkg 'root-metadata-controls-v1\resume-issued-coordinator.ps1') `
  -Count 1 -CompileReceiptHash $CompileHash -ExeHash $ExeHash `
  -SerializerControlSha256 $SerializerHash -IssuedMetadataPath $issued `
  -IssuedMetadataHash $IssuedHash -GuardControlsPath $result `
  -GuardControlsHash $guardHash -MacSchemaReceiptPath $schemaReceipt `
  -MacSchemaReceiptHash $schemaReceiptHash
```

This source verifies issued metadata again, exact Count1 fresh run root, exact existing coordinator folder, guard receipt status plus 11 rejected faults, Mac `PASS_LOCAL_COMMON_SCHEMA` receipt, helper/source pins, and config freshness before silent CAS acquisition. Hidden task startup, retained worker handle, terminal result, exhaustive worker inventory, quiescence, and owned release remain identical to frozen coordinator.
