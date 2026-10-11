$ErrorActionPreference='Stop'
$root='D:\Claude\swiftright\.factory-work\hosts\stack-lifecycle'
if(Test-Path $root){throw 'Fresh lifecycle rolling root required'}
@{fresh=$true;root=$root;nativeActions=0}|ConvertTo-Json
