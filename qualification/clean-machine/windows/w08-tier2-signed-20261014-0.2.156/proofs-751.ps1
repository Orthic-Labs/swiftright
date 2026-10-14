$ErrorActionPreference='Continue'
function Log([string]$m){ 'LOG: '+$m }
function Test-ForeignEvent([string]$family, [string]$recordId) {
    # '' = proceed (not an event run, or the event names this package, or it could not be read); else why the event is not ours
    if (-not $recordId -or $recordId -notmatch '^\d{1,20}$') { return '' }
    try {
        $e = Get-WinEvent -LogName 'Microsoft-Windows-AppXDeploymentServer/Operational' -FilterXPath ('*[System[EventID=751 and EventRecordID=' + $recordId + ']]') -MaxEvents 1 -ErrorAction Stop
        $text = [string]$e.Message + ' ' + [string]$e.ToXml()
        $name = $family.Substring(0, $family.LastIndexOf('_')); $pub = $family.Substring($family.LastIndexOf('_') + 1)
        if (($text.IndexOf($name + '_', [StringComparison]::OrdinalIgnoreCase) -ge 0) -and ($text.IndexOf($pub, [StringComparison]::OrdinalIgnoreCase) -ge 0)) { return '' }
        return ('event 751 record ' + $recordId + ' does not name ' + $family)
    } catch { Log ('event ' + $recordId + ' unreadable, proceeding: ' + $_.Exception.Message); return '' }
}

$o=[ordered]@{}
$ev = @(Get-WinEvent -LogName 'Microsoft-Windows-AppXDeploymentServer/Operational' -FilterXPath '*[System[EventID=751]]' -MaxEvents 20 -ErrorAction SilentlyContinue)
$o.events751 = @($ev | ForEach-Object { [ordered]@{ recordId = $_.RecordId; time = $_.TimeCreated.ToString('o'); message = $_.Message } })
$ours = 'OrthicLabs.SliceApp_j3cejpx244dcr'
$other = 'OrthicLabs.OtherApp_abcdefghijklm'
if ($ev.Count -gt 0) {
  $id = [string]$ev[0].RecordId
  $o.recordUsed = $id
  $o.accept_ours = '[' + (Test-ForeignEvent $ours $id) + ']'
  $o.ignore_other_pkg = '[' + (Test-ForeignEvent $other $id) + ']'
}
$o.foreign_nonnumeric_id_proceeds = '[' + (Test-ForeignEvent $ours 'abc') + ']'
$o.empty_id_proceeds = '[' + (Test-ForeignEvent $ours '') + ']'
$o.unreadable_id_failopen = '[' + (Test-ForeignEvent $ours '99999999') + ']'
# 4688 task-action command lines
$cmd = @(Get-WinEvent -FilterHashtable @{LogName='Security';Id=4688} -MaxEvents 4000 -ErrorAction SilentlyContinue | Where-Object { $_.Message -match 'repair-guard.ps1' } | ForEach-Object {
  $cl = ([regex]::Match($_.Message,'Process Command Line:\s*(.*)')).Groups[1].Value.Trim(); [ordered]@{ time = $_.TimeCreated.ToString('o'); cmd = $cl } })
$o.guardProcessCommandLines = $cmd
'JSON-BEGIN'; ($o | ConvertTo-Json -Depth 6); 'JSON-END'
