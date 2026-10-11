Set sh = CreateObject("WScript.Shell")
rc = sh.Run("powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File ""D:\Claude\swiftright\factory\native\windows\round1-native-v6\repeat-task.ps1"" -Config ""D:\Claude\swiftright\factory\native\windows\round1-native-v6\repeat-preference-key-r1\replays\run-003\config.json""", 0, True)
WScript.Quit rc