$ErrorActionPreference = "Stop"
$repoWin = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$version = "v1.8.0"
$thirdParty = Join-Path $repoWin "third_party"
$destination = Join-Path $thirdParty "skynet"

if (Test-Path -LiteralPath (Join-Path $destination "Makefile")) {
    Write-Output "Skynet 已存在：$destination"
    Write-Output "工程固定基线：$version"
    exit 0
}

# /mnt/c、/mnt/g 等 DrvFs mount 可能拒绝 WSL Git 在 clone 时执行 chmod。
# Windows wrapper 因此使用 Windows Git 拉取源码；编译仍严格在 WSL/Linux 中完成。
if (Test-Path -LiteralPath $destination) {
    $resolvedParent = (Resolve-Path -LiteralPath (Split-Path -Parent $destination)).Path
    $expectedParent = (Resolve-Path -LiteralPath $thirdParty).Path
    if ($resolvedParent -ne $expectedParent) {
        throw "拒绝清理非预期目录：$destination"
    }
    Remove-Item -LiteralPath $destination -Recurse -Force
}

$git = Get-Command git.exe -ErrorAction Stop
& $git.Source clone --recursive --branch $version --depth 1 `
    https://github.com/cloudwu/skynet.git $destination
if ($LASTEXITCODE -ne 0) {
    throw "Skynet $version 拉取失败，Git exit code：$LASTEXITCODE"
}

Write-Output "已拉取官方 Skynet $version"
