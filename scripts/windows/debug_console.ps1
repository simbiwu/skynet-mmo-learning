param(
    [string]$HostName = "127.0.0.1",
    [int]$Port = 8000
)
$ErrorActionPreference = "Stop"
$repoWin = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$repoLinux = (wsl.exe -d Ubuntu -- wslpath -a -u $repoWin.Replace('\', '/')).Trim()
wsl bash -lc "cd '$repoLinux' && ./scripts/linux/debug_console.sh '$HostName' '$Port'"
