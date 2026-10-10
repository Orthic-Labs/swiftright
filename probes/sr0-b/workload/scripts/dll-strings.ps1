# W5 step 5 evidence: environment/API names embedded in the renderer DLL (read-only scan).
param([string]$Dll = 'D:\Claude\sr0-r08\renderer\swiftright_render.dll')
$b = [IO.File]::ReadAllBytes($Dll); $s = [Text.Encoding]::GetEncoding(28591).GetString($b)
$pat = 'GPUI_[A-Z0-9_]{3,40}|SetMaximumFrameLatency|GetFrameLatencyWaitableObject|FRAME_LATENCY[A-Z_]*|EnumAdapterByGpuPreference|CreateSwapChainForComposition|CreateSwapChainForHwnd|SWR_[A-Z_]{3,30}|DXGI_SWAP_CHAIN_FLAG[A-Z_]*|IDXGIFactory6|SetGPUThreadPriority'
[regex]::Matches($s, $pat) | ForEach-Object { $_.Value } | Group-Object | ForEach-Object { "$($_.Name) x$($_.Count)" }
