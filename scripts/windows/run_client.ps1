param(
    [int]$Port = 8888,
    [int]$Player = 10001,
    [switch]$Auto
)
$ErrorActionPreference = "Stop"
$repoWin = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$repoLinux = (wsl.exe -d Ubuntu -- wslpath -a -u $repoWin.Replace('\', '/')).Trim()
$autoArg = if ($Auto) { "--auto" } else { "" }
wsl bash -lc "cd '$repoLinux' && ./scripts/linux/run_client.sh --port=$Port --player=$Player $autoArg"
