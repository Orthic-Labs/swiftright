Set sh = CreateObject("WScript.Shell")
rc = sh.Run("powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File ""D:\Claude\swiftright\factory\native\windows\first-capture-corrections-v1\corrected-task.ps1"" -Config ""D:\Claude\swiftright\factory\native\windows\first-capture-corrections-v1\disabled-repeatability-r1-02\config.json""", 0, True)
WScript.Quit rc