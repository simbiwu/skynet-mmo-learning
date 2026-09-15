$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = [Console]::OutputEncoding
$repoWin = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$thirdParty = Join-Path $repoWin "third_party"
$luaPanda = Join-Path $thirdParty "luapanda"
$luaSocket = Join-Path $thirdParty "luasocket"
$luaPandaCommit = "e3ac3d3314f24cf939c36cac5b7dc1f2ed6ee129"
$luaSocketTag = "v3.1.0"
$git = Get-Command git.exe -ErrorAction Stop

New-Item -ItemType Directory -Force -Path $thirdParty | Out-Null

function Remove-ExactThirdPartyDirectory([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $resolvedParent = (Resolve-Path -LiteralPath (Split-Path -Parent $Path)).Path
    $expectedParent = (Resolve-Path -LiteralPath $thirdParty).Path
    if ($resolvedParent -ne $expectedParent) {
        throw "拒绝清理非预期目录：$Path"
    }
    Remove-Item -LiteralPath $Path -Recurse -Force
}

if (-not (Test-Path -LiteralPath (Join-Path $luaPanda "Debugger\LuaPanda.lua"))) {
    Remove-ExactThirdPartyDirectory $luaPanda
    & $git.Source init $luaPanda
    if ($LASTEXITCODE -ne 0) { throw "LuaPanda git init 失败" }
    & $git.Source -C $luaPanda remote add origin https://github.com/Tencent/LuaPanda.git
    & $git.Source -C $luaPanda fetch --depth 1 origin $luaPandaCommit
    if ($LASTEXITCODE -ne 0) { throw "LuaPanda 固定提交拉取失败" }
    & $git.Source -C $luaPanda checkout --detach FETCH_HEAD
    if ($LASTEXITCODE -ne 0) { throw "LuaPanda 固定提交 checkout 失败" }
}

if (-not (Test-Path -LiteralPath (Join-Path $luaSocket "src\makefile"))) {
    Remove-ExactThirdPartyDirectory $luaSocket
    & $git.Source clone --branch $luaSocketTag --depth 1 `
        https://github.com/lunarmodules/luasocket.git $luaSocket
    if ($LASTEXITCODE -ne 0) { throw "LuaSocket $luaSocketTag 拉取失败" }
}

$actualLuaPandaCommit = (& $git.Source -C $luaPanda rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $actualLuaPandaCommit -ne $luaPandaCommit) {
    throw "LuaPanda 目录不是工程固定 commit：$luaPandaCommit"
}
$actualLuaSocketTag = (& $git.Source -C $luaSocket describe --tags --exact-match).Trim()
if ($LASTEXITCODE -ne 0 -or $actualLuaSocketTag -ne $luaSocketTag) {
    throw "LuaSocket 目录不是工程固定 tag：$luaSocketTag"
}

Write-Output "LuaPanda 3.3.1 与 LuaSocket $luaSocketTag 源码已准备"
