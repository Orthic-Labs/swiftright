# OBSOLETE (2026-10-10): the SR0O_RELEASE_FLAG gate is now in probes/sr0-s/fresh-on-bridge/Sources/FreshOnBridge/SelfTest.swift
# (releaseSignalPresent), so the normal FreshOnBridge build honours it. Kept for the history of the w6 trace.
throw 'build-fob.ps1 is obsolete: build FreshOnBridge normally; SelfTest.swift carries the release gate'
# Builds a copy of FreshOnBridge whose F1 self-test waits for an external release signal (file named by SR0O_RELEASE_FLAG)
# before releasing the fake engine's insert-above. Everything else is the unchanged staged source. The original exe is untouched.
param([string]$Base = 'D:\Claude\sr0s-bridge', [string]$Out = 'D:\Claude\swiftright\.work\sr0o-f1',
      [string]$Dll = 'D:\Claude\sr0b-abi0\payload\bin\swiftright_render.dll')
$ErrorActionPreference = 'Stop'
$env:Path = 'C:\Users\adrds\AppData\Local\Programs\Swift\Runtimes\6.4.0\usr\bin;' + [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
$src = "$Base\probes\sr0-s\fresh-on-bridge"
$dst = "$Base\probes\sr0-s\fob-f1cross"
robocopy $src $dst /E /XD .build scratch /NFL /NDL /NJH /NJS | Out-Null
$f = "$dst\Sources\FreshOnBridge\SelfTest.swift"
$t = [IO.File]::ReadAllText($f)
$old = '.wait("insert-above pending") { self.pendingHas("insert-above") },'
$new = '.wait("insert-above pending") { self.pendingHas("insert-above") && self.releaseSignalPresent() },'
if (-not $t.Contains($old)) { throw 'F1 wait line not found' }
$t = $t.Replace($old, $new)
$anchor = '    private func pendingHas(_ key: String) -> Bool { engine.pendingKeys.contains(key) }'
if (-not $t.Contains($anchor)) { throw 'anchor not found' }
$helper = $anchor + "`n" + '    /// SR0-O F1 cross: harness release signal. Unset env = release immediately (original behaviour).' + "`n" + '    private func releaseSignalPresent() -> Bool {' + "`n" + '        guard let p = ProcessInfo.processInfo.environment["SR0O_RELEASE_FLAG"], !p.isEmpty else { return true }' + "`n" + '        return FileManager.default.fileExists(atPath: p)' + "`n" + '    }'
$t = $t.Replace($anchor, $helper)
[IO.File]::WriteAllText($f, $t)
"patched $f"
Set-Location $dst
$dep = "/MANIFESTDEPENDENCY:type='win32' name='Microsoft.Windows.Common-Controls' version='6.0.0.0' processorArchitecture='*' publicKeyToken='6595b64144ccf1df' language='*'"
$scratch = "$Out\scratch-fob"
& swift build -c release --scratch-path $scratch "-Xlinker" "/MANIFEST:EMBED" "-Xlinker" $dep 2>&1 | ForEach-Object { $_.ToString() }
"swift build exit=$LASTEXITCODE"
$bin = (& swift build -c release --scratch-path $scratch --show-bin-path).Trim()
Copy-Item $Dll $bin -Force
"bin=$bin"
Get-ChildItem $bin | Where-Object { $_.Extension -in ".exe", ".dll" } | ForEach-Object { "{0} {1}" -f $_.Name, $_.Length }
