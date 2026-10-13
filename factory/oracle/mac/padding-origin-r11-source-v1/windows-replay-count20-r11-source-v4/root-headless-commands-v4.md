# Root-controlled Count20 r11 headless sequence

Root transports every v4 file plus frozen dependency rows from `source-map-v4.json` into `D:\Claude\swiftright\factory\native\windows\padding-capture-lease-capture-v3\root-metadata-controls-v4\repeat-r11\`. Keep `ProducerRoot` as actual compiled producer package root. This stage layout makes custom integration guard resolve `..\\..\\support\\integration.ps1` to frozen support bytes.

Set paths only from measured receipts/archives:

```powershell
$ProducerRoot = 'D:\Claude\swiftright\factory\native\windows\padding-capture-lease-capture-v3'
$OverlayRoot = Join-Path $ProducerRoot 'root-metadata-controls-v4\repeat-r11'
$NamespaceRoot = Join-Path $ProducerRoot '.factory-work\windows-replay-r11'
$ControlRoot = Join-Path $NamespaceRoot 'coordinator-repeat-r11'
$OutputRoot = Join-Path $NamespaceRoot 'actual-repeat-r11'
$RunRoot = $OutputRoot
$Issued = Join-Path $ControlRoot 'issued-metadata.json'
$FreshGuard = Join-Path $ControlRoot 'fresh-guard.json'
$MetadataGuard = '<actual full metadata guard receipt path>'
$MacSchema = '<actual Mac schema receipt path>'
$Case = '<transported fresh case JSON path>'
$Tuple = '<transported fresh tuple packet path>'
$Manifest = '<transported fresh manifest path>'
$Equivalence = '<transported v4 equivalence receipt path>'
$Plan = '<actual producer plan JSON path>'
$Receipt = '<actual compiler receipt JSON path>'
$Exe = '<actual measured executable path>'
$Renderer = '<actual measured renderer path>'
$Canonical = '<actual canonical-inputs manifest path>'
$Binding = '<actual source-binding JSON path>'
```

Run v4 issuer before any coordinator, lock, or native action. Supply hashes from `Get-FileHash` over transported bytes; do not type digest literals.

```powershell
& (Join-Path $OverlayRoot 'issue-count20-fresh-r11-v4.ps1') -FreshCasePath $Case -FreshTuplePath $Tuple -FreshManifestPath $Manifest -EquivalencePath $Equivalence -ActualPlanPath $Plan -ActualReceiptPath $Receipt -ExecutablePath $Exe -RendererPath $Renderer -CanonicalInputsPath $Canonical -SourceBindingPath $Binding -NamespaceRoot $NamespaceRoot -RunRoot $RunRoot -OutputPath $Issued -CompileReceiptSha256 ((Get-FileHash $Receipt).Hash.ToLower()) -ExeSha256 ((Get-FileHash $Exe).Hash.ToLower()) -PlanSha256 ((Get-FileHash $Plan).Hash.ToLower()) -SerializerControlSha256 '<measured serializer hash>' -Count 20
```

Run v4 guard with same measured inputs, then require its JSON hash before launch gate:

```powershell
& (Join-Path $OverlayRoot 'guard-count20-fresh-r11-v4.ps1') -IssuedMetadataPath $Issued -IssuedMetadataHash ((Get-FileHash $Issued).Hash.ToLower()) -FreshCasePath $Case -FreshTuplePath $Tuple -FreshManifestPath $Manifest -EquivalencePath $Equivalence -ActualPlanPath $Plan -ActualReceiptPath $Receipt -ExecutablePath $Exe -ControlOutputPath $FreshGuard -RunRoot $RunRoot -CompileReceiptSha256 ((Get-FileHash $Receipt).Hash.ToLower()) -ExeSha256 ((Get-FileHash $Exe).Hash.ToLower()) -PlanSha256 ((Get-FileHash $Plan).Hash.ToLower()) -Count 20
```

Run `launch-count20-fresh-r11-v4.ps1` with v4 stage manifest, full metadata-control receipt, Mac schema receipt, custom integration guard path/hash, producer/control/output/run roots, then root may invoke coordinator. Launch gate must finish before lock acquisition. Every child receives same fresh guard lineage & namespace roots.
