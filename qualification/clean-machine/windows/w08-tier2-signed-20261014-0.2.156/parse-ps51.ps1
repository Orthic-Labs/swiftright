$f = 'C:\sbq\guard-0.2.156.ps1'
$o = [ordered]@{ psVersion = $PSVersionTable.PSVersion.ToString(); sha256 = (Get-FileHash $f -Algorithm SHA256).Hash.ToLower() }
$tokens = $null; $errs = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$tokens, [ref]$errs)
$o.parseErrors = @($errs | ForEach-Object { $_.Message + ' @' + $_.Extent.StartLineNumber })
$o.nonAscii = @([IO.File]::ReadAllBytes($f) | Where-Object { $_ -gt 127 }).Count
# Register-ScheduledTask acceptance of the guard's own task XML (Get-TaskXml evaluated from the script text; a throw-away task name, removed at once)
$src = Get-Content -LiteralPath $f -Raw
$m = [regex]::Match($src, '(?s)function Get-TaskXml.*?\r?\n\}\r?\n')
$PSCommandPath = 'C:\Users\x\AppData\Local\SliceApp\repair\repair-guard.ps1'
Invoke-Expression $m.Value
$name = 'OrthicLabs.ProofOnly_aaaaaaaaaaaaa-Repair-xmltest'
$xml = Get-TaskXml 'OrthicLabs.ProofOnly_aaaaaaaaaaaaa' $null
try { [void](Register-ScheduledTask -TaskName $name -Xml $xml -Force); $o.registerOk = $true; $x = Export-ScheduledTask -TaskName $name; $o.exported_has_EventRecordID_valuequery = [bool]($x -match 'EventRecordID'); $o.exported_action_args = ([regex]::Match($x, '<Arguments>(.*?)</Arguments>')).Groups[1].Value } catch { $o.registerOk = $false; $o.registerError = $_.Exception.Message }
finally { Unregister-ScheduledTask -TaskName $name -Confirm:$false -ErrorAction SilentlyContinue; $o.removed = -not [bool](Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue) }
$o | ConvertTo-Json -Depth 4
