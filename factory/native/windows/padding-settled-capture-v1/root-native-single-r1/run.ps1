$ErrorActionPreference='Stop'
$here='D:\Claude\swiftright\factory\native\windows\padding-settled-capture-v1'
if((Get-FileHash "$here\coordinator.ps1").Hash.ToLowerInvariant() -cne 'f57136d3291914ea53dfa238e80146027fe22ce866564422831c085a9a11d685'){throw 'Reviewed coordinator drift'}
& "$here\coordinator.ps1" -CompileReceiptHash '33eaea411164c7c650fe69521ba01ee81a0855fa31f8ff345d0b08a3202de9ba' -ExeHash '431e68252a68dbbc0218c6bd854eb130b7a0385713f98d07ec4b3c3cf5f2cbc3' -Count 1
