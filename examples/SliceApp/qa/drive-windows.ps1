# SliceApp QA driver (Windows). Called from rightkit-qa scenarios (qa\scenarios\windows\*.scenario.toml) as
#   powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File qa\drive-windows.ps1 <selfcheck|build|launch|journey>
# with the working directory examples\SliceApp (right-release qa runs the runner there).
#
# Contract: stdout carries exactly ONE JSON object (the step result the scenario asserts on); every log line goes to stderr.
# Exit code 0 only when result.ok is true. The result always carries `error` (null on success) and `diagnostics`.
#
# What it drives: the STAGED payload .build\msix-stage\SliceApp.exe (the flat directory right-release packs into the MSIX),
# started with PATH reduced to System32 and Windows (no Swift runtime, no dev tools: the exe must load its DLLs and the renderer
# from its own directory) and an isolated %LOCALAPPDATA% (so the real profile is never read or written).
#
# Input is window-targeted only: UI Automation InvokePattern / ValuePattern on the app's own elements and WM_CLOSE through
# Process.CloseMainWindow. Never SendInput, never keybd_event/mouse_event, never SetForegroundWindow: a person may be using
# the desktop (workspace rule from the 2026-10-09 SendInput leak). Only processes this script started are ever killed.
#
# Cases: selfcheck (no build, no launch), build (prepackage-windows.ps1 + .build\qa-build.json), launch, journey.
# Not implemented: RIGHT_RELEASE_QA_STAGE=installed (the driver refuses it; there is no false installed receipt).
param([Parameter(Mandatory = $true, Position = 0)][ValidateSet('selfcheck', 'build', 'launch', 'journey')][string]$Case)
$ErrorActionPreference = 'Stop'

$script:AppDir = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$script:StageDir = Join-Path $script:AppDir '.build\msix-stage'
$script:Exe = Join-Path $script:StageDir 'SliceApp.exe'
$script:BuildRecord = Join-Path $script:AppDir '.build\qa-build.json'
$script:Started = New-Object System.Collections.ArrayList
$script:Result = [ordered]@{ ok = $false; case = $Case; platform = 'windows'; stage = $null; commit = $null; diagnostics = @(); error = $null }
$script:AllDiagnostics = New-Object System.Collections.ArrayList

function Log([string]$m) { [Console]::Error.WriteLine('[sliceapp-qa] ' + $m) }
function Get-Sha([string]$p) { return (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash }
function Write-Utf8([string]$p, [string]$t) { [IO.File]::WriteAllText($p, $t, (New-Object System.Text.UTF8Encoding($false))) }

function Get-HeadCommit {
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { $c = (& git -C $script:AppDir rev-parse HEAD 2>$null); if ($LASTEXITCODE -ne 0) { $c = $null } } finally { $ErrorActionPreference = $prev }
    return [string]$c
}

function Get-DataRoot {
    $d = [string]$env:SLICEAPP_QA_DATA
    # The runner canonicalizes paths to the \\?\ verbatim form on Windows; PowerShell's Join-Path/Test-Path/New-Item reject it ("drive is null").
    if ($d.StartsWith('\\?\') -and $d.Length -gt 6 -and $d[5] -eq ':') { $d = $d.Substring(4) }
    if (-not $d) {
        $d = Join-Path ([IO.Path]::GetTempPath()) ('sliceapp-qa-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        $script:Result.dataRootAutoCreated = $true
        Log ('SLICEAPP_QA_DATA not set; using ' + $d)
    }
    New-Item -ItemType Directory -Force -Path $d | Out-Null
    return $d
}

# ---------------------------------------------------------------------------------------------------- UI Automation + window

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -Namespace SliceQa -Name Win -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
[DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
[StructLayout(LayoutKind.Sequential)] public struct RECT { public int left, top, right, bottom; }
'@

$UIA = [System.Windows.Automation.AutomationElement]
$CT = [System.Windows.Automation.ControlType]

function Start-App([string]$Exe, [string]$LocalAppData, [string]$Label) {
    New-Item -ItemType Directory -Force -Path $LocalAppData | Out-Null
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Exe
    $psi.WorkingDirectory = Split-Path -Parent $Exe
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.EnvironmentVariables['PATH'] = (Join-Path $env:SystemRoot 'System32') + ';' + $env:SystemRoot
    [void]$psi.EnvironmentVariables.Remove('SWIFTRIGHT_RENDER_DLL')
    $psi.EnvironmentVariables['LOCALAPPDATA'] = $LocalAppData
    $p = [System.Diagnostics.Process]::Start($psi)
    [void]$script:Started.Add($p)
    Log ("started $Label pid=" + $p.Id)
    return @{ proc = $p; out = $p.StandardOutput.ReadToEndAsync(); err = $p.StandardError.ReadToEndAsync(); label = $Label }
}

function Wait-Window($App, [int]$TimeoutSec) {
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        if ($App.proc.HasExited) { return [IntPtr]::Zero }
        $App.proc.Refresh()
        if ($App.proc.MainWindowHandle -ne [IntPtr]::Zero) { return $App.proc.MainWindowHandle }
        Start-Sleep -Milliseconds 250
    }
    return [IntPtr]::Zero
}

function Describe-Early($App) {
    $p = $App.proc
    if (-not $p.HasExited) { return 'process is alive but has no main window' }
    $o = ''; $e = ''
    try { if ($App.out.Wait(3000)) { $o = [string]$App.out.Result } } catch { }
    try { if ($App.err.Wait(3000)) { $e = [string]$App.err.Result } } catch { }
    return ('process exited with code ' + $p.ExitCode + '; stdout: ' + $o.Trim() + '; stderr: ' + $e.Trim())
}

function Get-WindowFacts($App, [IntPtr]$Hwnd) {
    $r = New-Object SliceQa.Win+RECT
    [void][SliceQa.Win]::GetWindowRect($Hwnd, [ref]$r)
    $App.proc.Refresh()
    $root = $UIA::FromHandle($Hwnd)
    $f = [ordered]@{
        hwnd      = $Hwnd.ToInt64()
        title     = [string]$App.proc.MainWindowTitle
        visible   = [bool][SliceQa.Win]::IsWindowVisible($Hwnd)
        minimized = [bool][SliceQa.Win]::IsIconic($Hwnd)
        width     = [int]($r.right - $r.left)
        height    = [int]($r.bottom - $r.top)
        offscreen = [bool]$root.Current.IsOffscreen
    }
    $f.shown = ($f.visible -and -not $f.minimized -and -not $f.offscreen -and $f.width -ge 200 -and $f.height -ge 150)
    return $f
}

# One pass over the window's UIA tree: row text fields (AutomationId row/<uuid>/field), buttons by AutomationId, the "N rows" label.
function Get-Snapshot($Root) {
    $all = $Root.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
    $fields = New-Object System.Collections.ArrayList
    $buttons = @{}
    $label = $null
    foreach ($el in $all) {
        $cur = $el.Current
        $id = [string]$cur.AutomationId
        $ct = $cur.ControlType
        if ($ct.Id -eq $CT::Edit.Id -and $id -match '^row/[0-9A-Fa-f-]{36}/field$') {
            $val = ''
            $vp = $null
            if ($el.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern, [ref]$vp)) { $val = [string]$vp.Current.Value }
            [void]$fields.Add([pscustomobject]@{ id = $id; value = $val; element = $el })
        } elseif ($ct.Id -eq $CT::Button.Id -and $id) {
            $buttons[$id] = $el
        } elseif ($ct.Id -eq $CT::Text.Id -and ([string]$cur.Name) -match '^\d+ rows$') {
            $label = [string]$cur.Name
        }
    }
    return [pscustomobject]@{ fields = @($fields); buttons = $buttons; label = $label }
}

# For failure messages: what the window's UIA tree actually holds (first 60 nodes: type | AutomationId | Name).
function Dump-Tree($Root) {
    try {
        $all = $Root.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
        $lines = New-Object System.Collections.ArrayList
        foreach ($el in $all) {
            $c = $el.Current
            [void]$lines.Add(([string]$c.ControlType.ProgrammaticName + '|' + [string]$c.AutomationId + '|' + [string]$c.Name))
            if ($lines.Count -ge 60) { break }
        }
        return ('UIA tree (' + $all.Count + ' nodes): ' + ($lines -join ' ; '))
    } catch { return 'UIA tree dump failed: ' + $_.Exception.Message }
}

# Polls until $Test(snapshot) is true; UIA calls on a tree that is mid-update can throw, so those are retried.
function Wait-Snapshot($Root, [scriptblock]$Test, [int]$TimeoutSec) {
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    $last = $null
    while ((Get-Date) -lt $deadline) {
        try {
            $s = Get-Snapshot $Root
            $last = $s
            if (& $Test $s) { return $s }
        } catch { Log ('uia snapshot retry: ' + $_.Exception.Message) }
        Start-Sleep -Milliseconds 300
    }
    return $null
}

function Invoke-Button($Root, [string]$AutomationId) {
    for ($i = 0; $i -lt 4; $i++) {
        try {
            $s = Get-Snapshot $Root
            if (-not $s.buttons.ContainsKey($AutomationId)) { throw "button $AutomationId not found in the UIA tree" }
            $s.buttons[$AutomationId].GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
            return
        } catch { Log ("invoke $AutomationId retry: " + $_.Exception.Message); Start-Sleep -Milliseconds 400 }
    }
    throw ("could not invoke $AutomationId through UIA InvokePattern. " + (Dump-Tree $Root))
}

function Set-FieldValue($Root, [string]$FieldId, [string]$Text) {
    for ($i = 0; $i -lt 4; $i++) {
        try {
            $s = Get-Snapshot $Root
            $f = @($s.fields | Where-Object { $_.id -eq $FieldId })
            if ($f.Count -ne 1) { throw "field $FieldId not found in the UIA tree" }
            $f[0].element.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue($Text)
            return
        } catch { Log ("set value retry: " + $_.Exception.Message); Start-Sleep -Milliseconds 400 }
    }
    throw ("could not set the value of $FieldId through UIA ValuePattern. " + (Dump-Tree $Root))
}

# ---------------------------------------------------------------------------------------------------- rows.json

function Read-RowsJson([string]$LocalAppData) {
    $f = Join-Path $LocalAppData 'SliceApp\rows.json'
    $o = [ordered]@{ exists = $false; schema = $null; rowCount = 0; texts = @(); sha256 = $null }
    if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { return $o }
    for ($i = 0; $i -lt 5; $i++) {
        try {
            $bytes = [IO.File]::ReadAllBytes($f)
            $doc = [System.Text.Encoding]::UTF8.GetString($bytes) | ConvertFrom-Json
            $sha = New-Object System.Security.Cryptography.SHA256Managed
            $o.sha256 = ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '')
            $o.exists = $true
            $o.schema = [int]$doc.schema
            $rows = @($doc.rows)
            $o.rowCount = $rows.Count
            $o.texts = @($rows | ForEach-Object { [string]$_.text })
            return $o
        } catch { Start-Sleep -Milliseconds 200 }
    }
    throw "rows.json exists but could not be read or parsed: $f"
}

function Wait-RowsJson([string]$LocalAppData, [scriptblock]$Test, [int]$TimeoutSec) {
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    $last = $null
    while ((Get-Date) -lt $deadline) {
        $last = Read-RowsJson $LocalAppData
        if (& $Test $last) { return $last }
        Start-Sleep -Milliseconds 300
    }
    return $null
}

# ---------------------------------------------------------------------------------------------------- one app session

# Start, wait for a visible window, wait for the ready signal. Returns the session (kept alive for further UI actions).
function Start-Session([string]$Label, [string]$LocalAppData, [int]$ExpectRows) {
    $app = Start-App -Exe $script:Exe -LocalAppData $LocalAppData -Label $Label
    $hwnd = Wait-Window $app 90
    if ($hwnd -eq [IntPtr]::Zero) { throw ("${Label}: no window within 90 s; " + (Describe-Early $app)) }
    $facts = Get-WindowFacts $app $hwnd
    $root = $UIA::FromHandle($hwnd)
    $snap = Wait-Snapshot $root { param($s) $s.buttons.ContainsKey('toolbar/insert-above') -and $s.fields.Count -ge $ExpectRows } 45
    if (-not $snap) { throw ("$Label ready signal not seen within 45 s: the toolbar/insert-above button and $ExpectRows row fields are not in the UIA tree. " + (Dump-Tree $root)) }
    return @{ app = $app; hwnd = $hwnd; root = $root; facts = $facts; snap = $snap; label = $Label }
}

# WM_CLOSE through CloseMainWindow, then require a normal exit (code 0 = window closed and shutdown completed; see WindowsBootstrap.swift).
function Stop-Session($Session) {
    $app = $Session.app
    $p = $app.proc
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $closeSent = $false
    try { $closeSent = [bool]$p.CloseMainWindow() } catch { Log ('CloseMainWindow: ' + $_.Exception.Message) }
    $exited = $p.WaitForExit(20000)
    $killed = $false
    if (-not $exited) { $killed = $true; try { $p.Kill() } catch { }; [void]$p.WaitForExit(5000) }
    $p.WaitForExit()
    $o = ''; $e = ''
    try { $o = [string]$app.out.Result } catch { }
    try { $e = [string]$app.err.Result } catch { }
    $diag = @()
    foreach ($line in (($o + "`n" + $e) -split "\r?\n")) { if ($line -match '^(SWR_|SLICE_)[A-Z_]*ERROR') { $diag += $line.Trim() } }
    foreach ($d in $diag) { [void]$script:AllDiagnostics.Add($Session.label + ': ' + $d) }
    $code = $p.ExitCode
    return [ordered]@{ closeSent = $closeSent; exited = $exited; killed = $killed; exitCode = $code; ms = [int]$sw.ElapsedMilliseconds; clean = ($exited -and -not $killed -and $code -eq 0) }
}

function Summarize-Session($Session, $Rows) {
    return [ordered]@{
        pid           = $Session.app.proc.Id
        windowShown   = $Session.facts.shown
        windowTitle   = $Session.facts.title
        window        = $Session.facts
        ready         = $true
        rowCount      = $Session.snap.fields.Count
        rowsLabel     = $Session.snap.label
        buttons       = @($Session.snap.buttons.Keys | Sort-Object | Where-Object { $_ -like 'toolbar/*' })
        rowsJson      = $Rows
    }
}

# ---------------------------------------------------------------------------------------------------- build provenance

function Assert-Build {
    if (-not (Test-Path -LiteralPath $script:BuildRecord)) { throw 'no .build\qa-build.json: the build case (app.build scenario) must run first' }
    $rec = Get-Content -Raw -LiteralPath $script:BuildRecord | ConvertFrom-Json
    if ([string]$rec.commit -ne $script:Result.commit) { throw ('staged build is for commit ' + $rec.commit + ', checkout is ' + $script:Result.commit) }
    if (-not (Test-Path -LiteralPath $script:Exe)) { throw "staged exe missing: $script:Exe" }
    if ((Get-Sha $script:Exe) -ne [string]$rec.exeSha256) { throw 'staged SliceApp.exe changed since the build case recorded it' }
    $script:Result.build = [ordered]@{ commit = [string]$rec.commit; exeSha256 = [string]$rec.exeSha256; rendererSha256 = [string]$rec.rendererSha256 }
}

# ---------------------------------------------------------------------------------------------------- cases

function Invoke-SelfCheck {
    $dataRoot = Get-DataRoot
    $probe = Join-Path $dataRoot 'selfcheck-write-probe.txt'
    Write-Utf8 $probe 'ok'
    $script:Result.psVersion = $PSVersionTable.PSVersion.ToString()
    $script:Result.uiaLoaded = ($null -ne ([System.Windows.Automation.AutomationElement]::RootElement))
    $script:Result.dataRootWritable = (Test-Path -LiteralPath $probe)
    $script:Result.dataRoot = $dataRoot
    $script:Result.stagedExeExists = (Test-Path -LiteralPath $script:Exe)
    $script:Result.buildRecordExists = (Test-Path -LiteralPath $script:BuildRecord)
    $script:Result.appDir = $script:AppDir
    $script:Result.qaCommitEnv = [string]$env:RIGHT_RELEASE_QA_COMMIT
    $script:Result.tools = [ordered]@{
        git  = [bool](Get-Command git -ErrorAction SilentlyContinue)
        node = [bool](Get-Command node -ErrorAction SilentlyContinue)
        pnpm = [bool](Get-Command pnpm -ErrorAction SilentlyContinue)
    }
    $script:Result.ok = ($script:Result.uiaLoaded -and $script:Result.dataRootWritable)
}

function Invoke-Build {
    $prep = Join-Path $script:AppDir 'scripts\prepackage-windows.ps1'
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try {
        & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $prep 2>&1 | ForEach-Object { [Console]::Error.WriteLine([string]$_) }
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $prev }
    if ($code -ne 0) { throw "prepackage-windows.ps1 failed (exit $code); the step log has its output" }
    $renderer = Join-Path $script:StageDir 'swiftright_render.dll'
    if (-not (Test-Path -LiteralPath $script:Exe)) { throw "staged exe missing after prepackage: $script:Exe" }
    if (-not (Test-Path -LiteralPath $renderer)) { throw "staged renderer missing after prepackage: $renderer" }
    $rec = [ordered]@{ commit = $script:Result.commit; exeSha256 = (Get-Sha $script:Exe); rendererSha256 = (Get-Sha $renderer); builtAt = (Get-Date).ToUniversalTime().ToString('o') }
    Write-Utf8 $script:BuildRecord (ConvertTo-Json -InputObject $rec -Compress)
    $script:Result.build = $rec
    $script:Result.stageFileCount = @(Get-ChildItem -LiteralPath $script:StageDir -File).Count
    $script:Result.buildMs = [int]$sw.ElapsedMilliseconds
    $script:Result.ok = $true
}

function Invoke-Launch {
    Assert-Build
    $la = Join-Path (Get-DataRoot) 'launch\localappdata'
    if (Test-Path -LiteralPath $la) { throw "profile directory is not fresh: $la" }
    $s = Start-Session -Label 'launch' -LocalAppData $la -ExpectRows 5
    $rows = Wait-RowsJson $la { param($r) $r.exists -and $r.rowCount -ge 5 } 15
    if (-not $rows) { $rows = Read-RowsJson $la }
    $sum = Summarize-Session $s $rows
    $quit = Stop-Session $s
    foreach ($k in $sum.Keys) { $script:Result[$k] = $sum[$k] }
    $script:Result.quit = $quit
    $script:Result.localAppData = $la
    $seed = @('Row 1', 'Row 2', 'Row 3', 'Row 4', 'Row 5')
    $script:Result.seedRowsPersisted = (($rows.texts -join '|') -eq ($seed -join '|'))
    $script:Result.ok = ($sum.windowShown -and $sum.windowTitle -eq 'SliceApp' -and $sum.rowCount -eq 5 -and $rows.schema -eq 1 -and $rows.rowCount -eq 5 -and $script:Result.seedRowsPersisted -and $quit.clean)
}

function Invoke-Journey {
    Assert-Build
    $la = Join-Path (Get-DataRoot) 'journey\localappdata'
    if (Test-Path -LiteralPath $la) { throw "profile directory is not fresh: $la" }
    $commit8 = $script:Result.commit.Substring(0, [Math]::Min(8, $script:Result.commit.Length))
    $marker = 'qa-journey-' + $commit8 + '-' + (Get-Date -Format 'HHmmss')
    $script:Result.marker = $marker
    $script:Result.uiDriven = $true

    # --- first run: fresh profile, edit through UIA
    $s1 = Start-Session -Label 'first' -LocalAppData $la -ExpectRows 5
    $seedRows = Wait-RowsJson $la { param($r) $r.exists -and $r.rowCount -ge 5 } 15
    if (-not $seedRows) { throw 'first run: rows.json with the seed rows did not appear' }
    $beforeIds = @($s1.snap.fields | ForEach-Object { $_.id })
    Invoke-Button $s1.root 'toolbar/insert-above'
    $afterInsert = Wait-Snapshot $s1.root { param($s) $s.fields.Count -eq ($beforeIds.Count + 1) } 15
    if (-not $afterInsert) { throw ('first run: the row count did not become 6 after Insert above. ' + (Dump-Tree $s1.root)) }
    $new = @($afterInsert.fields | Where-Object { $beforeIds -notcontains $_.id })
    if ($new.Count -ne 1) { throw ('first run: expected exactly one new row field, found ' + $new.Count + '. ' + (Dump-Tree $s1.root)) }
    Set-FieldValue $s1.root $new[0].id $marker
    $shown = Wait-Snapshot $s1.root { param($s) @($s.fields | Where-Object { $_.value -eq $marker }).Count -eq 1 } 15
    $withMarker = Wait-RowsJson $la { param($r) $r.rowCount -eq 6 -and ($r.texts -contains $marker) } 15
    $edit = [ordered]@{
        insertedRowId      = $new[0].id
        rowCountAfterInsert = $afterInsert.fields.Count
        markerShownInUi    = [bool]$shown
        markerInRowsJson   = [bool]$withMarker
    }
    $firstSum = Summarize-Session $s1 $seedRows
    $quit1 = Stop-Session $s1
    $firstSum.quit = $quit1
    $afterFirst = Read-RowsJson $la

    # --- second run: same profile, the edit must come back
    $s2 = Start-Session -Label 'second' -LocalAppData $la -ExpectRows 6
    $markerShown2 = @($s2.snap.fields | Where-Object { $_.value -eq $marker }).Count -eq 1
    $secondSum = Summarize-Session $s2 $afterFirst
    $secondSum.markerShown = [bool]$markerShown2
    $quit2 = Stop-Session $s2
    $secondSum.quit = $quit2
    $afterSecond = Read-RowsJson $la

    $script:Result.firstRun = $firstSum
    $script:Result.edit = $edit
    $script:Result.secondRun = $secondSum
    $script:Result.rowsJsonAfterFirstRun = $afterFirst
    $script:Result.rowsJsonAfterSecondRun = $afterSecond
    $script:Result.rowsJsonUnchangedByReload = ($afterFirst.sha256 -and $afterFirst.sha256 -eq $afterSecond.sha256)
    $script:Result.localAppData = $la
    $script:Result.restartKeptData = ($edit.markerInRowsJson -and $markerShown2 -and ($afterSecond.texts -contains $marker) -and $afterSecond.rowCount -eq 6)
    $script:Result.ok = ($firstSum.windowShown -and $firstSum.rowCount -eq 5 -and $edit.rowCountAfterInsert -eq 6 -and $edit.markerShownInUi -and $edit.markerInRowsJson `
        -and $quit1.clean -and $secondSum.windowShown -and $secondSum.rowCount -eq 6 -and $markerShown2 -and $quit2.clean `
        -and $script:Result.rowsJsonUnchangedByReload -and $script:Result.restartKeptData)
}

# ---------------------------------------------------------------------------------------------------- main

try {
    $stage = [string]$env:RIGHT_RELEASE_QA_STAGE
    $script:Result.stage = $(if ($stage) { $stage } else { 'manual' })
    $script:Result.commit = Get-HeadCommit
    if ($stage -eq 'installed') {
        throw 'installed-stage QA is not implemented for SliceApp: this driver tests the staged source build only, so no installed receipt can be produced'
    }
    $want = [string]$env:RIGHT_RELEASE_QA_COMMIT
    if ($want -and $want -ne $script:Result.commit) { throw "RIGHT_RELEASE_QA_COMMIT $want differs from the checkout HEAD $($script:Result.commit)" }
    switch ($Case) {
        'selfcheck' { Invoke-SelfCheck }
        'build'     { Invoke-Build }
        'launch'    { Invoke-Launch }
        'journey'   { Invoke-Journey }
    }
} catch {
    $script:Result.ok = $false
    $script:Result.error = [string]$_.Exception.Message
    Log ('FAILED: ' + $_.Exception.Message)
    Log ([string]$_.ScriptStackTrace)
} finally {
    foreach ($p in $script:Started) { try { if (-not $p.HasExited) { $p.Kill(); Log ('killed leftover pid ' + $p.Id) } } catch { } }
}
$script:Result.diagnostics = @($script:AllDiagnostics)
if ($script:Result.diagnostics.Count -gt 0) { $script:Result.ok = $false; if (-not $script:Result.error) { $script:Result.error = 'the app printed SWR_/SLICE_ error lines' } }
[Console]::Out.WriteLine((ConvertTo-Json -InputObject $script:Result -Depth 8 -Compress))
exit $(if ($script:Result.ok -eq $true) { 0 } else { 1 })
