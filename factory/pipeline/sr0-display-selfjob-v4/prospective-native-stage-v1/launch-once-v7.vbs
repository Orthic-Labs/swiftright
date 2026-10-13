Option Explicit
Dim shell, worker, manifest, command
If WScript.Arguments.Count <> 2 Then WScript.Quit 2
worker = WScript.Arguments(0)
manifest = WScript.Arguments(1)
Set shell = CreateObject("WScript.Shell")
command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File " & QuoteArg(worker) & " -ManifestPath " & QuoteArg(manifest)
shell.Run command, 0, False
WScript.Quit 0

Function QuoteArg(value)
  QuoteArg = Chr(34) & Replace(value, Chr(34), Chr(92) & Chr(34)) & Chr(34)
End Function
