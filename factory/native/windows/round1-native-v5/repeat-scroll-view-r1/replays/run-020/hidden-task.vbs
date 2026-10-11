Set sh = CreateObject("WScript.Shell")
rc = sh.Run("powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File ""D:\Claude\swiftright\factory\native\windows\round1-native-v5\repeat-task.ps1"" -Config ""D:\Claude\swiftright\factory\native\windows\round1-native-v5\repeat-scroll-view-r1\replays\run-020\config.json""", 0, True)
WScript.Quit rc