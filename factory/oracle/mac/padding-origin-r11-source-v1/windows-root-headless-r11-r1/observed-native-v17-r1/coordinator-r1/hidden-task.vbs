Set sh = CreateObject("WScript.Shell")
rc = sh.Run("powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File ""D:\Claude\swiftright\factory\native\windows\.work\windows-replay-r11\r17\overlay\interactive-task-fresh-r11-v17.ps1"" -Config ""D:\Claude\swiftright\factory\native\windows\.work\windows-replay-r11\r17\coordinator-r1\config.json""", 0, True)
WScript.Quit rc