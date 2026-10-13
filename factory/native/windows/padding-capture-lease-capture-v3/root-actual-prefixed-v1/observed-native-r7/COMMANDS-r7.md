# Count1 r7 root invocation & production joins

Root runs below on Dell after cleanup receipt confirms no active prior root/config.

```powershell
$repo='D:\Claude\swiftright'
$here=Join-Path $repo 'factory\native\windows\padding-capture-lease-capture-v3'
$prefixed=Join-Path $here 'root-actual-prefixed-v1'
$overlay=Join-Path $here 'root-metadata-controls-v1\execute-r7'
$launcher=Join-Path $overlay 'coordinator-r7.ps1'
$pins=@{
 'coordinator-r7.ps1'='1d959f332c31d4843ed1217f5994c05f0e1df3a5801385c9fbbed9c08be39fd8'
 'interactive-task-r7.ps1'='25f18fab1c286c9f4f121e59ce0955b3c3a7d02b7bea5ce3d56b25dcdb4893b4'
 'dispatch-r7.ps1'='33acdf62c846895a4c0360068917b89d657ace5f4ba68d503a454ea77ed493d0'
 'capture-repeat-r7.ps1'='049c9d39d80a9c30017190cb57ab6e55093b3e65926e18a019e5b6aa3090b2e3'
 'integration-prefixed-ids-r1.ps1'='d4a20512937c6a7cb1e5751e02566276290897cb56203a99b40cfcccf486e904'
}
foreach($name in $pins.Keys){$p=Join-Path $overlay $name;if((Get-FileHash -LiteralPath $p).Hash.ToLowerInvariant() -cne $pins[$name]){throw "r7 source drift: $name"}}
$metadata=Join-Path $prefixed 'observed-count1-metadata-r3\coordinator-single-r1\issued-metadata.json'
& $launcher `
 -CompileReceiptHash '1847f82af0c1d02452d816ca5051787e865afb5be50147d57065c0c37f93e4cf' `
 -ExeHash '3d3171b6d6be0447d4c34cd7f8ee5f74332bd1e9eeb24f62f9b1057332d8d10a' `
 -SerializerControlSha256 '952c75251160871870cb6d5f4a3af9d4ba2b8d204fbca40aa7fc437655af1bba' `
 -IssuedMetadataPath $metadata `
 -IssuedMetadataHash '81f5dfd3d0424d2b01b9462081b70fabff4d92a725f5aa36e04396c9124ce523' `
 -GuardControlsPath (Join-Path $prefixed 'observed-count1-metadata-r3\root-actual-prefixed-count1-r3\metadata-controls-count1-r1.json') `
 -GuardControlsHash '209e2780203450333f7720a7c35eb28859081dd2b15e8d2ff8891d4156064543f' `
 -MacSchemaReceiptPath (Join-Path $prefixed 'observed-count1-metadata-r3\coordinator-single-r1\mac-schema-receipt-r1.json') `
 -MacSchemaReceiptHash '6fc3fa0405ce9e68d1793b6659af84943c81c00a153e2312ace2d5024c5094d9' `
 -Count 1
```

After root transports actual r7 output, update map with actual refs & run producer:

```sh
factory/.venv/bin/python factory/native/windows/settled-capture-adapter-v3/count1-inputs-r3/produce-count1-inputs-r3.py \
  --archive-root . \
  --input-map factory/native/windows/padding-capture-lease-capture-v3/root-actual-prefixed-v1/observed-native-r7/count1-input-map-r7.actual.json \
  --output factory/native/windows/padding-capture-lease-capture-v3/root-actual-prefixed-v1/observed-native-r7/adapter-inputs-r7.actual.json
factory/.venv/bin/python factory/native/windows/settled-capture-adapter-v3/count1-inputs-r3/run-adapter-v4.py \
  --archive-root . \
  --inputs factory/native/windows/padding-capture-lease-capture-v3/root-actual-prefixed-v1/observed-native-r7/adapter-inputs-r7.actual.json \
  --output factory/native/windows/padding-capture-lease-capture-v3/root-actual-prefixed-v1/observed-native-r7/adapter-output-r7.actual.json
```

Attach 13-role production proofs from actual run bytes & exact compiler archive before F10:

```sh
factory/.venv/bin/python factory/native/windows/settled-capture-adapter-v3/count1-inputs-r3/windows-exit-proof-r1/build-windows-exit-proof-r1.py \
  --source-root . \
  --captures factory/native/windows/padding-capture-lease-capture-v3/root-actual-prefixed-v1/observed-native-r7/adapter-output-r7.actual.json \
  --input-map factory/native/windows/padding-capture-lease-capture-v3/root-actual-prefixed-v1/observed-native-r7/count1-input-map-r7.actual.json \
  --compiler factory/native/windows/padding-capture-lease-capture-v3/root-actual-prefixed-v1/compiler-byte-archive-r1.json \
  --require-complete \
  --output factory/native/windows/padding-capture-lease-capture-v3/root-actual-prefixed-v1/observed-native-r7/windows-proof-bundle-r7.actual.json
```

Before F10 reader, create fresh manifest containing exact adapter capture hashes joined to Windows archive directories:

```sh
factory/.venv/bin/python factory/pipeline/paired-padding-origin-fresh-v3-operational-v1/f10-trusted-reader-v1/trusted-reader-report.py \
  --input factory/pipeline/paired-padding-origin-fresh-v3-operational-v1/f10-trusted-reader-v1/root-actual-prefixed-v1-input-r7.json \
  --output factory/pipeline/paired-padding-origin-fresh-v3-operational-v1/f10-trusted-reader-v1/root-actual-prefixed-v1-report-r7
```

F10 input must bind Mac report `factory/pipeline/paired-padding-origin-fresh-v3-operational-v1/run-33877/report.json`, typed Windows proof bundle output, Mac archive roots/path map, & exact `windowsArchives` keys equal to 20 typed capture canonical hashes. Reader invokes `factory.gate.windows_exit_admission.verify_windows_exit_admission` for each capture; output remains observational until semantic/timing review.
