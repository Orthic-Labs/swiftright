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
#   * Narrator SPEECH (what it announces) cannot be read without audio: recorded as FAIL-not-automatable.
# Narrator's prior state is recorded and restored: the run refuses to start if Narrator is already running.
param(
  [string]$Base = 'D:\Claude\sr0s-bridge06b',
  [string]$Out = 'D:\Claude\sr0s-bridge06b\result-native-narrator.txt',
  [Parameter(Mandatory)][string]$ExpectExe,
  [Parameter(Mandatory)][string]$ExpectDll
)
. "$PSScriptRoot\native-common.ps1"
$ready = "$Out.ready"
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

$tap = $null; $narStarted = $false; $reached = $false; $gone = $false; $uuid6 = $null; $moved = $false
try {
  # ---------------------------------------------------------- Narrator first: its startup must not eat the exe script's 40 s step timers
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
    if (-not (Send-GatedChord @($VK_CAPS) $VK_RIGHT "narrator-next-$i" 450)) { break }
    $f = Focused-Info
    $nav.Add("${i}:$($f.Type -replace 'ControlType\.','')|$($f.Name)|$($f.Id)|pid=$($f.Pid)")
    if ($f.Id -ne $startFocus.Id) { $moved = $true }
    if ($f.Id -eq $delId) { $reached = $true; break }
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
    [void](Send-GatedChord @($VK_CAPS) $VK_ENTER 'narrator-activate' 400)
    $gone = Wait-Element { if ((Edit 'Row 6') -eq $null) { 'gone' } else { $null } } 'Row 6 removed by Narrator activation' 5000
    Add-Check 'narrator-activate-changes-model-state' $(if ($gone) { 'PASS' } else { 'FAIL' }) "after Caps Lock + Enter on the focused Delete button: Row 6 present in the UIA tree=$(-not $gone) (model state is confirmed from the exe's EVT lines after exit)"
  } else {
    Add-Check 'narrator-activate-changes-model-state' 'NOT-RUN' 'the Delete button was not reached by Narrator navigation'
    # driver fallback so the exe's script can finish; NOT counted as Narrator evidence
    [void](Invoke-El (Find-Id $delId 3000) 'driver fallback: Delete (row 6)')
  }
  Add-Check 'narrator-speech-content' 'FAIL-not-automatable' 'what Narrator announces (names, roles, caret and text-change speech) is output only as audio; Windows has no non-audio speech log or UIA-visible speech history for Narrator. UIA queries reaching our provider are evidenced indirectly by the focus/activation effects above. A person must listen, or the lane needs an audio loopback recorder plus speech recognition, which is not "verified without audio".'
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
  $listenAfter = [SRN.N]::UiaClientsAreListening()
  $regAfter = Snap-Reg; $regDiff = @(); $regRestored = @()
  foreach ($k in ($regBefore.Keys + $regAfter.Keys | Sort-Object -Unique)) { if ((Reg-Sig $regBefore[$k]) -ne (Reg-Sig $regAfter[$k])) { $regDiff += $k } }
  if ($narStarted -and $regDiff.Count -gt 0) {
    try { $regRestored = @(Reg-Restore $regBefore) } catch { Log "registry_restore_exception: $($_.Exception.Message)" }
  }
  $regFinal = Snap-Reg; $regLeft = @()
  foreach ($k in ($regBefore.Keys + $regFinal.Keys | Sort-Object -Unique)) { if ((Reg-Sig $regBefore[$k]) -ne (Reg-Sig $regFinal[$k])) { $regLeft += $k } }
  Log "narrator_exit_path=$exitPath registry_changed=[$($regDiff -join ' ; ')] restored=[$($regRestored -join ' ; ')] still_different_after_restore=[$($regLeft -join ' ; ')]"
  # Caps Lock: Narrator consumes the key while running; if the state still differs, restore it while the probe is foreground
  $capsNow = ([SRN.N]::GetKeyState(0x14) -band 1); $capsFixed = 'n/a'
  if ($capsNow -ne $capsBefore -and $script:Hwnd -ne [IntPtr]::Zero -and -not $script:Proc.HasExited) { $capsFixed = (Send-GatedKey $VK_CAPS 'caps-lock-restore' 200); $capsNow = ([SRN.N]::GetKeyState(0x14) -band 1) }
  $leftover = @(Get-Process | Where-Object { $pidsBefore -notcontains $_.Id -and $_.Name -like 'Narrator*' }).Count
  Add-Check 'narrator-stopped-and-state-restored' $(if ($stillRunning -eq 0 -and $listenAfter -eq $listenBefore -and $capsNow -eq $capsBefore -and $regLeft.Count -eq 0) { 'PASS' } else { 'FAIL' }) "exit_path=$exitPath narrator_processes_left=$stillRunning uia_clients_listening before=$listenBefore after=$listenAfter caps_lock before=$capsBefore after=$capsNow (restore press=$capsFixed) registry_keys_changed_by_narrator=[$($regDiff -join ' ; ')] registry_restored=$($regRestored.Count) still_different_after_restore=[$($regLeft -join ' ; ')] (before-snapshot in $Out.regbackup.txt)"
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
