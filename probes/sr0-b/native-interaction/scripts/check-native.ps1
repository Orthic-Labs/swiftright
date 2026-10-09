# Static checks for the R9 scripts. Safe in a NON-interactive SSH session: it parses and compiles only, and never
# calls an input, IME or window function. Run through `win` as a file:
#   win "powershell -NoProfile -ExecutionPolicy Bypass -File <dir>\check-native.ps1"
$ErrorActionPreference = 'Stop'
$bad = 0
foreach ($f in @('native-common.ps1', 'drive-ime.ps1', 'drive-narrator.ps1', 'schedule-native.ps1', 'check-native.ps1')) {
  $tokens = $null; $errs = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot $f), [ref]$tokens, [ref]$errs)
  if ($errs.Count -gt 0) { $bad++; foreach ($e in $errs) { "PARSE_ERROR $f line $($e.Extent.StartLineNumber): $($e.Message)" } } else { "PARSE_OK $f" }
  $raw = [IO.File]::ReadAllBytes((Join-Path $PSScriptRoot $f)); $nonAscii = @($raw | Where-Object { $_ -gt 127 }).Count
  if ($nonAscii -gt 0) { $bad++; "NON_ASCII $f bytes=$nonAscii (PowerShell 5.1 would misread them)" }
}
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
$refs = @([System.Windows.Automation.AutomationElement].Assembly.Location, [System.Windows.Automation.ControlType].Assembly.Location)
try {
  Add-Type -TypeDefinition ([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'NativeHelpers.cs'))) -ReferencedAssemblies $refs
  "COMPILE_OK NativeHelpers.cs (types: $(([SRN.N], [SRN.LineTap], [SRN.UiaTap]) | ForEach-Object { $_.Name })) input_struct_size=$([SRN.N]::InputSize())"
} catch { $bad++; "COMPILE_ERROR NativeHelpers.cs: $($_.Exception.Message)" }
if ($bad -eq 0) { 'CHECK_OK' } else { "CHECK_FAILED problems=$bad"; exit 1 }
