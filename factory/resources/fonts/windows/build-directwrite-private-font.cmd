@echo off
call "C:\Program Files\Microsoft Visual Studio\18\Community\VC\Auxiliary\Build\vcvars64.bat" >nul
cl /nologo /std:c++17 /EHsc /W4 "D:\Claude\swiftright\factory\resources\fonts\windows\directwrite-private-font.cpp" /Fe:"D:\Claude\swiftright\factory\resources\fonts\windows\directwrite-private-font.exe" /link dwrite.lib
exit /b %errorlevel%
