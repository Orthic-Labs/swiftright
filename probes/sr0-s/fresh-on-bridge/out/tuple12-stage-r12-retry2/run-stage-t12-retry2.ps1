# Process-scoped git config: the Dell system gitconfig sets core.autocrlf=true, which checks text out with CRLF and breaks the pinned LF header hash (verify-bridge-header).
$env:GIT_CONFIG_COUNT = '1'; $env:GIT_CONFIG_KEY_0 = 'core.autocrlf'; $env:GIT_CONFIG_VALUE_0 = 'false'
$s = 'D:\Claude\swiftright\.work\sr0-overrides\probes\sr0-s\fresh-on-bridge\scripts'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$s\resume-tuple.ps1" -ScriptOverride 'D:\Claude\swiftright\.work\sr0-overrides' -Restart -RetryRoot 'D:\Claude\swiftright\.work\sr0-r12-retry2' -Commit a9556b77f50315afcae27fc8fc44c0cd274959e2 -RendererDll 'D:\Claude\swiftright\.work\sr0-stage-inputs\swiftright_render.dll' -ExpectRenderer 7578CD5DA8A6831900C66680C4B94F89E64B6B294623709817848B02219AEAC2 *> 'D:\Claude\swiftright\.work\t12-retry2-20261017.txt'
"RESTART_EXIT $LASTEXITCODE" | Out-File -Append 'D:\Claude\swiftright\.work\t12-retry2-20261017.txt'
