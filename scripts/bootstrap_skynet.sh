#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="v1.8.0"
DEST="third_party/skynet"

if [[ -f "$DEST/Makefile" ]]; then
    echo "Skynet already exists at $DEST"
    echo "Expected learning baseline: $VERSION"
    exit 0
fi

# Windows 盘在 WSL 中挂载为 DrvFs 时可能拒绝 Git clone 的 chmod。若支持
# WSL interoperability，就交给 Windows wrapper 用 native Git 拉取同一固定 tag。
REPO_PATH="$(pwd -P)"
if [[ "$REPO_PATH" == /mnt/* ]] && command -v powershell.exe >/dev/null 2>&1; then
    WINDOWS_SCRIPT="$(wslpath -w "$REPO_PATH/scripts/windows/bootstrap.ps1")"
    exec powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$WINDOWS_SCRIPT"
fi

rm -rf "$DEST"
mkdir -p third_party

git clone --recursive --branch "$VERSION" --depth 1 https://github.com/cloudwu/skynet.git "$DEST"
git -C "$DEST" submodule update --init --recursive

echo "Fetched Skynet $VERSION"
