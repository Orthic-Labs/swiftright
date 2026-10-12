# Fresh padding paired analysis v1

This packet prepares fresh repaired-case evidence for existing trusted reader/comparator. It emits `comparisonEligible=false` always; no parity, golden, qualification, or promotion claim is produced before trusted reader joins & 20 Mac + 20 Windows rows.

Minimum inputs:

* fresh case JSON, fresh staged package `plan.json`, fresh capture plan;
* fresh compile receipt with kernel/exit/stream proof & produced `FactoryProbe.exe`;
* fresh candidate tuple, issued Count20 metadata, normalized Windows20 captures, adapter-proof Count20;
* trusted reader Count20 report + archive, Mac20 comparator report + raw archive manifest/root.

Run after fresh compiler/capture materializers, before trusted comparison:

```powershell
$repo='D:\Claude\swiftright'
$case="$repo\factory\oracle\mac\padding-origin-r11-source-v1\generated\13bfe5b8fbd9\cases\swiftui.padding-frame.recipe.gate-seeded.ca4e13f820f5d258.r11.h13bfe5b8fbd9.json"
$stage="$repo\.factory-work\windows-replay-r11\fresh-case-v1"
$native="$repo\factory\native\windows\.work\windows-replay-r11\fresh-case-v1"
$mac="$repo\factory\oracle\mac\padding-origin-r11-source-v1\observed-mac20-r1"
$out="$repo\.factory-work\padding-case-rebuild-root-v1\paired-analysis-v1.json"
python "$repo\factory\pipeline\padding-case-rebuild-root-v1\paired-case-analysis-v1\materialize-paired-analysis-plan-v1.py" `
  --repo $repo --case $case --fresh-package-plan "$stage\package\plan.json" `
  --capture-plan "$native\producer\capture-plan.json" `
  --compile-receipt "$stage\package\build-fresh-r1\observation.json" `
  --executable "$stage\package\build-fresh-r1\FactoryProbe.exe" `
  --candidate-tuple "$native\coordinator\candidate-tuple.json" `
  --issued-metadata "$native\coordinator\issued-metadata.json" `
  --normalized "$native\proof\normalized-v12-r3.json" `
  --adapter-proof "$native\proof\adapter-proof-v12.json" `
  --reader-report "$native\reader\trusted-reader.json" `
  --mac-report "$mac\mac-only-production-comparator-r1.json" `
  --mac-root $mac --mac-manifest "$mac\raw-archive-manifest.json" `
  --reader-archive "$native\reader\archive" --output $out
```

Then invoke existing production route using paths recorded in emitted plan:

```powershell
$pair="$repo\factory\pipeline\paired-padding-r11-v12"
python "$pair\run-paired-comparison-v1.py" `
  --repo $repo --mac-root $mac --mac-manifest "$mac\raw-archive-manifest.json" `
  --reader-archive "$native\reader\archive" --case $case `
  --normalized "$native\proof\normalized-v12-r3.json" `
  --adapter-proof "$native\proof\adapter-proof-v12.json" `
  --reader-report "$native\reader\trusted-reader.json" `
  --mac-report "$mac\mac-only-production-comparator-r1.json" `
  --source-plan "$stage\package\plan.json" `
  --output "$native\paired-comparison-v1.json"
```

Run existing `test-paired-comparison-controls-v1.py` with same inputs. Expected output stays candidate-only, Count20, protected parity/golden hold. Fresh case equality must cover package plan, capture plan, issued metadata, candidate tuple, Mac report, normalized/proof captures, & every reader row.
