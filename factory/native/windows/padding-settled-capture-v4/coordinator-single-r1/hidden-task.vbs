Set sh = CreateObject("WScript.Shell")
rc = sh.Run("powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File ""D:\Claude\swiftright\factory\native\windows\padding-settled-capture-v4\interactive-task.ps1"" -Config ""D:\Claude\swiftright\factory\native\windows\padding-settled-capture-v4\coordinator-single-r1\config.json""", 0, True)
WScript.Quit rc