Set sh = CreateObject("WScript.Shell")
rc = sh.Run("powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File ""D:\Claude\swiftright\factory\native\windows\round1-seeded-native-v2\repeat-task.ps1"" -Config ""D:\Claude\swiftright\factory\native\windows\round1-seeded-native-v2\single-padding-frame-r1\replays\run-001\config.json""", 0, True)
WScript.Quit rc