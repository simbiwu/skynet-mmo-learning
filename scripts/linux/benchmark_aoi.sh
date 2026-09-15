#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
exec ./third_party/skynet/3rd/lua/lua tests/benchmark/aoi_bench.lua "$@"
