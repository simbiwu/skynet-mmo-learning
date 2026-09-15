#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."

RUNTIME_ROOT="$(pwd -P)/third_party/luapanda-runtime"
CORE_MODULE="$RUNTIME_ROOT/luaclib/socket/core.so"

if [[ ! -f "$CORE_MODULE" ]]; then
    echo "LuaPanda Runtime 缺少 $CORE_MODULE" >&2
    exit 1
fi

# 回归保护：DrvFs 上不能依赖 LuaSocket 的 chmod/install 流程；最终产物必须位于
# 工程私有目录，并且能被 Skynet Bundled Lua 5.4.7 直接加载。
LUA_CPATH="$RUNTIME_ROOT/luaclib/?.so;;" \
    ./third_party/skynet/3rd/lua/lua -e \
    'local socket = assert(require "socket.core"); assert(type(socket.tcp) == "function")'

echo "LUAPANDA_RUNTIME_OK"
