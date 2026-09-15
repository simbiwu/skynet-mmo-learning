#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."

DEBUG_HOST="${1:-127.0.0.1}"
DEBUG_PORT="${2:-8000}"

if ! command -v nc >/dev/null 2>&1; then
    echo "缺少 nc。Ubuntu/Debian 请执行：sudo apt install -y netcat-openbsd"
    exit 1
fi

echo "正在连接 Skynet Debug Console ${DEBUG_HOST}:${DEBUG_PORT}；输入 help 查看命令，Ctrl+C 退出。"
if command -v rlwrap >/dev/null 2>&1; then
    exec rlwrap nc "$DEBUG_HOST" "$DEBUG_PORT"
fi
exec nc "$DEBUG_HOST" "$DEBUG_PORT"
