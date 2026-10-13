# V5 headless transfer & admission

This packet transfers five frozen V5 packages and their production controls into one versioned tool root plus exact per-host package roots under `D:\Claude\swiftright\.factory-work\hosts`. `transfer-bundle.json` pins source-stage files, five plan hashes, copied payload membership, and external runtime/compiler/renderer/bridge requirements. Transfer checks source-stage bytes, copied bytes, and every external file hash before any writes. Existing destinations cause a fail-closed stop; no destination is overwritten or deleted.

Run from the Windows checkout only after this folder and its parent V5 packet have been transferred intact:

```powershell
$packet='D:\Claude\swiftright\factory\native\windows\remaining-five-hosts-v5'
& (Join-Path $packet 'root-admission-r1\transfer-bundle.ps1')
$tools='D:\Claude\swiftright\.factory-work\hosts\remaining-five-v5-admission-r1'
& (Join-Path $tools 'root-admission-r1\admit-hosts.ps1')
```

Transfer validates source manifest `ef0853a00aca582f10f655b05946303190dfe608b76b01dc9810e2921de71950`, copied payload membership, and external dependencies named in `transfer-bundle.json`. Admission runs source-scope and JSON decoder fixtures, V5 pure production controls, stream/kernel controls and stream admission, then full builder preflight sequentially for `disabled`, `image`, `shapes.fill-stroke`, `text.bundled-font`, and `toggle`. The loop uses `$hostLabel`, avoiding PowerShell's reserved `$Host` variable.

Admission invokes each builder only with `-PreflightOnly`; it verifies `compilerStarted=false`, `nativeActions=0`, `outputCreated=false`, and `qualification=hold`. It does not invoke Swift package compilation or launch probes. Root can review resulting receipts before separately running any serialized build. Renderer, runtime and bridge inputs are external dependencies, not included as duplicate copies in this transfer bundle. Provider, parity and tuple qualifications remain held.
