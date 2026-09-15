#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."

TARGET_SERVICE="${1:-scene/scene}"
TARGET_PORT="${2:-8818}"

if [[ ! -f third_party/luapanda/Debugger/LuaPanda.lua \
    || ! -f third_party/luapanda-runtime/luaclib/socket/core.so ]]; then
    ./scripts/linux/build_luapanda.sh
fi

export LUAPANDA_SERVICE="$TARGET_SERVICE"
export LUAPANDA_HOST="127.0.0.1"
export LUAPANDA_PORT="$TARGET_PORT"

echo "LuaPanda 将只注入 Service：$LUAPANDA_SERVICE，Adapter：$LUAPANDA_HOST:$LUAPANDA_PORT"
exec ./third_party/skynet/skynet config/debug_luapanda.lua
