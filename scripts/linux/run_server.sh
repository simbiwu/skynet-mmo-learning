#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
CONFIG="${1:-config/game.lua}"
exec ./third_party/skynet/skynet "$CONFIG"
