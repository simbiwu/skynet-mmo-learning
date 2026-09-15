$ErrorActionPreference = "Stop"
$repoWin = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$repoLinux = (wsl.exe -d Ubuntu -- wslpath -a -u $repoWin.Replace('\', '/')).Trim()
wsl bash -lc "cd '$repoLinux' && ./scripts/linux/build.sh"
