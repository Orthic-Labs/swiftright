Set sh = CreateObject("WScript.Shell")
rc = sh.Run("powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File ""D:\Claude\swiftright\factory\native\windows\first-capture-readiness-v1\first-task.ps1"" -Config ""D:\Claude\swiftright\factory\native\windows\first-capture-readiness-v1\actual-first-r1\config.json""", 0, True)
WScript.Quit rc