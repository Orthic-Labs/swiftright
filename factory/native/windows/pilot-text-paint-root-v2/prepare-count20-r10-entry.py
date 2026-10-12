"""Seal bounded Text Count20 installer entry; no remote or native actions."""
import base64
import hashlib
import json
from pathlib import Path

root = Path(__file__).resolve().parent
cache = Path('/Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/git-root')
installer = cache / 'install-text-count20-r10-root-v3.ps1'
package = cache / 'text-count20-r10-root-v3.zip'
assert installer.stat().st_size < 131072 and package.stat().st_size < 2097152
raw = installer.read_bytes()
digest = hashlib.sha256(raw).hexdigest()
remote_installer = r'D:\Claude\swiftright\.factory-work\root-tools\text-count20-r10-installer.ps1'
remote_package = r'D:\Claude\swiftright\.factory-work\root-tools\text-count20-r10-root-v3.zip'
control = r'D:\Claude\swiftright\factory\native\windows\.work\text-mta-r11-count20-r10\control-count20-r10'

def quote(s):
    return "'" + s.replace("'", "''") + "'"

entry = "$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'\n"
entry += '$f=' + quote(remote_installer) + ";if(Test-Path $f){throw 'fresh installer required'}\n"
entry += '[IO.File]::WriteAllBytes($f,[Convert]::FromBase64String(' + quote(base64.b64encode(raw).decode()) + '))\n'
entry += 'if((Get-FileHash $f).Hash.ToLowerInvariant() -cne ' + quote(digest) + "){throw 'installer pin mismatch'}\n"
entry += '$tokens=$null;$errors=$null;[void][Management.Automation.Language.Parser]::ParseFile($f,[ref]$tokens,[ref]$errors);if($errors.Count){throw ($errors|Out-String)}\n'
entry += '& $f -PackagePath ' + quote(remote_package) + '\n'
entry += 'Get-Content -Raw -LiteralPath ' + quote(control + r'\package-preflight.json') + '\n'
with (root / 'admission-count20-r10-entry.ps1').open('x') as f:
    f.write(entry)
with (root / 'install-count20-r10-root-v3.ps1').open('xb') as f:
    f.write(raw)
receipt = dict(installerSha256=digest, installerBytes=len(raw), packageSha256=hashlib.sha256(package.read_bytes()).hexdigest(), packageBytes=package.stat().st_size, nativeActions=0)
with (root / 'count20-r10-entry-pins.json').open('x') as f:
    json.dump(receipt, f, indent=2)
    f.write('\n')
print(json.dumps(receipt))
