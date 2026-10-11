$ErrorActionPreference='Stop'
$root='D:\Claude\swiftright\factory\native\windows\stack-lifecycle-next-capture-v1'
$compile='D:\Claude\swiftright\.factory-work\hosts\stack-lifecycle\package\build-lifecycle-r1'
& (Join-Path $root 'prepare-capture.ps1') -CompileReceiptPath (Join-Path $compile 'observation.json') -ExecutablePath (Join-Path $compile 'FactoryProbe.exe') -CompileReceiptHash '99a0332b765518e97a8200ef25612fa5c31671037eccdf5504a1fcec091dcae8' -ExeHash 'abf82f6f133f1d4dd9a48b3075f9af5fe4632db2b9fdc9763114661196bf6c2c' -Count 1 -OutputPath (Join-Path $root 'prepared-dispatch-1.json')
