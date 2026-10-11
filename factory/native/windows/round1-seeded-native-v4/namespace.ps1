function Assert-RepeatNamespace([string]$Root,[string[]]$Expected){
 if(@($Expected|Select-Object -Unique).Count -ne $Expected.Count){throw 'Duplicate expected replay namespace'}
 $actual=@(Get-ChildItem -LiteralPath $Root -Force|ForEach-Object{$_.Name})
 if($actual.Count -ne $Expected.Count -or @($actual|Where-Object{$Expected -cnotcontains $_}).Count -ne 0){throw 'Replay namespace count/set drift'}
 foreach($name in $Expected){if(-not (Get-Item -LiteralPath (Join-Path $Root $name)).PSIsContainer){throw 'Replay namespace entry is not directory'}}
}
