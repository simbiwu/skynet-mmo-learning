#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."

if [[ ! -x third_party/skynet/skynet ]]; then
    ./scripts/linux/build.sh
fi

./third_party/skynet/3rd/lua/lua tests/unit/run.lua
./third_party/skynet/3rd/lua/lua tests/tooling/test_client_stdin.lua
./third_party/skynet/3rd/lua/lua tests/tooling/test_luapanda_preload_order.lua
./tests/integration/smoke.sh

echo "ALL_TESTS_OK"
