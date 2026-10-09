param([string]$P, [int]$N = 15)
Get-Content $P -Tail $N
Get-Process | Where-Object { $_.ProcessName -match 'swift|FreshOn' } | Select-Object Name, Id | Out-String
