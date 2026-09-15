#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."

SERVER_LOG="/tmp/skynet_mmo_learning_server_$$.log"
CLIENT_LOG="/tmp/skynet_mmo_learning_client_$$.log"
CLIENT_STDIN="/tmp/skynet_mmo_learning_client_stdin_$$"

cleanup() {
    if [[ -n "${CLIENT_PID:-}" ]] && kill -0 "$CLIENT_PID" 2>/dev/null; then
        kill "$CLIENT_PID" 2>/dev/null || true
        wait "$CLIENT_PID" 2>/dev/null || true
    fi
    if [[ -n "${STDIN_KEEPER_PID:-}" ]] && kill -0 "$STDIN_KEEPER_PID" 2>/dev/null; then
        kill "$STDIN_KEEPER_PID" 2>/dev/null || true
        wait "$STDIN_KEEPER_PID" 2>/dev/null || true
    fi
    if [[ -n "${SERVER_PID:-}" ]] && kill -0 "$SERVER_PID" 2>/dev/null; then
        kill "$SERVER_PID" 2>/dev/null || true
        wait "$SERVER_PID" 2>/dev/null || true
    fi
    rm -f "$CLIENT_STDIN"
}
trap cleanup EXIT

./third_party/skynet/skynet config/test.lua >"$SERVER_LOG" 2>&1 &
SERVER_PID=$!

# Give bootstrap/gate enough time on a normal developer machine.
for _ in $(seq 1 30); do
    if ! kill -0 "$SERVER_PID" 2>/dev/null; then
        echo "Server exited during startup"
        cat "$SERVER_LOG"
        exit 1
    fi
    if grep -q "startup complete" "$SERVER_LOG" 2>/dev/null; then
        break
    fi
    sleep 0.1
done

# 官方 client.socket 在加载时创建 stdin 读取线程，并在 stdin EOF 时直接 exit(1)。
# CI/Codex 没有交互终端，所以用 FIFO 保持 stdin 开启；自动客户端不会读取其中的数据。
mkfifo "$CLIENT_STDIN"
sleep 300 >"$CLIENT_STDIN" &
STDIN_KEEPER_PID=$!
./third_party/skynet/3rd/lua/lua client/test_client.lua --auto --port=18888 --player=10001 \
    <"$CLIENT_STDIN" >"$CLIENT_LOG" 2>&1 &
CLIENT_PID=$!

# client.socket 的 stdin pthread 会让非交互 client 在主 Lua chunk 返回后等待。
# 看到业务完成标记后关闭 FIFO writer，使该 pthread 自己收到 EOF 并结束 process。
for _ in $(seq 1 300); do
    if grep -q "SMOKE_OK player=10001" "$CLIENT_LOG" 2>/dev/null; then
        break
    fi
    if ! kill -0 "$CLIENT_PID" 2>/dev/null; then
        break
    fi
    sleep 0.1
done
kill "$STDIN_KEEPER_PID" 2>/dev/null || true
wait "$STDIN_KEEPER_PID" 2>/dev/null || true
STDIN_KEEPER_PID=""
wait "$CLIENT_PID" 2>/dev/null || true
CLIENT_PID=""
cat "$CLIENT_LOG"

grep -q "SMOKE_OK player=10001" "$CLIENT_LOG"
echo "INTEGRATION_SMOKE_OK"
