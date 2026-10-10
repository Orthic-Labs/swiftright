# W5 step 2: interleaved Intel (GpuPreference=1) vs RTX (GpuPreference=2) runs of the unchanged workload, per-app Windows graphics preference for WorkloadWin.exe only.
# Records the registry value before and after; restores the original state (absent -> removed) in a finally block.
param([string]$Base = 'D:\Claude\sr0-r08\workload', [string]$ExpectDll = 'E280F4A9FD9ECA0A7B2657F72F8C322A537CEE7B4C85999F6CBF7EB1F39CCC93',
      [string]$Order = 'I,R,I,R,I,R', [string]$Prefix = 'w5ab')
$exe = (Get-Content -Raw "$Base\build.json" | ConvertFrom-Json).exe
$key = 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences'
$out = "$Base\runs\w5"; New-Item -ItemType Directory -Force $out | Out-Null
function Cur { $p = Get-ItemProperty $key -Name $exe -ErrorAction SilentlyContinue; if ($p) { $p.$exe } else { '<absent>' } }
$before = Cur
"$((Get-Date).ToString('o')) exe=$exe before=$before" | Add-Content "$out\pref-log.txt"
$n = @{ I = 0; R = 0 }
try {
  foreach ($s in $Order.Split(',')) {
    $n[$s]++; $val = if ($s -eq 'I') { 'GpuPreference=1;' } else { 'GpuPreference=2;' }
    Set-ItemProperty -Path $key -Name $exe -Value $val -Type String
    "$((Get-Date).ToString('o')) set $s -> $(Cur)" | Add-Content "$out\pref-log.txt"
    $tag = "$Prefix-$s$($n[$s])"
    & "$Base\probes\sr0-b\workload\scripts\run-workload.ps1" -Base $Base -ExpectDll $ExpectDll -Runs 1 -Tag $tag *> "$out\$tag.console.txt"
    "$((Get-Date).ToString('o')) finished $tag" | Add-Content "$out\pref-log.txt"
  }
} finally {
  if ($before -eq '<absent>') { Remove-ItemProperty -Path $key -Name $exe -ErrorAction SilentlyContinue } else { Set-ItemProperty -Path $key -Name $exe -Value $before -Type String }
  "$((Get-Date).ToString('o')) restored, after=$(Cur)" | Add-Content "$out\pref-log.txt"
}
