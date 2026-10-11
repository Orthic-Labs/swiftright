Set sh = CreateObject("WScript.Shell")
rc = sh.Run("powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File ""D:\Claude\swiftright\factory\native\windows\round1-stack-layout-repair-capture-v1\repaired-task.ps1"" -Config ""D:\Claude\swiftright\factory\native\windows\round1-stack-layout-repair-capture-v1\actual-stack-overlay-r1\config.json""", 0, True)
WScript.Quit rc