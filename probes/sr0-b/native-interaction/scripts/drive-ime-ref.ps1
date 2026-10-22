# #45 reference host (experiment E1, second half): the same layout shift as F7live (a row inserted ABOVE the composing field while a REAL Microsoft Japanese IME
# composition is open), but in Microsoft Edge instead of SwiftRight. If Edge's open candidate/prediction list also stays where it was, the behaviour is the IME's
# for every application, not ours. Runs INSIDE the interactive desktop session (one-shot scheduled task, schedule-native.ps1 -Check ime-ref-edge).
# The page (written here) focuses an <input>; 6 s after compositionstart (after the romaji is typed and the list is open) it inserts a 60 CSS-px row above it and sets document.title to end in "moved".
# Edge runs as an --app window with a throwaway profile under the run folder (no user profile, no sync). Keys go through the same gated SendInput path.
param(
  [string]$Base = 'D:\Claude\sr0s-bridge06b',
  [string]$Out = 'D:\Claude\sr0s-bridge06b\result-native-ime-ref.txt',
  [string]$ExpectExe = '', [string]$ExpectDll = ''
)
. "$PSScriptRoot\native-common.ps1"
function Start-EventLog {
  if (-not ('SRN.EventLog' -as [type])) {
    $refs = @([System.Windows.Automation.AutomationElement].Assembly.Location, [System.Windows.Automation.ControlType].Assembly.Location, [System.Windows.Automation.TextPattern].Assembly.Location)
    Add-Type -TypeDefinition ([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'EventLog.cs'))) -ReferencedAssemblies $refs
  }
  [SRN.EventLog]::Start($script:Hwnd); Log 'event_log started'
}
function Stop-EventLog([string]$path) {
  if (-not ('SRN.EventLog' -as [type])) { return }
  $ev = [SRN.EventLog]::Stop()
  [IO.File]::WriteAllText($path, [string]::Join("`r`n", $ev), (New-Object Text.UTF8Encoding $false))
  Log "event_log stopped lines=$($ev.Count) -> $path"
}

$TIP_GUID = '{03B5835F-F03C-411B-9CE2-AA23E1171E36}'
Log "host=$env:COMPUTERNAME user=$env:USERNAME session=$((Get-Process -Id $PID).SessionId) reference=edge started=$(Get-Date -Format o)"
if ((Get-Process -Id $PID).SessionId -eq 0) { Add-Check 'interactive-session' 'FAIL' 'session 0'; Write-Result $Out 'ime-ref-edge'; exit 3 }
$jaHkls = [SRN.N]::JapaneseHkls()
if ($jaHkls.Count -eq 0) { Add-Check 'ime-installed' 'FAIL' 'no 0411 layout'; Write-Result $Out 'ime-ref-edge'; exit 3 }
$hklJa = ($jaHkls | Sort-Object { ((($_ -shr 16) -band 0xFFFF) -eq 0xE001) } -Descending | Select-Object -First 1)

$work = Join-Path (Split-Path -Parent $Out) ('ime-ref-' + (Get-Date -Format yyyyMMddHHmmss))
New-Item -ItemType Directory -Force -Path $work | Out-Null
$page = Join-Path $work 'page.html'
$html = @'
<!doctype html><html><head><meta charset="utf-8"><title>SwiftRight IME ref</title>
<style>body{margin:0;font:28px Segoe UI}#top{height:40px}input{font:28px Segoe UI;width:600px;margin:20px}</style></head>
<body><div id="top"></div><div id="rows"></div><input id="f" autofocus>
<script>
const f=document.getElementById('f'); let armed=true;
f.addEventListener('compositionstart',()=>{ if(!armed) return; armed=false; setTimeout(()=>{ const r=document.createElement('div'); r.style.height='60px'; r.textContent='inserted row'; document.getElementById('rows').appendChild(r); document.title='SwiftRight IME ref moved'; },6000); });
setInterval(()=>{ if(document.activeElement!==f) f.focus(); },200);
</script></body></html>
'@
[IO.File]::WriteAllText($page, $html, (New-Object Text.UTF8Encoding $false))
$edge = @("${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe", "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $edge) { Add-Check 'edge' 'FAIL' 'msedge.exe not found'; Write-Result $Out 'ime-ref-edge'; exit 3 }
$profileDir = Join-Path $work 'profile'
$script:Proc = Start-Process -FilePath $edge -ArgumentList @("--user-data-dir=`"$profileDir`"", '--no-first-run', '--no-default-browser-check', '--disable-sync', '--window-size=900,700', '--window-position=200,200', "--app=file:///$($page -replace '\\','/')") -PassThru
$sw = [Diagnostics.Stopwatch]::StartNew()
while ($sw.Elapsed.TotalSeconds -lt 30 -and $script:Hwnd -eq [IntPtr]::Zero) {
  foreach ($w in [SRN.N]::TopWindows()) { if ($w.Title -like 'SwiftRight IME ref*' -and $w.Visible) { $script:Hwnd = [IntPtr]$w.Hwnd; break } }
  Start-Sleep -Milliseconds 300
}
if ($script:Hwnd -eq [IntPtr]::Zero) { Add-Check 'edge-window' 'FAIL' 'no window titled SwiftRight IME ref'; Write-Result $Out 'ime-ref-edge'; exit 3 }
Log "edge_window hwnd=$($script:Hwnd.ToInt64())"
Start-Sleep -Seconds 2
$procIdOut = [uint32]0
$tid = [SRN.N]::GetWindowThreadProcessId($script:Hwnd, [ref]$procIdOut)
$layoutBefore = [SRN.N]::LayoutOfThread($tid)
if (-not (Ensure-Foreground)) { Add-Check 'foreground' 'FAIL' 'edge not foreground'; Write-Result $Out 'ime-ref-edge'; exit 3 }
[void][SRN.N]::PostMessage($script:Hwnd, [SRN.N]::WM_INPUTLANGCHANGEREQUEST, [IntPtr]0, [IntPtr]$hklJa)
Start-Sleep -Milliseconds 800
$r1 = [SRN.N]::ImeControl($script:Hwnd, [SRN.N]::IMC_SETOPENSTATUS, 1); Start-Sleep -Milliseconds 200
$r2 = [SRN.N]::ImeControl($script:Hwnd, [SRN.N]::IMC_SETCONVERSIONMODE, 9); Start-Sleep -Milliseconds 300
Log ("ime_switch rc=$r1/$r2 layout=0x{0:X8} open=$([SRN.N]::ImeControl($script:Hwnd, [SRN.N]::IMC_GETOPENSTATUS, 0)) conv=0x{1:X}" -f [SRN.N]::LayoutOfThread($tid), [SRN.N]::ImeControl($script:Hwnd, [SRN.N]::IMC_GETCONVERSIONMODE, 0))

# Every visible top-level window except Edge's own; the IME's list is whatever appears or moves once the composition opens (the Microsoft IME's list is an
# explorer-hosted ApplicationFrameWindow on Windows 11, found by hit test in the SwiftRight run, so no class filter is used).
function All-Wins {
  $o = @{}
  foreach ($w in [SRN.N]::TopWindows()) {
    if (-not $w.Visible -or $w.Hwnd -eq $script:Hwnd.ToInt64()) { continue }
    $o["$($w.Hwnd)"] = [pscustomobject]@{ Hwnd = $w.Hwnd; Pid = $w.Pid; Cls = $w.Cls; L = $w.VL; T = $w.VT; R = $w.VR; B = $w.VB }
  }
  return $o
}
$script:Base0 = $null
function Shot([string]$tag) {
  try {
    $me = [SRN.N]::TopWindows() | Where-Object { $_.Hwnd -eq $script:Hwnd.ToInt64() } | Select-Object -First 1
    $mg = 400; $x = [math]::Max(0, $me.VL - $mg); $y = [math]::Max(0, $me.VT - 100); $w = ($me.VR - $me.VL) + 2 * $mg; $h = ($me.VB - $me.VT) + 600
    $bmp = New-Object System.Drawing.Bitmap($w, $h); $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($x, $y, 0, 0, (New-Object System.Drawing.Size($w, $h))); $png = "$Out.$tag.png"
    $bmp.Save($png, [System.Drawing.Imaging.ImageFormat]::Png); $g.Dispose(); $bmp.Dispose(); Log "shot $tag origin=$x,$y size=$w x $h -> $png"
  } catch { Log "shot $tag error=$($_.Exception.Message)" }
}
function Ime-Wins([string]$tag) {
  $now = All-Wins
  if ($script:Base0 -eq $null) { $script:Base0 = $now; Log "$tag baseline windows=$($now.Count)"; return ,@() }
  $o = @()
  foreach ($k in $now.Keys) {
    $w = $now[$k]; $b = $script:Base0[$k]
    if ($b -eq $null -or $b.L -ne $w.L -or $b.T -ne $w.T -or $b.R -ne $w.R -or $b.B -ne $w.B) {
      $pn = '?'; try { $pn = (Get-Process -Id $w.Pid -ErrorAction Stop).ProcessName } catch { }
      $w | Add-Member -NotePropertyName Proc -NotePropertyValue $pn -Force
      $o += $w
      Log "$tag window hwnd=0x$('{0:X}' -f $w.Hwnd) proc=$pn class=$($w.Cls) rect=$($w.L),$($w.T),$($w.R),$($w.B) $(if ($b -eq $null) { 'new' } else { 'changed' })"
    }
  }
  if ($o.Count -eq 0) { Log "$tag no window appeared or moved" }
  return ,$o
}
Start-EventLog
$before = Ime-Wins 'before_typing'
foreach ($c in 'NIHONN'.ToCharArray()) { if (-not (Send-GatedKey ([uint16][int]$c) "romaji-$c" 150)) { break } }
Start-Sleep -Milliseconds 600
$open = Ime-Wins 'composition_open'
Shot 'composition_open'
$titleNow = { ([SRN.N]::TopWindows() | Where-Object { $_.Hwnd -eq $script:Hwnd.ToInt64() } | Select-Object -First 1).Title }
$sw = [Diagnostics.Stopwatch]::StartNew()
while ($sw.Elapsed.TotalSeconds -lt 10 -and -not ((& $titleNow) -like '*moved')) { Start-Sleep -Milliseconds 100 }
$moved = (& $titleNow) -like '*moved'
[SRN.EventLog]::Mark("page row inserted (title moved)")
Log "page_row_inserted=$moved after_ms=$($sw.ElapsedMilliseconds)"
Start-Sleep -Milliseconds 1000
$after = Ime-Wins 'after_move'
Shot 'after_move'
[void](Send-GatedKey 0x28 'down-after-move' 400)
$afterDown = Ime-Wins 'after_down'
Shot 'after_down'
$dpi = [SRN.N]::GetDpiForWindow($script:Hwnd); $shiftPx = [math]::Round(60 * $dpi / 96.0)
function Delta($a, $b) {
  foreach ($x in $a) { $y = $b | Where-Object { $_.Hwnd -eq $x.Hwnd } | Select-Object -First 1; if ($y) { return [pscustomobject]@{ Hwnd = $x.Hwnd; Dy = ($y.T - $x.T); Dx = ($y.L - $x.L) } } }
  return $null
}
$d1 = Delta $open $after; $d2 = Delta $open $afterDown
Log ("expected_shift_px=$shiftPx (60 css px at dpi $dpi) move_delta=" + $(if ($d1) { "dx=$($d1.Dx) dy=$($d1.Dy)" } else { 'no common window' }) + ' after_down_delta=' + $(if ($d2) { "dx=$($d2.Dx) dy=$($d2.Dy)" } else { 'no common window' }))
$state = if (-not $moved) { 'not-run' } elseif ($d1 -eq $null) { 'no-list' } elseif ([math]::Abs($d1.Dy - $shiftPx) -le 12) { 'followed' } elseif ([math]::Abs($d1.Dy) -le 2) { 'stayed' } else { 'other' }
Add-Check 'reference-edge-candidate-after-layout-move' 'PASS' "state=$state (diagnostic: followed = Edge moves the open list with the field; stayed = the IME leaves it, as in SwiftRight)"
foreach ($k in 1..3) { [void](Send-GatedKey 0x1B "escape-$k" 200) }
[void][SRN.N]::ImeControl($script:Hwnd, [SRN.N]::IMC_SETOPENSTATUS, 0)
[void][SRN.N]::PostMessage($script:Hwnd, [SRN.N]::WM_INPUTLANGCHANGEREQUEST, [IntPtr]0, [IntPtr]$layoutBefore)
Start-Sleep -Milliseconds 500
try { Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'msedge.exe' -and $_.CommandLine -match [regex]::Escape($profileDir) } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } } catch { }
Stop-EventLog "$Out.events.txt"
Write-Result $Out 'ime-ref-edge'
