$ErrorActionPreference='Stop'
$root='D:\Claude\swiftright\.factory-work\hosts\padding-window-diagnosis'
if(Test-Path $root){throw 'Fresh rolling diagnosis namespace required'}
New-Item -ItemType Directory -Path $root|Out-Null
@{status='FRESH_DIAGNOSIS_ROOT_CREATED';nativeActions=0;compilerActions=0;root=$root}|ConvertTo-Json
