#!/bin/sh
# Compare an accepted/expected trace with a Windows trace using the UIACompare exe on Windows.
# Usage: compare-win.sh <accepted.json local path> <candidate.json Windows path> [extra args]
set -eu
cd "$(dirname "$0")/.."
exp=$1; cand=$2; shift 2
b64=$(base64 < "$exp" | tr -d '\n')
win "\$e=\$env:TEMP+'\\sr0o-expected.json'; [IO.File]::WriteAllBytes(\$e,[Convert]::FromBase64String('$b64')); \$env:Path='C:\Users\adrds\AppData\Local\Programs\Swift\Runtimes\6.4.0\usr\bin;'+\$env:Path; \$x=(Get-ChildItem D:\Claude\sr0o-uia\scratch -Recurse -Filter UIACompare.exe | ? { \$_.FullName -match 'Release' } | select -First 1).FullName; & \$x \$e '$cand' $*; 'exit=' + \$LASTEXITCODE"
