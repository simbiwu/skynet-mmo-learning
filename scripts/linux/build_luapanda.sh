#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."

./scripts/bootstrap_luapanda.sh

if [[ ! -f third_party/skynet/3rd/lua/lua.h ]]; then
    ./scripts/linux/build.sh
fi

LUA_INCLUDE="$(pwd -P)/third_party/skynet/3rd/lua"
RUNTIME_ROOT="$(pwd -P)/third_party/luapanda-runtime"

make -C third_party/luasocket/src linux \
    PLAT=linux LUAV=5.4 LUAINC_linux="$LUA_INCLUDE"

# LuaSocket 上游 install target 会执行 chmod；Windows 盘的 DrvFs 可能拒绝该操作。
# LuaPanda 只 require("socket.core")，所以显式复制唯一需要的 C Module，既绕开
# 文件系统权限差异，也避免把未使用的 FTP/SMTP/MIME 模块带进 Debug Runtime。
mkdir -p "$RUNTIME_ROOT/luaclib/socket"
cp third_party/luasocket/src/socket-3.0.0.so \
    "$RUNTIME_ROOT/luaclib/socket/core.so"

./tests/tooling/test_luapanda_runtime.sh
