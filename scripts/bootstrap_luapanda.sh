#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

LUAPANDA_COMMIT="e3ac3d3314f24cf939c36cac5b7dc1f2ed6ee129"
LUASOCKET_TAG="v3.1.0"

# DrvFs 可能拒绝 WSL Git 的 chmod；与 Skynet bootstrap 相同，在 Windows 挂载盘上
# 交给 native Windows Git，构建仍由 WSL/Linux 完成。
REPO_PATH="$(pwd -P)"
if [[ "$REPO_PATH" == /mnt/* ]] && command -v powershell.exe >/dev/null 2>&1; then
    WINDOWS_SCRIPT="$(wslpath -w "$REPO_PATH/scripts/windows/bootstrap_luapanda.ps1")"
    exec powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$WINDOWS_SCRIPT"
fi

mkdir -p third_party

remove_exact_dependency() {
    local target="$1"
    local resolved_parent
    resolved_parent="$(dirname "$(realpath -m "$target")")"
    if [[ "$resolved_parent" != "$(realpath third_party)" ]]; then
        echo "拒绝清理非预期目录：$target" >&2
        exit 1
    fi
    rm -rf -- "$target"
}

if [[ ! -f third_party/luapanda/Debugger/LuaPanda.lua ]]; then
    remove_exact_dependency third_party/luapanda
    git init third_party/luapanda
    git -C third_party/luapanda remote add origin https://github.com/Tencent/LuaPanda.git
    git -C third_party/luapanda fetch --depth 1 origin "$LUAPANDA_COMMIT"
    git -C third_party/luapanda checkout --detach FETCH_HEAD
fi

if [[ ! -f third_party/luasocket/src/makefile ]]; then
    remove_exact_dependency third_party/luasocket
    git clone --branch "$LUASOCKET_TAG" --depth 1 https://github.com/lunarmodules/luasocket.git third_party/luasocket
fi

if [[ "$(git -C third_party/luapanda rev-parse HEAD)" != "$LUAPANDA_COMMIT" ]]; then
    echo "LuaPanda 目录不是工程固定 commit：$LUAPANDA_COMMIT" >&2
    exit 1
fi
if [[ "$(git -C third_party/luasocket describe --tags --exact-match)" != "$LUASOCKET_TAG" ]]; then
    echo "LuaSocket 目录不是工程固定 tag：$LUASOCKET_TAG" >&2
    exit 1
fi

echo "已拉取 LuaPanda 3.3.1 与 LuaSocket ${LUASOCKET_TAG}"
