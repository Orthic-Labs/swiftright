# Remaining-five source successor V5

V5 keeps V4 host witness, source, case, provider-hold & observation bytes. It replaces old r09 bridge dependency with owned `.factory-work\inputs\SwiftRightBridge` inputs pinned to bridge `0a745ab`, header `862997c` & exact ABI header hash. Runtime stays rolling `.factory-work\runtime-stage\runtime` at `37429120e7dd4e060ecf1a58a92ae3a7f4d2b12b`; renderer stays owned `.factory-work\inputs\renderer\swiftright_render.dll` at `e280f4a9fd9eca0a7b2657f72f8c322a537cee7b4c85999f6cbf7eb1f39ccc93`.

All five prospective packages target `D:\Claude\swiftright\.factory-work\hosts\<host>\package`, with separate fresh `build-v5-r1` scratch. V4 files & receipts remain unchanged. This packet has no compiler/native observations and grants no eligibility, provider, parity or tuple status; existing provider holds stay explicit.

`reviewed-v3-controls` preserves V3 control-tool bytes. Its source-scope membership control & actual JSON-array decoder controls are run as offline source checks. The V5 offline verifier independently binds each package’s exact source membership, case/witness, runtime receipt/tree, bridge manifest/header identities, renderer path/hash & compile request. `test_packet.py` covers stale r09 paths, changed bridge manifest/header, changed source/request, tool drift & qualification spoofing.

Root-owned Windows command design (no build was run for this packet):

```powershell
$repo='D:\Claude\swiftright'
$work=Join-Path $repo '.factory-work'
$tools=Join-Path $work 'hosts\remaining-five-v5-controls'
$packet=Join-Path $repo 'factory\native\windows\remaining-five-hosts-v5'
Copy-Item -Recurse -Force $packet $tools
foreach($host in @('disabled','image','shapes.fill-stroke','text.bundled-font','toggle')) {
  $destination=Join-Path $work "hosts\$host\package"
  New-Item -ItemType Directory -Force (Split-Path $destination)|Out-Null
  Copy-Item -Recurse -Force (Join-Path $packet "$host\package") $destination
}
& "$tools\reviewed-v3-controls\test-producer-source-scope.ps1" -OutputRoot "$tools\v3-source-scope-controls"
& "$tools\reviewed-v3-controls\test-json-array-shape.ps1" -OutputRoot "$tools\v3-json-array-controls"
& "$tools\run-controls.ps1"
& "$tools\parse-stream-controls.ps1" -Output "$tools\stream-parse.json"
& "$tools\run-stream-controls.ps1"
& "$tools\test-stream-admission.ps1" -OutputRoot "$tools\stream-admission-faults"
foreach($host in @('disabled','image','shapes.fill-stroke','text.bundled-font','toggle')) {
  $package=Join-Path $work "hosts\$host\package"
  & "$tools\build-hosts-v2.ps1" -Package $package -PreflightOnly
}
```

Each host may be compiled only after root reviews exact preflight receipts & gives next command. The build command is the same per host with `-PreflightOnly` omitted; no executable launch or native capture is part of this packet. Never remove or overwrite existing Dell staging.
