$ErrorActionPreference='Stop'
$root='D:\Claude\swiftright\factory\native\windows\padding-settled-capture-v1'
$files=@('coordinator-single-r1\coordinator.json','coordinator-single-r1\task-result.json','actual-single-r1\batch.json','actual-single-r1\run-001\capture-outcome.json','actual-single-r1\run-001\owned-process.json','actual-single-r1\run-001\owned-close.json')
$records=@()
foreach($name in $files){$file=Join-Path $root $name;if(Test-Path -LiteralPath $file){$records+=@{path=$name;sha256=(Get-FileHash -LiteralPath $file).Hash.ToLowerInvariant();content=Get-Content -LiteralPath $file -Raw}}}
$owned=@(Get-CimInstance Win32_Process|Where-Object{$_.ExecutablePath -and $_.ExecutablePath.StartsWith('D:\Claude\swiftright\.factory-work\hosts\padding-settled\',[StringComparison]::OrdinalIgnoreCase)}|Select-Object ProcessId,ParentProcessId,CreationDate,ExecutablePath)
@{lock=(Get-Content 'D:\Claude\desktop.lock' -Raw).Trim();records=$records;ownedProcesses=$owned;nativeActions=0}|ConvertTo-Json -Depth 12
