# SR0 lane R9 (b): Narrator against the ABI 0.6 FreshOnBridge F8 fixture (every row has a field and a Delete button).
# Runs INSIDE an interactive desktop session (one-shot scheduled task, schedule-native.ps1).
#
# What can and cannot be verified without a person (no audio is captured):
#   * Narrator starts, and its UIA event registration is visible (UiaClientsAreListening false -> true, no driver listener yet).
#   * Our provider raises focus / value / structure events with the right control type, name and AutomationId (an independent
#     UIA listener in this process; it proves the provider, not Narrator).
#   * Narrator-caused effects: Narrator commands are typed through the gated global SendInput path (Narrator key = Caps Lock).
#     The driver performs NO UIA action (no SetFocus, no Invoke) between the first Narrator command and the activation, so a
#     focus move onto the Delete button and the removal of its row can only come from Narrator. The removal is read back as
#     model state (UIA tree, and the exe's EVT lines after exit: source=ax invoke, state remove, disappear).
#   * Narrator SPEECH (what it announces) is checked from an audio loopback transcript (scripts/listen-loopback.ps1, WASAPI loopback of the
#     default render endpoint + offline System.Speech phrase/dictation grammars, #23): check narrator-speech-content.
# Narrator's prior state is recorded and restored: the run refuses to start if Narrator is already running.
param(
  [string]$Base = 'D:\Claude\sr0s-bridge06b',
  [string]$Out = 'D:\Claude\sr0s-bridge06b\result-native-narrator.txt',
  [Parameter(Mandatory)][string]$ExpectExe,
  [Parameter(Mandatory)][string]$ExpectDll
)
. "$PSScriptRoot\native-common.ps1"
$ready = "$Out.ready"
# #46: the words Narrator spoke inside ONE time window of the loopback WAV (PCM16 mono, 44-byte header, written by listen-loopback.ps1). The WAV is cut to [StartMs, EndMs] and recognised alone
# with a CLOSED grammar of the few words the lane expects (no dictation): System.Speech dictation returns garbage on Narrator's fast one-word utterances ("League swygert"), a closed grammar
# returns them at 0.94-0.95 confidence (measured on the Dell, narrator46-e). Results below MinConf are rejection noise (0.03-0.10 on slices without the word) and are dropped.
# Narrator speaks without gaps, so segment start times cannot separate steps; the window does.
function Recognize-WavSlice([string]$Wav, [int]$StartMs, [int]$EndMs, [string[]]$Words, [double]$MinConf = 0.5) {
  $bytes = [IO.File]::ReadAllBytes($Wav); $rate = [BitConverter]::ToInt32($bytes, 24)
  $a = 44 + 2 * [int][math]::Floor([math]::Max(0, $StartMs) * $rate / 1000.0); $b = [math]::Min($bytes.Length, 44 + 2 * [int][math]::Floor($EndMs * $rate / 1000.0))
  $a = [math]::Min($a, $bytes.Length); $n = $b - $a
  if ($n -lt [int]($rate / 2)) { return [pscustomobject]@{ Words = @(); Seconds = [math]::Round($n / 2.0 / $rate, 2); Error = 'slice shorter than 250 ms' } }
  $tmp = "$Wav.slice-$StartMs-$EndMs.wav"
  $fs = [IO.File]::Create($tmp); $w = New-Object IO.BinaryWriter($fs)
  $w.Write([Text.Encoding]::ASCII.GetBytes('RIFF')); $w.Write([int](36 + $n)); $w.Write([Text.Encoding]::ASCII.GetBytes('WAVEfmt ')); $w.Write([int]16); $w.Write([int16]1); $w.Write([int16]1)
  $w.Write([int]$rate); $w.Write([int]($rate * 2)); $w.Write([int16]2); $w.Write([int16]16); $w.Write([Text.Encoding]::ASCII.GetBytes('data')); $w.Write([int]$n); $w.Write($bytes, $a, $n); $w.Flush(); $fs.Close()
  Add-Type -AssemblyName System.Speech
  $heard = New-Object System.Collections.Generic.List[string]; $err = ''
  try {
    $culture = [System.Globalization.CultureInfo]::GetCultureInfo('en-US')
    $rec = New-Object System.Speech.Recognition.SpeechRecognitionEngine($culture)
    $ch = New-Object System.Speech.Recognition.Choices; foreach ($q in $Words) { $ch.Add($q) }
    foreach ($count in 1, 2) {   # one word, or two in a row ("edit delete")
      $gb = New-Object System.Speech.Recognition.GrammarBuilder; $gb.Culture = $culture
      foreach ($i in 1..$count) { $gb.Append($ch) }
      $rec.LoadGrammar((New-Object System.Speech.Recognition.Grammar($gb)))
    }
    $rec.SetInputToWaveFile($tmp)
    $nulls = 0
    while ($true) {
      try { $r = $rec.Recognize() } catch [System.Management.Automation.MethodInvocationException] { if ($_.Exception.InnerException -is [System.InvalidOperationException]) { break } else { throw } }
      if ($null -eq $r) { $nulls++; if ($nulls -gt 6) { break } else { continue } }
      $nulls = 0
      if ($r.Confidence -ge $MinConf) { $heard.Add(('{0}({1:N2})' -f $r.Text, $r.Confidence)) }
    }
    $rec.Dispose()
  } catch { $err = $_.Exception.Message }
  Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
  return [pscustomobject]@{ Words = @($heard); Seconds = [math]::Round($n / 2.0 / $rate, 2); Error = $err }
}
# #46 timing model: key steps are stamped with Stopwatch.GetTimestamp() (QPC ticks, one system-wide clock), the same clock the listener
# uses for its capture start (ready file: qpc= freq=) and for placing packets in the WAV (qpcPos). WAV offset ms = (step - capStart) * 1000 / freq.
$script:Marks = New-Object System.Collections.Generic.List[object]
function Mark([string]$name) { $t = [Diagnostics.Stopwatch]::GetTimestamp(); $script:Marks.Add([pscustomobject]@{ Name = $name; Qpc = $t; Utc = [DateTime]::UtcNow.ToString('o') }); return $t }
$script:CapQpc = $null; $script:CapFreq = $null; $script:CapUtc = ''
$VK_CAPS = [uint16]0x14; $VK_RIGHT = [uint16]0x27; $VK_ENTER = [uint16]0x0D; $VK_TAB = [uint16]0x09

Log "host=$env:COMPUTERNAME user=$env:USERNAME session=$((Get-Process -Id $PID).SessionId) started=$(Get-Date -Format o)"
if ((Get-Process -Id $PID).SessionId -eq 0) { Add-Check 'interactive-session' 'FAIL' 'session 0: not an interactive desktop'; Write-Result $Out 'narrator'; exit 3 }
if (-not (Verify-Tree $Base $ExpectExe $ExpectDll)) { Add-Check 'artifacts' 'FAIL' 'exe or renderer hash differs from the pinned tuple'; Write-Result $Out 'narrator'; exit 3 }

# ------------------------------------------------------------ prior state
# Registry backup/restore of every Narrator-touched key (full subtrees, with value kinds). The before-snapshot is logged AND written to
# "$Out.regbackup.txt" (one line per value: key|name|kind|base64 of the value) so an interrupted run can still be undone by hand.
$script:RegRoots = @('Software\Microsoft\Narrator', 'Software\Microsoft\Windows NT\CurrentVersion\Accessibility')
function Reg-Val($k, [string]$n) {
  $kind = $k.GetValueKind($n).ToString()
  $v = $k.GetValue($n, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
  $enc = switch ($kind) {
    'Binary' { [Convert]::ToBase64String([byte[]]$v) }
    'MultiString' { [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($v -join "`n"))) }
    default { [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes([string]$v)) }
  }
  return [pscustomobject]@{ Kind = $kind; Enc = $enc; Raw = $v }
}
function Reg-Walk([string]$sub, $acc) {
  $k = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($sub, $false)
  if ($k -eq $null) { $acc[$sub] = $null; return }
  try {
    $vals = @{}; foreach ($n in $k.GetValueNames()) { $vals[$n] = (Reg-Val $k $n) }
    $acc[$sub] = $vals
    foreach ($s in $k.GetSubKeyNames()) { Reg-Walk "$sub\$s" $acc }
  } finally { $k.Close() }
}
function Snap-Reg { $acc = @{}; foreach ($r in $script:RegRoots) { Reg-Walk $r $acc }; return $acc }   # key -> $null (absent) or name -> {Kind,Enc,Raw}
function Reg-Sig($vals) { if ($vals -eq $null) { return '<absent>' }; return (($vals.Keys | Sort-Object | ForEach-Object { "$_=$($vals[$_].Kind):$($vals[$_].Enc)" }) -join ';') }
function Reg-Save([string]$file, $snap) {
  $lines = foreach ($k in ($snap.Keys | Sort-Object)) {
    if ($snap[$k] -eq $null) { "$k|<key-absent>" } else { "$k|<key-present>"; foreach ($n in ($snap[$k].Keys | Sort-Object)) { "$k|$n|$($snap[$k][$n].Kind)|$($snap[$k][$n].Enc)" } }
  }
  [IO.File]::WriteAllText($file, [string]::Join([Environment]::NewLine, @($lines)), (New-Object Text.UTF8Encoding $false))
}
# Restore: set every saved value back (same kind), remove values that Narrator added, remove subkeys that did not exist before (and a root
# that did not exist before). Returns a list of what was done.
function Reg-Restore($before) {
  $done = @()
  $now = Snap-Reg
  foreach ($sub in @($now.Keys | Sort-Object { $_.Length } -Descending)) {   # deepest first, for deletions
    if (-not $before.ContainsKey($sub) -and $now[$sub] -ne $null) {
      try { [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree($sub, $false); $done += "deleted-key:$sub" } catch { $done += "delete-failed:$sub" }
    }
  }
  foreach ($sub in @($before.Keys | Sort-Object { $_.Length })) {
    $bv = $before[$sub]
    if ($bv -eq $null) {
      try { [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree($sub, $false); $done += "deleted-key:$sub" } catch { }
      continue
    }
    $k = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($sub)
    try {
      foreach ($n in $k.GetValueNames()) { if (-not $bv.ContainsKey($n)) { $k.DeleteValue($n, $false); $done += "deleted-value:$sub\$n" } }
      foreach ($n in $bv.Keys) {
        $cur = $null; try { $cur = (Reg-Val $k $n) } catch { }
        if ($cur -eq $null -or $cur.Kind -ne $bv[$n].Kind -or $cur.Enc -ne $bv[$n].Enc) {
          $kind = [Microsoft.Win32.RegistryValueKind]$bv[$n].Kind
          $val = $bv[$n].Raw
          $k.SetValue($n, $val, $kind); $done += "restored:$sub\$n"
        }
      }
    } finally { $k.Close() }
  }
  return $done
}
$nvda = (Get-Process -Name nvda -ErrorAction SilentlyContinue) -ne $null -or (Test-Path "$env:ProgramFiles\NVDA\nvda.exe") -or (Test-Path "${env:ProgramFiles(x86)}\NVDA\nvda.exe")
Add-Check 'nvda' 'INFO' $(if ($nvda) { 'NVDA is present on this host but is NOT driven by this lane (not requested; out of scope here)' } else { 'NVDA is not installed: out of scope for this lane (not installed by the driver, per instruction)' })

$narBefore = @(Get-Process -Name 'Narrator*' -ErrorAction SilentlyContinue)
if ($narBefore.Count -gt 0) {
  Add-Check 'narrator-prior-state' 'NOT-RUN' "Narrator is already running (pids $(($narBefore | ForEach-Object { $_.Id }) -join ',')): the run refuses to disturb a Narrator session in use. Stop Narrator and rerun."
  Write-Result $Out 'narrator'; exit 3
}
$pidsBefore = @(Get-Process | ForEach-Object { $_.Id })
$capsBefore = ([SRN.N]::GetKeyState(0x14) -band 1)
$regBefore = Snap-Reg
try { Reg-Save "$Out.regbackup.txt" $regBefore; Log "registry_backup_file=$Out.regbackup.txt values=$(($regBefore.Values | ForEach-Object { if ($_ -ne $null) { $_.Count } else { 0 } } | Measure-Object -Sum).Sum)" } catch { Log "registry_backup_failed: $($_.Exception.Message)" }
foreach ($k in ($regBefore.Keys | Sort-Object)) { if ($regBefore[$k] -eq $null) { Log "reg_before $k <absent>" } else { foreach ($n in ($regBefore[$k].Keys | Sort-Object)) { Log "reg_before $k\\$n kind=$($regBefore[$k][$n].Kind) b64=$($regBefore[$k][$n].Enc)" } } }
$listenBefore = [SRN.N]::UiaClientsAreListening()
Add-Check 'narrator-prior-state' 'INFO' "narrator_running=False caps_lock_on=$capsBefore uia_clients_listening=$listenBefore registry_keys_snapshotted=$($regBefore.Keys.Count)"

# ------------------------------------------------------------ audio loopback listener (separate child process, same interactive session)
$listenWav = "$Out.listen.wav"; $listenJson = "$Out.listen.json"; $listenReady = "$Out.listen.ready"; $listenStop = "$Out.listen.stop"
$listenLog = "$Out.listen.out.txt"; $listenErr = "$Out.listen.err.txt"
# What the run makes Narrator say: the Row 3 field (Name 'Row 3', role edit; focused by the driver while Narrator runs, value 'AX value')
# and the Delete button reached by Caps Lock + Right (Name 'Delete', role button). Digits get a spoken variant for the recognizer.
$listenPhrases = @('Delete', 'button', 'Delete button', 'Row 3', 'Row three', 'Row 3 edit', 'Row three edit', 'edit', 'AX value')
$listenProc = $null; $listenStartErr = ''
foreach ($f in @($listenWav, $listenJson, $listenReady, $listenStop, $listenLog, $listenErr)) { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue }
try {
  $lArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$PSScriptRoot\listen-loopback.ps1`" -Wav `"$listenWav`" -Json `"$listenJson`" -Seconds 420 -ReadyFile `"$listenReady`" -StopFile `"$listenStop`" -Phrases `"$($listenPhrases -join '|')`""
  $listenProc = Start-Process -FilePath "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList $lArgs -PassThru -WindowStyle Hidden -RedirectStandardOutput $listenLog -RedirectStandardError $listenErr
  $sw = [Diagnostics.Stopwatch]::StartNew()
  while ($sw.ElapsedMilliseconds -lt 45000 -and -not (Test-Path -LiteralPath $listenReady) -and -not $listenProc.HasExited) { Start-Sleep -Milliseconds 200 }
  if (-not (Test-Path -LiteralPath $listenReady)) {
    $le = ''; if (Test-Path -LiteralPath $listenErr) { $le = ((Get-Content -LiteralPath $listenErr -ErrorAction SilentlyContinue | Select-Object -First 3) -join ' ') }
    $listenStartErr = "listener did not start capture within 45 s (exited=$($listenProc.HasExited)): $le"
    if (-not $listenProc.HasExited) { Stop-Process -Id $listenProc.Id -Force -ErrorAction SilentlyContinue }
    $listenProc = $null
  } else { Start-Sleep -Milliseconds 500 }
} catch { $listenStartErr = "listener launch exception: $($_.Exception.Message)"; $listenProc = $null }
if ($listenProc -ne $null -and (Test-Path -LiteralPath $listenReady)) {
  try {
    $rt = (Get-Content -LiteralPath $listenReady -Raw)
    if ($rt -match 'qpc=(\d+)\s+freq=(\d+)\s+utc=(\S+)') { $script:CapQpc = [int64]$Matches[1]; $script:CapFreq = [int64]$Matches[2]; $script:CapUtc = $Matches[3] }
    if ($script:CapFreq -ne [Diagnostics.Stopwatch]::Frequency) { $script:CapQpc = $null }   # different clock base: offsets would be meaningless
  } catch { $script:CapQpc = $null }
}
Log "listener capture_start qpc=$($script:CapQpc) freq=$($script:CapFreq) utc=$($script:CapUtc)"
Log "listener proc=$(if ($listenProc) { $listenProc.Id } else { 'none' }) wav=$listenWav json=$listenJson start_error=[$listenStartErr]"

$row3Focused = $false; $nav = $null
$tNarStart = $null; $tReached = $null; $tFocusSeen = $null; $tAct = $null
$tap = $null; $narStarted = $false; $reached = $false; $gone = $false; $uuid6 = $null; $moved = $false
try {
  # ---------------------------------------------------------- Narrator first: its startup must not eat the exe script's 40 s step timers
  $tNarStart = Mark 'narrator-start'
  [void](Start-Process -FilePath "$env:WINDIR\System32\Narrator.exe" -PassThru)
  $narStarted = $true
  $sw = [Diagnostics.Stopwatch]::StartNew(); $running = $false; $listening = $false
  while ($sw.ElapsedMilliseconds -lt 15000) {
    $running = (@(Get-Process -Name 'Narrator' -ErrorAction SilentlyContinue)).Count -gt 0
    $listening = [SRN.N]::UiaClientsAreListening()
    if ($running -and $listening) { break }
    Start-Sleep -Milliseconds 250
  }
  Start-Sleep -Milliseconds 2500
  $narPids = @(Get-Process -Name 'Narrator*' -ErrorAction SilentlyContinue | ForEach-Object { $_.Id })
  $narWins = @([SRN.N]::TopWindows() | Where-Object { $narPids -contains [int]$_.Pid -and $_.Visible } | ForEach-Object { "$($_.Cls)|$($_.Title)|$($_.L),$($_.T),$($_.R),$($_.B)" })
  Log "narrator pids=[$($narPids -join ',')] visible_windows=[$($narWins -join '; ')]"
  if ($running -and $listening -and -not $listenBefore) { Add-Check 'narrator-started-uia-listening' 'PASS' "Narrator process running, UiaClientsAreListening false -> true with no driver listener registered yet (startup took $($sw.ElapsedMilliseconds) ms)" }
  elseif ($running -and $listenBefore) { Add-Check 'narrator-started-uia-listening' 'FAIL-not-automatable' 'another UIA client was already listening before Narrator started, so Narrator cannot be attributed from this flag' }
  else { Add-Check 'narrator-started-uia-listening' 'FAIL' "running=$running listening=$listening (Narrator did not start or registered no UIA listener within 15 s)" }
  if (-not $running) { throw 'narrator-not-running' }

  # ---------------------------------------------------------- fixture F8 (setup is driver-initiated UIA, as scripts/drive-fixture.ps1 F8)
  $script:Root = Start-Fixture $Base 'F8' $ready
  if ($script:Root -eq $null) { throw 'no probe window' }
  $tap = New-Object SRN.UiaTap($script:Root, $script:Proc.Id)
  $tap.Start()
  [void](Invoke-El (Find-Named 'Insert above' ([System.Windows.Automation.ControlType]::Button) 15000) 'Insert above')
  [void](Wait-Element { Edit 'Row 101' } 'inserted row 101 (Toolbar 0)' 30000)
  Set-Value 'Row 3' 'AX value'; [void](Wait-Value 'Row 3' 'AX value')
  [void](Focus-Edit 'Row 3')
  Start-Sleep -Milliseconds 1200
  $e3 = Edit 'Row 3'; $id3 = $e3.Current.AutomationId
  $row3Focused = ((Focused-Info).Id -eq $id3)   # Row 3 held focus while Narrator was running, so Narrator should have announced it
  $uuid6 = Row-Uuid (Edit 'Row 6'); $delId = "row/$uuid6/delete"
  $evs = $tap.Snapshot()
  $f3 = @($evs | Where-Object { $_.Kind -eq 'focus' -and $_.Id -eq $id3 })
  Add-Check 'provider-focus-event-role-and-id' $(if ($f3.Count -ge 1 -and $f3[0].Type -eq 'ControlType.Edit') { 'PASS' } else { 'FAIL' }) "focus events for Row 3 field ($id3): count=$($f3.Count) type=$($f3 | ForEach-Object { $_.Type } | Select-Object -First 1) name=[$($f3 | ForEach-Object { $_.Name } | Select-Object -First 1)] (listener in this process; shows the provider raises focus events with the right role; independent of Narrator)"
  $v3 = @($evs | Where-Object { $_.Kind -like 'prop:*Value*' -and $_.Id -eq $id3 -and $_.Extra -eq 'AX value' })
  Add-Check 'provider-value-changed-event' $(if ($v3.Count -ge 1) { 'PASS' } else { 'FAIL' }) "ValueProperty change events for Row 3 carrying the new value=$($v3.Count)"
  $tc = @($evs | Where-Object { $_.Kind -like '*TextChanged*' -and $_.Id -eq $id3 }).Count
  $sc = @($evs | Where-Object { $_.Kind -like '*TextSelectionChanged*' }).Count
  Add-Check 'provider-text-events' 'INFO' "TextChanged events for Row 3=$tc, TextSelectionChanged events (any)=$sc (recorded only; AccessKit decides which text events it raises)"

  # ---------------------------------------------------------- keyboard navigation: Tab (expected product gap, see report)
  $beforeTab = Focused-Info
  [void](Send-GatedKey $VK_TAB 'tab-1' 500); [void](Send-GatedKey $VK_TAB 'tab-2' 500)
  $afterTab = Focused-Info
  Add-Check 'tab-moves-focus-between-controls' $(if ($afterTab.Id -ne $beforeTab.Id -and $afterTab.Pid -eq $script:Proc.Id) { 'PASS' } else { 'FAIL' }) "focus before=[$($beforeTab.Id)] after two Tab presses=[$($afterTab.Id)] pid=$($afterTab.Pid). Source reading: the fixture host's key handler only counts key events (BridgeBackend.handle .key) and no Tab traversal exists in the renderer, so FAIL here is a product gap, not an automation fault."
  if ((Focused-Info).Id -ne $id3) { [void](Focus-Edit 'Row 3'); Start-Sleep -Milliseconds 800 }   # setup action, before Narrator commands begin

  # ---------------------------------------------------------- Narrator commands (no UIA actions from here to the activation)
  $startFocus = Focused-Info
  $mark = $tap.Count
  $nav = New-Object System.Collections.Generic.List[string]
  for ($i = 1; $i -le 22; $i++) {
    $tKey = Mark "narrator-next-$i"
    if (-not (Send-GatedChord @($VK_CAPS) $VK_RIGHT "narrator-next-$i" 450)) { break }
    $f = Focused-Info
    $nav.Add("${i}:$($f.Type -replace 'ControlType\.','')|$($f.Name)|$($f.Id)|pid=$($f.Pid)")
    if ($f.Id -ne $startFocus.Id) { $moved = $true }
    if ($f.Id -eq $delId) { $reached = $true; $tReached = $tKey; $tFocusSeen = Mark 'delete-focus-observed'; break }
    if ($i -ge 6 -and -not $moved) { break }
  }
  Log "narrator_nav start=[$($startFocus.Id)] target=[$delId] steps=[$($nav -join ' ; ')]"
  $focusEvs = @($tap.Snapshot() | Select-Object -Skip $mark | Where-Object { $_.Kind -eq 'focus' })
  $delFocus = @($focusEvs | Where-Object { $_.Id -eq $delId })
  if ($reached) {
    $okRole = ($delFocus.Count -ge 1 -and $delFocus[0].Type -eq 'ControlType.Button' -and $delFocus[0].Name -eq 'Delete')
    Add-Check 'narrator-moved-focus-to-delete-button' $(if ($okRole) { 'PASS' } else { 'FAIL' }) "Narrator next-item commands (Caps Lock + Right, no driver UIA action) moved system focus onto the Delete button of Row 6 after $($nav.Count) commands; focus event type=$($delFocus | ForEach-Object { $_.Type } | Select-Object -First 1) name=[$($delFocus | ForEach-Object { $_.Name } | Select-Object -First 1)]; focus events seen during navigation=$($focusEvs.Count)"
  } elseif (-not $moved) {
    Add-Check 'narrator-moved-focus-to-delete-button' 'FAIL-not-automatable' "system focus never left [$($startFocus.Id)] after $($nav.Count) injected Caps Lock + Right commands. This cannot be told apart from Narrator ignoring injected (LLKHF_INJECTED) keystrokes, or Narrator's focus-follows-cursor setting being off: a person must press the Narrator commands. Trace: $($nav -join ' ; ')"
  } else {
    Add-Check 'narrator-moved-focus-to-delete-button' 'FAIL' "focus moved but never reached the Row 6 Delete button within $($nav.Count) commands. Trace: $($nav -join ' ; ')"
  }

  # ---------------------------------------------------------- Narrator activate (Caps Lock + Enter) -> model state
  if ($reached) {
    $tAct = Mark 'narrator-activate'
    [void](Send-GatedChord @($VK_CAPS) $VK_ENTER 'narrator-activate' 400)
    $gone = Wait-Element { if ((Edit 'Row 6') -eq $null) { 'gone' } else { $null } } 'Row 6 removed by Narrator activation' 5000
    Add-Check 'narrator-activate-changes-model-state' $(if ($gone) { 'PASS' } else { 'FAIL' }) "after Caps Lock + Enter on the focused Delete button: Row 6 present in the UIA tree=$(-not $gone) (model state is confirmed from the exe's EVT lines after exit)"
  } else {
    Add-Check 'narrator-activate-changes-model-state' 'NOT-RUN' 'the Delete button was not reached by Narrator navigation'
    # driver fallback so the exe's script can finish; NOT counted as Narrator evidence
    [void](Invoke-El (Find-Id $delId 3000) 'driver fallback: Delete (row 6)')
  }
}
catch { Log "driver_exception: $($_.Exception.Message)"; Add-Check 'driver-run' 'FAIL' "exception: $($_.Exception.Message)" }
finally {
  if ($tap -ne $null) { $tap.Stop() }
  # ---------------------------------------------------------- stop Narrator, restore its prior state
  $exitPath = 'not-attempted'
  if ($narStarted) {
    # own exit path first: Narrator key + Escape through the same gated, probe-foreground-only input path; kill only as a fallback
    if (@(Get-Process -Name 'Narrator*' -ErrorAction SilentlyContinue).Count -gt 0 -and $script:Hwnd -ne [IntPtr]::Zero -and -not $script:Proc.HasExited) {
      [void](Send-GatedChord @($VK_CAPS) 0x1B 'narrator-exit' 500)
      $sw = [Diagnostics.Stopwatch]::StartNew()
      while ($sw.ElapsedMilliseconds -lt 6000 -and @(Get-Process -Name 'Narrator*' -ErrorAction SilentlyContinue).Count -gt 0) { Start-Sleep -Milliseconds 250 }
      $exitPath = if (@(Get-Process -Name 'Narrator*' -ErrorAction SilentlyContinue).Count -eq 0) { 'own-exit-caps+esc' } else { 'own-exit-failed' }
    }
    if (@(Get-Process -Name 'Narrator*' -ErrorAction SilentlyContinue).Count -gt 0) {
      Get-Process -Name 'Narrator*' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
      $exitPath += '+killed'
    }
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($sw.ElapsedMilliseconds -lt 8000 -and @(Get-Process -Name 'Narrator*' -ErrorAction SilentlyContinue).Count -gt 0) { Start-Sleep -Milliseconds 250 }
    Start-Sleep -Milliseconds 1500
  }
  $stillRunning = @(Get-Process -Name 'Narrator*' -ErrorAction SilentlyContinue).Count
  if ($listenProc -ne $null) { try { Set-Content -LiteralPath $listenStop -Value (Get-Date -Format o) } catch { } }   # Narrator is gone: end the recording; the listener transcribes while the registry settles
  $listenAfter = [SRN.N]::UiaClientsAreListening()
  # Windows (AtBroker / Narrator exit handlers) rewrites ATConfig\narrator asynchronously after exit: wait for the registry to settle, restore, verify, retry.
  function Reg-DiffDetail($bf, $af) {   # value-level differences: "key\name(before->after)"
    $o = @()
    foreach ($k in ($bf.Keys + $af.Keys | Sort-Object -Unique)) {
      $bv = $bf[$k]; $av = $af[$k]
      if ($bv -eq $null -and $av -eq $null) { continue }
      if ($bv -eq $null -or $av -eq $null) { $o += "$k(key-" + $(if ($bv -eq $null) { 'added' } else { 'removed' }) + ')'; continue }
      foreach ($n in ($bv.Keys + $av.Keys | Sort-Object -Unique)) {
        $x = $bv[$n]; $y = $av[$n]
        if ($x -eq $null -or $y -eq $null -or $x.Kind -ne $y.Kind -or $x.Enc -ne $y.Enc) { $o += "$k\$n(" + $(if ($x -eq $null) { 'absent' } else { "$($x.Kind):$($x.Raw)" }) + '->' + $(if ($y -eq $null) { 'absent' } else { "$($y.Kind):$($y.Raw)" }) + ')' }
      }
    }
    return $o
  }
  function Reg-Settle([int]$maxMs) {   # snapshot repeatedly until two consecutive snapshots are identical
    $sw = [Diagnostics.Stopwatch]::StartNew(); $prev = Snap-Reg; $prevSig = (($prev.Keys | Sort-Object | ForEach-Object { "$_|$(Reg-Sig $prev[$_])" }) -join "`n")
    while ($sw.ElapsedMilliseconds -lt $maxMs) {
      Start-Sleep -Milliseconds 700
      $cur = Snap-Reg; $sig = (($cur.Keys | Sort-Object | ForEach-Object { "$_|$(Reg-Sig $cur[$_])" }) -join "`n")
      if ($sig -eq $prevSig) { return $cur }
      $prev = $cur; $prevSig = $sig
    }
    return $prev
  }
  $regAfter = Reg-Settle 6000; $regDiff = @(); $regRestored = @()
  foreach ($k in ($regBefore.Keys + $regAfter.Keys | Sort-Object -Unique)) { if ((Reg-Sig $regBefore[$k]) -ne (Reg-Sig $regAfter[$k])) { $regDiff += $k } }
  Log ("registry_after_settle value_diff=[" + ((Reg-DiffDetail $regBefore $regAfter) -join ' ; ') + "]")
  $regFinal = $regAfter; $regLeft = @()
  if ($narStarted) {
    for ($try = 1; $try -le 4; $try++) {
      $regLeft = @(); foreach ($k in ($regBefore.Keys + $regFinal.Keys | Sort-Object -Unique)) { if ((Reg-Sig $regBefore[$k]) -ne (Reg-Sig $regFinal[$k])) { $regLeft += $k } }
      if ($regLeft.Count -eq 0 -and $try -gt 1) { break }   # verified identical after a restore pass
      if ($regLeft.Count -eq 0) { break }
      try { $r = @(Reg-Restore $regBefore); $regRestored += $r; Log "registry_restore_pass=$try actions=$($r.Count) [$($r -join ' ; ')]" } catch { Log "registry_restore_exception: $($_.Exception.Message)" }
      $regFinal = Reg-Settle 3000
    }
  }
  $regLeft = @(); foreach ($k in ($regBefore.Keys + $regFinal.Keys | Sort-Object -Unique)) { if ((Reg-Sig $regBefore[$k]) -ne (Reg-Sig $regFinal[$k])) { $regLeft += $k } }
  # Residual diffs that survive restore+settle and are confined to values Windows itself maintains on ATConfig\narrator (run-state bookkeeping) are OS-managed, not probe state.
  $osManagedNames = @('RunningState', 'LastUpdatedForScripts'); $regOs = @()
  $leftDetail = @(Reg-DiffDetail $regBefore $regFinal)
  if ($regLeft.Count -gt 0) {
    $atKey = 'Software\Microsoft\Windows NT\CurrentVersion\Accessibility\ATConfig\narrator'
    $onlyOs = $true
    foreach ($d in $leftDetail) { $okOs = $false; foreach ($n in $osManagedNames) { if ($d.StartsWith("$atKey\$n(")) { $okOs = $true } }; if (-not $okOs) { $onlyOs = $false } }
    if ($onlyOs -and $leftDetail.Count -gt 0) { $regOs = $regLeft; $regLeft = @() }
  }
  Log ("registry_final_value_diff=[" + ($leftDetail -join ' ; ') + "] os_managed_classified=[" + ($regOs -join ' ; ') + "]")
  Log "narrator_exit_path=$exitPath registry_changed=[$($regDiff -join ' ; ')] restored=[$($regRestored -join ' ; ')] still_different_after_restore=[$($regLeft -join ' ; ')] os_managed_residual=[$($regOs -join ' ; ')]"
  # Caps Lock: Narrator consumes the key while running; if the state still differs, restore it while the probe is foreground
  $capsNow = ([SRN.N]::GetKeyState(0x14) -band 1); $capsFixed = 'n/a'
  if ($capsNow -ne $capsBefore -and $script:Hwnd -ne [IntPtr]::Zero -and -not $script:Proc.HasExited) { $capsFixed = (Send-GatedKey $VK_CAPS 'caps-lock-restore' 200); $capsNow = ([SRN.N]::GetKeyState(0x14) -band 1) }
  $leftover = @(Get-Process | Where-Object { $pidsBefore -notcontains $_.Id -and $_.Name -like 'Narrator*' }).Count
  Add-Check 'narrator-stopped-and-state-restored' $(if ($stillRunning -eq 0 -and $listenAfter -eq $listenBefore -and $capsNow -eq $capsBefore -and $regLeft.Count -eq 0) { 'PASS' } else { 'FAIL' }) "exit_path=$exitPath narrator_processes_left=$stillRunning uia_clients_listening before=$listenBefore after=$listenAfter caps_lock before=$capsBefore after=$capsNow (restore press=$capsFixed) registry_keys_changed_by_narrator=[$($regDiff -join ' ; ')] registry_restored=$($regRestored.Count) still_different_after_restore=[$($regLeft -join ' ; ')] os_managed_residual=[$($regOs -join ' ; ') values=$($leftDetail -join ' ; ')] (before-snapshot in $Out.regbackup.txt)"
  # ---------------------------------------------------------- Narrator speech content (#23): verdict from the loopback transcript
  # #46: the recognizer now runs RecognizeAsync(Multiple), so each phrase carries its own AudioPosition, and the WAV is zero-filled across
  # loopback silence so WAV offset == wall time since capture start. Verdict rule:
  #   'fresh' (a word of the window title, from the HWND default provider): heard in any segment starting at/after the Narrator start step;
  #   'Delete' (the UIA name our provider gives the button): heard in a segment whose start offset lies in
  #     [Delete-step - 0.5 s, min(Delete-step + 3 s, activation step)], where Delete-step is the Caps+Right press that put focus on the Delete button
  #     (the window ends at the Caps+Enter press: later speech belongs to the activation, not to the focus announcement);
  #   'button' (role): recorded in the same window, not required (offline System.Speech does not reliably resolve it).
  $minPeak = 200; $navRan = ($nav -ne $null -and $nav.Count -gt 0)
  $needFresh = $narStarted; $needDelete = $reached
  $speechStatus = 'FAIL'; $speechDetail = ''
  try {
    if ($listenProc -ne $null) {
      if (-not $listenProc.WaitForExit(120000)) { Stop-Process -Id $listenProc.Id -Force -ErrorAction SilentlyContinue; throw 'listener did not finish transcribing within 120 s (killed)' }
    }
    if ($listenProc -eq $null) {
      $speechStatus = 'FAIL-not-automatable'; $speechDetail = "audio loopback could not start: $listenStartErr (no recorded audio, so Narrator speech cannot be checked here)"
    } elseif (-not (Test-Path -LiteralPath $listenJson)) {
      $le = ''; if (Test-Path -LiteralPath $listenErr) { $le = ((Get-Content -LiteralPath $listenErr -ErrorAction SilentlyContinue | Select-Object -First 3) -join ' ') }
      $speechStatus = 'FAIL-not-automatable'; $speechDetail = "listener produced no transcript JSON (exit=$($listenProc.ExitCode)): $le"
    } elseif ($script:CapQpc -eq $null -and ($needFresh -or $needDelete)) {
      $speechStatus = 'FAIL-not-automatable'; $speechDetail = "listener capture-start time unavailable (ready file unreadable or clock mismatch), so transcript offsets cannot be tied to the driver steps; wav=$listenWav json=$listenJson"
    } else {
      $lj = Get-Content -LiteralPath $listenJson -Raw | ConvertFrom-Json
      $items = @($lj.phrases)
      $norm = { param($t) $x = ([string]$t).ToLowerInvariant(); foreach ($d in @(@('zero','0'),@('one','1'),@('two','2'),@('three','3'),@('four','4'),@('five','5'),@('six','6'),@('seven','7'),@('eight','8'),@('nine','9'))) { $x = $x -replace "\b$($d[0])\b", $d[1] }; return ($x -replace '[^a-z0-9 ]', ' ' -replace '\s+', ' ').Trim() }
      $hasWord = { param($it, $w) (" $(& $norm $it.text) " -like "* $(& $norm $w) *") }
      $toMs = { param($t) if ($t -eq $null) { $null } else { [int][math]::Round(([int64]$t - $script:CapQpc) * 1000.0 / $script:CapFreq) } }
      $narMs = & $toMs $tNarStart; $reachMs = & $toMs $tReached; $seenMs = & $toMs $tFocusSeen; $actMs = & $toMs $tAct
      $rel = { param($ms, $anchor) if ($anchor -eq $null) { "$ms ms" } else { '{0:+0.00;-0.00}s' -f (($ms - $anchor) / 1000.0) } }
      $parts = @(); $missing = @()
      $steps = "step offsets in WAV ms: narrator_start=$narMs delete_key=$reachMs delete_focus_seen=$seenMs activate=$actMs capture_start_utc=$($script:CapUtc) padded_gaps=$($lj.paddedGaps) padded_samples=$($lj.paddedSamples)"
      if ($needFresh) {
        $best = $null
        foreach ($it in $items) { if ([int]$it.offsetMs -ge $narMs -and (& $hasWord $it 'fresh')) { if ($best -eq $null -or [double]$it.confidence -gt [double]$best.confidence) { $best = $it } } }
        if ($best -ne $null) { $parts += "'fresh' found at $($best.offsetMs)ms ($(& $rel $best.offsetMs $narMs) after Narrator start) conf=$($best.confidence) text=[$($best.text)]" }
        else { $missing += 'fresh'; $parts += "'fresh' NOT found in any segment starting at/after Narrator start ($narMs ms)" }
      }
      if ($needDelete) {
        $lo = $reachMs - 500; $hi = $reachMs + 3000; if ($actMs -ne $null -and $actMs -lt $hi) { $hi = $actMs }
        $inWin = @($items | Where-Object { [int]$_.offsetMs -ge $lo -and [int]$_.offsetMs -le $hi })
        $best = $null
        foreach ($it in $inWin) { if (& $hasWord $it 'Delete') { if ($best -eq $null -or [double]$it.confidence -gt [double]$best.confidence) { $best = $it } } }
        $btn = @($inWin | Where-Object { & $hasWord $_ 'button' } | Select-Object -First 1)
        $btnTxt = $(if ($btn.Count -gt 0) { "'button' heard in window at $($btn[0].offsetMs)ms ($(& $rel $btn[0].offsetMs $reachMs) vs Delete step) text=[$($btn[0].text)]" } else { "'button' not heard in window (recorded, not required)" })
        $winTxt = "window=[$lo..$hi]ms = Delete step $reachMs ms -0.5s..+3s capped at activation"
        if ($best -ne $null) { $parts += "'Delete' found at $($best.offsetMs)ms ($(& $rel $best.offsetMs $reachMs) vs Delete step, dur=$($best.durationMs)ms) conf=$($best.confidence) grammar=$($best.grammar) text=[$($best.text)]; $winTxt; $btnTxt" }
        else {
          $missing += 'Delete'
          $outside = @($items | Where-Object { & $hasWord $_ 'Delete' } | Select-Object -First 4 | ForEach-Object { "$($_.offsetMs)ms ($(& $rel $_.offsetMs $reachMs))" })
          $parts += "'Delete' NOT found in a segment starting inside $winTxt; matches outside the window (not counted): [$($outside -join ', ')]; $btnTxt"
        }
        $segs = (@($inWin | Select-Object -First 10 | ForEach-Object { "$($_.offsetMs)ms/$($_.durationMs)ms:'$($_.text)'" }) -join ' | ')
        $parts += "segments starting in window: $segs"
        # #46 window recognition: the WAV cut from the Delete key step (Narrator speaks as the focus lands) to 1.5 s after the activation, recognised with the closed grammar. Narrator announces the
        # NAME only at its default verbosity ('button' is never spoken: scan of narrator46-e), so the ROLE is required from UIA by narrator-moved-focus-to-delete-button (ControlType.Button, name Delete).
        $wLo = $reachMs - 100; $wHi = $(if ($actMs -ne $null) { $actMs + 1500 } else { $reachMs + 3000 })
        # A closed grammar only matches a whole utterance, so the window is scanned in 1.2 s hops (400 ms apart) and the words of every hop are collected, each with its start time.
        $scanWords = New-Object System.Collections.Generic.List[string]; $scanErr = ''
        for ($t0 = $wLo; $t0 -le ($wHi - 600); $t0 += 400) {
          $hop = Recognize-WavSlice $listenWav $t0 ([math]::Min($t0 + 1200, $wHi + 200)) @('delete', 'edit', 'button', 'row')
          foreach ($wd in @($hop.Words)) { $scanWords.Add("$wd@$t0") }
          if ($hop.Error -and -not $scanErr) { $scanErr = $hop.Error }
        }
        $slice = [pscustomobject]@{ Words = @($scanWords); Seconds = [math]::Round(($wHi - $wLo) / 1000.0, 2); Error = $scanErr }
        $sliceText = (@($slice.Words) -join ' ')
        $hasDel = (@($slice.Words) | Where-Object { $_ -like 'delete*' -or $_ -match '\bdelete\b' } | Measure-Object).Count -gt 0
        $hasBtn = (@($slice.Words) | Where-Object { $_ -match 'button' } | Measure-Object).Count -gt 0
        $parts += "window recognition [$wLo..$wHi]ms ($($slice.Seconds)s = Delete key step -0.1s .. activation +1.5s): [$sliceText]$(if ($slice.Error) { " error=[$($slice.Error)]" }); 'button' spoken=$hasBtn (not required: role is checked from UIA)"
        if ($hasDel) { $missing = @($missing | Where-Object { $_ -ne 'Delete' }) } else { if ($missing -notcontains 'Delete') { $missing += 'Delete' } }
      }
      $nPhrase = @($items | Where-Object { $_.grammar -eq 'phrase' }).Count; $nDict = @($items | Where-Object { $_.grammar -eq 'dictation' }).Count
      $dictText = (@($items | Where-Object { $_.grammar -eq 'dictation' } | Select-Object -First 12 | ForEach-Object { "$($_.offsetMs)ms:'$($_.text)'($($_.confidence))" }) -join ' | ')
      $stats = "samples=$($lj.samples) recorded_s=$($lj.recordedSeconds) peak=$($lj.peak)/32767 nonzero_fraction=$($lj.nonZeroFraction) total_results=$($items.Count) (phrase=$nPhrase dictation=$nDict) recognition_error=[$($lj.recognitionError)]"
      $paths = "wav=$listenWav json=$listenJson"
      $silent = ([int]$lj.peak -lt $minPeak)
      if (-not ($needFresh -or $needDelete)) {
        $speechStatus = 'NOT-RUN'; $speechDetail = "no Narrator-announced step ran (Delete button reached=$reached, Row 3 focused=$row3Focused, nav commands=$($navRan)); nothing to check. $stats; $paths"
      } elseif ($missing.Count -eq 0) {
        $speechStatus = 'PASS'; $speechDetail = "required provider names recognised at the right time: $($parts -join '; '). $steps. $stats; $paths"
      } else {
        $speechStatus = 'FAIL'
        $why = $(if ($silent) { "SILENT capture (peak $($lj.peak) < $minPeak): no audible output reached the loopback, so this is no-audio, not mis-recognition" } else { "audio was captured (non-silent) but the required phrases were not recognised in their time window" })
        $speechDetail = "$why. $($parts -join '; '). $steps. dictation heard: $dictText. $stats; $paths"
      }
    }
  } catch { $speechStatus = 'FAIL-not-automatable'; $speechDetail = "loopback transcript could not be produced or read: $($_.Exception.Message); $listenStartErr; wav=$listenWav json=$listenJson" }
  if (-not $navRan -and $speechStatus -ne 'FAIL-not-automatable') { $speechStatus = 'NOT-RUN'; $speechDetail = "Narrator navigation did not run (no commands sent). $speechDetail" }
  Add-Check 'narrator-speech-content' $speechStatus $speechDetail
  Close-And-Collect 'F8'
}

# ------------------------------------------------------------ post-hoc: the exe's record (model state)
$std = $script:StdTap.Snapshot()
$evt = Parse-Evt $std
$verdict = ($std | Where-Object { $_ -like 'SELFTEST *' } | Select-Object -First 1)
Log "selftest_verdict=[$verdict]"
if ($uuid6) {
  $axInv = @($evt | Where-Object { $_.kind -eq 'input' -and $_.payload.op -eq 'invoke' -and $_.payload.source -eq 'ax' })
  $rem = @($evt | Where-Object { $_.node_id -eq $uuid6 -and $_.kind -eq 'state' -and $_.payload.op -eq 'remove' })
  if ($reached) {
    $narInvoke = ($axInv.Count -ge 2 -and $axInv[1].payload.node -ne $axInv[0].payload.node)
    Add-Check 'narrator-activation-in-runtime-model-state' $(if ($narInvoke -and $rem.Count -eq 1 -and $gone) { 'PASS' } else { 'FAIL' }) "exe EVT: ax-source invokes=$($axInv.Count) (1 = the driver's 'Insert above' setup, 2nd on a different node = the Delete button Narrator activated) state-remove events for Row 6 uuid $uuid6 = $($rem.Count) (1 expected); self-test verdict=[$verdict]"
  } else {
    Add-Check 'narrator-activation-in-runtime-model-state' 'NOT-RUN' "Narrator did not reach the control; exe saw ax invokes=$($axInv.Count), Row 6 removals=$($rem.Count) (the removal, if any, came from the driver fallback)"
  }
}
Write-Result $Out 'narrator'
