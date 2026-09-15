$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = [Console]::OutputEncoding
$repoWin = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
& (Join-Path $PSScriptRoot "bootstrap_luapanda.ps1")
$repoLinux = (wsl.exe -d Ubuntu -- wslpath -a -u $repoWin.Replace('\', '/')).Trim()
wsl bash -lc "cd '$repoLinux' && ./scripts/linux/build_luapanda.sh"
if ($LASTEXITCODE -ne 0) {
    throw "LuaPanda 调试环境构建失败，WSL exit code：$LASTEXITCODE"
}
