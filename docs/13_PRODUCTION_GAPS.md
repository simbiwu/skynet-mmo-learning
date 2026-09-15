# 13 - Production Gaps

This repository is production-shaped, not production-ready.

Before using the architecture for a live MMO, address at least:

- real login/Center authentication and replay-safe one-time tokens
- protocol versioning, packet limits, rate limits and abuse handling
- pathfinding/collision validation and client prediction correction（基础地图边界与权威速度校验已由 P0 完成）
- robust skill/buff/combat timing model
- monster AI/pathfinding and per-tick CPU budgets
- dirty/versioned persistence and critical-data journal semantics
- database reconnect/retry/backpressure and observability
- graceful shutdown and mass player flush
- structured logging/trace IDs/metrics
- service mailbox and coroutine monitoring
- AOI density/pathological-hotspot protection
- scene line/shard migration protocol
- guild/world/rank/chat/cluster architecture
- config validation/versioned hot reload
- code hotfix + state migration rules
- reconnect session security
- fuzz/protocol/load/failure tests

The point of documenting gaps is to avoid mistaking "the smoke test passes" for "the MMO architecture is finished".
