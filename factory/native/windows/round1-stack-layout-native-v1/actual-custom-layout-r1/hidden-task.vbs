Set sh = CreateObject("WScript.Shell")
rc = sh.Run("powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File ""D:\Claude\swiftright\factory\native\windows\round1-stack-layout-native-v1\round1-task.ps1"" -Config ""D:\Claude\swiftright\factory\native\windows\round1-stack-layout-native-v1\actual-custom-layout-r1\config.json""", 0, True)
WScript.Quit rc