$ErrorActionPreference = "Stop"
$repoWin = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path

# 回归保护：PowerShell 5.1 直接把 G:\... 传给 wslpath 时可能吞掉反斜杠。
# 先使用 Windows 和 wslpath 都接受的 G:/... 形式，再验证结果确实是绝对 Linux 路径。
$portablePath = $repoWin.Replace('\', '/')
$repoLinux = (wsl.exe -d Ubuntu -- wslpath -a -u $portablePath).Trim()
if ($LASTEXITCODE -ne 0 -or -not $repoLinux.StartsWith('/')) {
    throw "Windows 路径转换 WSL 路径失败：$repoWin -> $repoLinux"
}

Write-Output "WINDOWS_WSLPATH_OK $repoLinux"
