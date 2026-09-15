# 07 - Storage

## Why memory mode is default

A learning repository should prove its service/network/AOI path without requiring MySQL installation. `memory_worker.lua` exposes the same `load_player/save_player` contract as MySQL, so architecture stays visible while setup stays small.

## Worker routing

StorageMgr creates N workers and selects:

```text
worker_index = player_id % N + 1
```

The same player goes to the same worker, which makes per-player storage ordering easier to reason about.

## MySQL mode

1. Start MySQL yourself or:

```bash
docker compose -f compose.mysql.yml up -d
```

2. Change `config/game.lua`:

```lua
storage_driver = "mysql"
```

3. Start the server normally.

## What is intentionally missing

The project currently saves at final offline only. A real MMO needs at minimum:

- dirty flags / versioned snapshots
- periodic asynchronous persistence
- critical economy operation durability
- write ordering / stale snapshot protection
- retry/backpressure policy
- slow query metrics
- schema migrations
- idempotency for rewards/trades/payments

A later lesson should evolve StorageMgr from synchronous teaching RPC into a write queue with explicit persistence semantics.
