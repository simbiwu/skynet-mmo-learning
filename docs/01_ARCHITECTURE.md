# 01 - Architecture

## Process-level view

For this lesson everything runs inside one Skynet process:

```text
Skynet Runtime (thread=8)
|
+-- protocol/protoloader       compiled Sproto schemas
+-- config/config_service      sharedata host
+-- storage/storage_mgr
|   +-- memory_worker x N      default
|   `-- mysql_worker x N       optional mode
+-- scene/scene_mgr
|   `-- scene/scene            scene 1
+-- player/player_mgr
|   `-- player/player_agent x online players
+-- auth/auth
+-- gateway/watchdog
|   `-- official gate.lua
`-- debug_console
```

Different services can be scheduled by different Skynet worker threads. A single Lua Service is still an Actor boundary and should be designed around a coherent state ownership domain.

## State ownership

### PlayerAgent owns

- player id/name/level
- gold and future bag/task/equipment/activity state
- persistent HP snapshot
- persistent last scene/position
- connection binding to the current client
- per-player request serialization

### Scene owns

- current online position
- AOI index
- which entities each player currently sees
- monsters and monster HP
- combat distance check/damage application
- real-time scene membership
- 服务端权威地图边界与每玩家移动额度

This avoids the common mistake where both PlayerAgent and Scene independently believe their coordinate is authoritative. `PlayerAgent.player.x/y` is updated only after Scene accepts movement and serves primarily as persistence/recovery state.

移动速度额度与实时坐标放在同一个 `Scene` entity 中，因此校验和提交之间不需要跨 Service RPC。`lualib/scene/movement.lua` 只是可测试的计算模块，不拥有状态，也没有被错误地提升成一个 Service。

## Why Watchdog is retained

Before login, `fd` does not map to a known player. Official `gate.lua` sends un-forwarded packet data to Watchdog. After authentication and PlayerAgent creation, Watchdog calls gate `forward`; future packets are redirected directly to PlayerAgent. This avoids making Watchdog a permanent traffic proxy.

## Production expansion path

The current single process can later become:

```text
Gate/Game Node     -> PlayerAgent
Scene Node(s)      -> Scene shards / map lines
World Node         -> guild/rank/global activity
DB Node            -> storage workers
Chat Node          -> chat/filter
```

Use `cluster`/routing only when the process split is actually needed. Do not pre-emptively make every local call a remote-style RPC chain.
